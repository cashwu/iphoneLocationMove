import Combine
import Foundation

protocol SimulationScheduling: Sendable {
    func now() async -> TimeInterval
    func waitForNextTick() async throws
}

struct SystemSimulationScheduler: SimulationScheduling {
    func now() async -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func waitForNextTick() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
}

struct PointSimulationSnapshot: Equatable, Sendable {
    let sessionID: SimulationSessionID
    let coordinate: DeviceCoordinate
}

struct RouteSimulationSnapshot: Equatable, Sendable {
    let sessionID: SimulationSessionID
    let phase: RouteSessionPhase
    let confirmedDistance: Double
    let confirmedCoordinate: RouteCoordinate?
    let confirmedDirection: RouteDirection
    let speedKilometersPerHour: Double
    let interruption: DeviceInterruption?
}

enum SimulationMode: Equatable, Sendable {
    case point
    case route
}

enum SimulationStoreState: Equatable, Sendable {
    case idle
    case starting(mode: SimulationMode, sessionID: SimulationSessionID)
    case replacing(previousSessionID: SimulationSessionID?)
    case pointActive(PointSimulationSnapshot)
    case route(RouteSimulationSnapshot, failure: DeviceLocationError?)
    case interrupted(
        sessionID: SimulationSessionID,
        interruption: DeviceInterruption,
        failure: DeviceLocationError
    )
    case stopping(sessionID: SimulationSessionID, failure: DeviceLocationError?)
}

@MainActor
final class SimulationStore: ObservableObject {
    @Published private(set) var state: SimulationStoreState = .idle

    private let device: any DeviceLocationClient
    private let generation: DeviceSessionGeneration
    private let scheduler: any SimulationScheduling
    private let diagnosticLogger: any DiagnosticLogging

    private(set) var activeSessionID: SimulationSessionID?
    private var routeSession: RouteSession?
    private var producerTask: Task<Void, Never>?
    private var inFlightMutation: Task<Void, Error>?
    private var inFlightToken: RouteUpdateToken?
    private var commandInProgress = false
    private var lastMonotonicInstant: TimeInterval = 0

    init(
        device: any DeviceLocationClient,
        generation: DeviceSessionGeneration,
        scheduler: any SimulationScheduling = SystemSimulationScheduler(),
        diagnosticLogger: any DiagnosticLogging = NullDiagnosticLogger()
    ) {
        self.device = device
        self.generation = generation
        self.scheduler = scheduler
        self.diagnosticLogger = diagnosticLogger
    }

    var routeSnapshot: RouteSimulationSnapshot? {
        guard case let .route(snapshot, _) = state else {
            return nil
        }
        return snapshot
    }

    func confirmPoint(
        _ coordinate: DeviceCoordinate,
        riskAccepted: Bool
    ) async {
        guard riskAccepted, !commandInProgress else {
            return
        }
        commandInProgress = true
        defer { commandInProgress = false }

        await prepareForReplacement()
        let sessionID = SimulationSessionID()
        diagnosticLogger.record(
            .info,
            category: "simulation",
            event: "point.start_requested",
            metadata: [
                "sessionID": sessionID.rawValue.uuidString,
                "generation": String(generation.rawValue),
            ]
        )
        state = .starting(mode: .point, sessionID: sessionID)
        do {
            try await device.setLocation(
                coordinate,
                context: DeviceMutationContext(
                    simulationSessionID: sessionID,
                    generation: generation
                )
            )
            activeSessionID = sessionID
            state = .pointActive(
                PointSimulationSnapshot(
                    sessionID: sessionID,
                    coordinate: coordinate
                )
            )
            diagnosticLogger.record(
                .info,
                category: "simulation",
                event: "point.started",
                metadata: ["sessionID": sessionID.rawValue.uuidString]
            )
        } catch {
            diagnosticLogger.record(
                .error,
                category: "simulation",
                event: "point.start_failed",
                metadata: [
                    "sessionID": sessionID.rawValue.uuidString,
                    "failure": String(describing: error),
                ]
            )
            publishInitialMutationFailure(error, candidateSessionID: sessionID)
        }
    }

    func startRoute(
        preview: RoutePreview,
        speedKilometersPerHour: Double,
        roundTrip: Bool,
        riskAccepted: Bool
    ) async throws {
        guard riskAccepted, !commandInProgress else {
            return
        }
        commandInProgress = true
        defer { commandInProgress = false }

        await prepareForReplacement()
        let sessionID = SimulationSessionID()
        diagnosticLogger.record(
            .info,
            category: "simulation",
            event: "route.start_requested",
            metadata: [
                "sessionID": sessionID.rawValue.uuidString,
                "generation": String(generation.rawValue),
                "roundTrip": String(roundTrip),
                "speedKPH": String(speedKilometersPerHour),
            ]
        )
        let route = try RouteSession(
            speedKilometersPerHour: speedKilometersPerHour,
            roundTrip: roundTrip
        )
        try route.loadPreview(preview)
        routeSession = route
        state = .starting(mode: .route, sessionID: sessionID)

        let firstCoordinate = try deviceCoordinate(
            from: preview.points[0].coordinate
        )
        do {
            try await device.setLocation(
                firstCoordinate,
                context: DeviceMutationContext(
                    simulationSessionID: sessionID,
                    generation: generation
                )
            )
            let instant = await scheduler.now()
            try route.start(at: instant)
            lastMonotonicInstant = instant
            activeSessionID = sessionID
            publishRouteState()
            startProducer(for: sessionID)
            await Task.yield()
            diagnosticLogger.record(
                .info,
                category: "simulation",
                event: "route.started",
                metadata: ["sessionID": sessionID.rawValue.uuidString]
            )
        } catch let routeError as RouteSessionError {
            diagnosticLogger.record(
                .error,
                category: "simulation",
                event: "route.start_failed",
                metadata: [
                    "sessionID": sessionID.rawValue.uuidString,
                    "failure": String(describing: routeError),
                ]
            )
            routeSession = nil
            throw routeError
        } catch {
            let failure = deviceFailure(from: error)
            diagnosticLogger.record(
                .error,
                category: "simulation",
                event: "route.start_failed",
                metadata: [
                    "sessionID": sessionID.rawValue.uuidString,
                    "failure": String(describing: failure),
                ]
            )
            try route.startFailed(reason: interruptionReason(for: failure))
            activeSessionID = sessionID
            state = .interrupted(
                sessionID: sessionID,
                interruption: DeviceInterruption(
                    reason: interruptionReason(for: failure),
                    positionKnowledge: .unknown
                ),
                failure: failure
            )
        }
    }

    func tick(at instant: TimeInterval) throws {
        try tick(at: instant, expectedSessionID: activeSessionID)
    }

    func pause() throws {
        guard let routeSession else {
            return
        }
        producerTask?.cancel()
        producerTask = nil
        _ = try routeSession.pause()
        publishRouteState()
        diagnosticLogger.record(.info, category: "simulation", event: "route.paused")
    }

    func resume(at instant: TimeInterval) throws {
        guard let routeSession, let activeSessionID else {
            return
        }
        try routeSession.resume(at: instant)
        lastMonotonicInstant = instant
        publishRouteState()
        startProducer(for: activeSessionID)
        diagnosticLogger.record(.info, category: "simulation", event: "route.resumed")
    }

    func setSpeed(_ speedKilometersPerHour: Double, at instant: TimeInterval) throws {
        guard let routeSession else {
            return
        }
        try routeSession.setSpeed(
            kilometersPerHour: speedKilometersPerHour,
            at: instant
        )
        lastMonotonicInstant = instant
        publishRouteState()
        diagnosticLogger.record(
            .info,
            category: "simulation",
            event: "route.speed_changed",
            metadata: ["speedKPH": String(speedKilometersPerHour)]
        )
    }

    func stop() async {
        guard let sessionID = activeSessionID else {
            return
        }
        diagnosticLogger.record(
            .info,
            category: "simulation",
            event: "stop_requested",
            metadata: ["sessionID": sessionID.rawValue.uuidString]
        )

        producerTask?.cancel()
        producerTask = nil
        if let routeSession, routeSession.phase != .stopping {
            try? routeSession.requestStop()
        }
        state = .stopping(sessionID: sessionID, failure: nil)

        let currentMutation = inFlightMutation
        inFlightToken = nil
        if let currentMutation {
            _ = await currentMutation.result
        }
        inFlightMutation = nil

        do {
            try await device.clearLocation(
                context: DeviceCleanupContext(generation: generation)
            )
            if let routeSession, routeSession.phase == .stopping {
                try? routeSession.clearSucceeded()
            }
            self.routeSession = nil
            activeSessionID = nil
            state = .idle
            diagnosticLogger.record(
                .info,
                category: "simulation",
                event: "stopped",
                metadata: ["sessionID": sessionID.rawValue.uuidString]
            )
        } catch {
            let failure = deviceFailure(from: error)
            diagnosticLogger.record(
                .error,
                category: "simulation",
                event: "stop_failed",
                metadata: [
                    "sessionID": sessionID.rawValue.uuidString,
                    "failure": String(describing: failure),
                ]
            )
            if let routeSession, routeSession.phase == .stopping {
                try? routeSession.clearFailed()
            }
            state = .stopping(sessionID: sessionID, failure: failure)
        }
    }

    func handleDeviceInterruption(_ interruption: DeviceInterruption) {
        guard let sessionID = activeSessionID else {
            return
        }
        diagnosticLogger.record(
            .warning,
            category: "simulation",
            event: "device_interrupted",
            metadata: [
                "sessionID": sessionID.rawValue.uuidString,
                "reason": String(describing: interruption.reason),
                "positionKnowledge": String(describing: interruption.positionKnowledge),
            ]
        )
        producerTask?.cancel()
        producerTask = nil
        inFlightToken = nil
        if let routeSession {
            try? routeSession.interrupt(
                reason: interruption.reason,
                positionKnowledge: interruption.positionKnowledge
            )
            publishRouteState(failure: failure(for: interruption.reason))
        } else {
            state = .interrupted(
                sessionID: sessionID,
                interruption: interruption,
                failure: failure(for: interruption.reason)
            )
        }
    }

    func systemWillSleep() {
        guard let routeSession else {
            return
        }
        do {
            guard try routeSession.handleSleep() else {
                return
            }
            producerTask?.cancel()
            producerTask = nil
            publishRouteState()
        } catch {
            interruptRouteForInternalFailure()
        }
    }

    func systemDidWake() {
        // A pausing transaction is completed only by its in-flight/correction
        // device reply. Wake never resumes route progress automatically.
        publishRouteState()
    }

    private func tick(
        at instant: TimeInterval,
        expectedSessionID: SimulationSessionID?
    ) throws {
        guard
            let expectedSessionID,
            expectedSessionID == activeSessionID,
            let routeSession
        else {
            return
        }
        lastMonotonicInstant = max(lastMonotonicInstant, instant)
        if let update = try routeSession.tick(at: instant) {
            dispatch(update, sessionID: expectedSessionID)
        }
        publishRouteState()
    }

    private func startProducer(for sessionID: SimulationSessionID) {
        producerTask?.cancel()
        producerTask = Task { [weak self, scheduler] in
            while !Task.isCancelled {
                do {
                    try await scheduler.waitForNextTick()
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else {
                    return
                }
                let instant = await scheduler.now()
                do {
                    try self.tick(at: instant, expectedSessionID: sessionID)
                } catch {
                    self.interruptRouteForInternalFailure()
                    return
                }
            }
        }
    }

    private func dispatch(
        _ update: RouteUpdate,
        sessionID: SimulationSessionID
    ) {
        guard inFlightMutation == nil else {
            return
        }
        let device = self.device
        let generation = self.generation
        let mutation = Task {
            try await device.setLocation(
                try deviceCoordinate(from: update.coordinate),
                context: DeviceMutationContext(
                    simulationSessionID: sessionID,
                    generation: generation
                )
            )
        }
        inFlightMutation = mutation
        inFlightToken = update.token

        Task { [weak self, scheduler] in
            let result = await mutation.result
            let instant = await scheduler.now()
            self?.complete(
                update: update,
                sessionID: sessionID,
                result: result,
                at: instant
            )
        }
    }

    private func complete(
        update: RouteUpdate,
        sessionID: SimulationSessionID,
        result: Result<Void, Error>,
        at instant: TimeInterval
    ) {
        guard
            sessionID == activeSessionID,
            update.token == inFlightToken,
            let routeSession
        else {
            return
        }
        inFlightMutation = nil
        inFlightToken = nil
        let completionInstant = max(instant, lastMonotonicInstant)
        lastMonotonicInstant = completionInstant

        let routeResult: RouteUpdateResult
        var failure: DeviceLocationError?
        switch result {
        case .success:
            routeResult = .success
        case let .failure(error):
            let typedFailure = deviceFailure(from: error)
            diagnosticLogger.record(
                .error,
                category: "simulation",
                event: "route.update_failed",
                metadata: [
                    "sessionID": sessionID.rawValue.uuidString,
                    "failure": String(describing: typedFailure),
                ]
            )
            failure = typedFailure
            routeResult = .uncertain(interruptionReason(for: typedFailure))
        }

        do {
            let next = try routeSession.completeUpdate(
                update.token,
                result: routeResult,
                at: completionInstant
            )
            publishRouteState(failure: failure)
            if routeSession.phase == .completed || routeSession.phase == .interrupted {
                producerTask?.cancel()
                producerTask = nil
            }
            if let next {
                dispatch(next, sessionID: sessionID)
            }
        } catch {
            interruptRouteForInternalFailure()
        }
    }

    private func prepareForReplacement() async {
        let previousSessionID = activeSessionID
        guard previousSessionID != nil else {
            routeSession = nil
            return
        }

        state = .replacing(previousSessionID: previousSessionID)
        producerTask?.cancel()
        producerTask = nil
        activeSessionID = nil
        inFlightToken = nil
        if let routeSession, routeSession.phase != .stopping {
            try? routeSession.requestStop()
        }
        let currentMutation = inFlightMutation
        if let currentMutation {
            _ = await currentMutation.result
        }
        inFlightMutation = nil
        routeSession = nil
    }

    private func publishInitialMutationFailure(
        _ error: Error,
        candidateSessionID: SimulationSessionID
    ) {
        let failure = deviceFailure(from: error)
        let interruption = DeviceInterruption(
            reason: interruptionReason(for: failure),
            positionKnowledge: .unknown
        )
        activeSessionID = candidateSessionID
        state = .interrupted(
            sessionID: candidateSessionID,
            interruption: interruption,
            failure: failure
        )
    }

    private func publishRouteState(failure: DeviceLocationError? = nil) {
        guard let routeSession, let activeSessionID else {
            return
        }
        state = .route(
            RouteSimulationSnapshot(
                sessionID: activeSessionID,
                phase: routeSession.phase,
                confirmedDistance: routeSession.confirmedDistance,
                confirmedCoordinate: routeSession.confirmedCoordinate,
                confirmedDirection: routeSession.confirmedDirection,
                speedKilometersPerHour: routeSession.speedKilometersPerHour,
                interruption: routeSession.interruption
            ),
            failure: failure
        )
    }

    private func interruptRouteForInternalFailure() {
        guard let routeSession else {
            return
        }
        try? routeSession.interrupt(
            reason: .transportFailure,
            positionKnowledge: .unknown
        )
        producerTask?.cancel()
        producerTask = nil
        publishRouteState(failure: .transportFailure("Route orchestration failed"))
    }

    private func deviceCoordinate(from coordinate: RouteCoordinate) throws -> DeviceCoordinate {
        try DeviceCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private func deviceFailure(from error: Error) -> DeviceLocationError {
        if let typed = error as? DeviceLocationError {
            return typed
        }
        return .transportFailure(error.localizedDescription)
    }

    private func interruptionReason(
        for failure: DeviceLocationError
    ) -> InterruptionReason {
        switch failure {
        case .timeout:
            return .timeout
        case .usbDisconnected:
            return .usbDisconnected
        case .authorizationDenied:
            return .authorizationDenied
        case .helperFailure:
            return .helperExited
        case .tunnelFailure:
            return .tunnelEnded
        default:
            return .transportFailure
        }
    }

    private func failure(for reason: InterruptionReason) -> DeviceLocationError {
        switch reason {
        case .timeout:
            return .timeout
        case .usbDisconnected:
            return .usbDisconnected
        case .authorizationDenied:
            return .authorizationDenied
        case .helperExited:
            return .helperFailure("DVT helper exited")
        case .tunnelEnded:
            return .tunnelFailure("Tunnel ended")
        case .deviceMutationFailed, .transportFailure:
            return .transportFailure("Device mutation failed")
        }
    }
}

extension SimulationStore: SystemSleepHandling {}
