import Foundation

struct RouteCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct RoutePoint: Equatable, Sendable {
    let coordinate: RouteCoordinate
    let cumulativeDistance: Double

    init(coordinate: RouteCoordinate, cumulativeDistance: Double) {
        self.coordinate = coordinate
        self.cumulativeDistance = cumulativeDistance
    }
}

struct RoutePreview: Equatable, Sendable {
    let points: [RoutePoint]
    let totalDistance: Double

    init(points: [RoutePoint]) throws {
        guard points.count >= 2 else {
            throw RouteSessionError.invalidRoute
        }
        guard points[0].cumulativeDistance == 0 else {
            throw RouteSessionError.invalidRoute
        }

        var previousDistance = -Double.infinity
        for point in points {
            guard point.coordinate.latitude.isFinite,
                  (-90 ... 90).contains(point.coordinate.latitude),
                  point.coordinate.longitude.isFinite,
                  (-180 ... 180).contains(point.coordinate.longitude),
                  point.cumulativeDistance.isFinite,
                  point.cumulativeDistance >= 0,
                  point.cumulativeDistance > previousDistance
            else {
                throw RouteSessionError.invalidRoute
            }
            previousDistance = point.cumulativeDistance
        }

        guard previousDistance > 0 else {
            throw RouteSessionError.invalidRoute
        }
        self.points = points
        totalDistance = previousDistance
    }
}

struct RouteUpdateEpoch: RawRepresentable, Equatable, Hashable, Sendable {
    let rawValue: UInt64
}

struct RouteUpdateToken: Equatable, Hashable, Sendable {
    let epoch: RouteUpdateEpoch
    let sequence: UInt64
}

enum RouteDirection: Equatable, Sendable {
    case towardA
    case towardB
}

enum RouteUpdateResult: Equatable, Sendable {
    case success
    case uncertain(InterruptionReason)
}

enum RouteUpdateKind: Equatable, Sendable {
    case routeProgress
    case pauseCorrection
}

struct RouteUpdate: Equatable, Sendable {
    let token: RouteUpdateToken
    let coordinate: RouteCoordinate
    let distanceFromA: Double
    let direction: RouteDirection
    let kind: RouteUpdateKind
}

enum RouteSessionPhase: Equatable, Sendable {
    case idle
    case preview
    case running
    case pausing
    case paused
    case completed
    case interrupted
    case stopping
}

enum RouteSessionEvent: Equatable, Sendable {
    case loadPreview
    case cancelPreview
    case start
    case startFailed
    case pause
    case resume
    case stop
    case clearSucceeded
    case clearFailed
    case interrupt
    case setSpeed
}

enum RouteSessionError: Error, Equatable, Sendable {
    case invalidRoute
    case invalidSpeed
    case invalidMonotonicInstant
    case clockMovedBackwards
    case identityExhausted
    case invalidTransition(from: RouteSessionPhase, event: RouteSessionEvent)
}

final class RouteSession {
    static let defaultSpeedKilometersPerHour = 4.5
    static let allowedSpeedRange = 1.0 ... 7.0
    static let updateInterval: TimeInterval = 1

    private struct Target: Equatable {
        let travelledDistance: Double
        let distanceFromA: Double
        let coordinate: RouteCoordinate
        let direction: RouteDirection
        let completesSingleTrip: Bool
    }

    private struct InFlight {
        let update: RouteUpdate
        let target: Target
    }

    private struct PauseSnapshot {
        let target: Target
    }

    private enum Barrier {
        case pause(PauseSnapshot)
        case speed(kilometersPerHour: Double)
    }

    private(set) var phase: RouteSessionPhase = .idle
    private(set) var interruption: DeviceInterruption?
    private(set) var speedKilometersPerHour: Double
    private(set) var currentEpoch = RouteUpdateEpoch(rawValue: 0)

    let roundTrip: Bool

    private var preview: RoutePreview?
    private var baselineTravelledDistance: Double = 0
    private var baselineInstant: TimeInterval = 0
    private var lastObservedInstant: TimeInterval?
    private var lastScheduledInstant: TimeInterval = 0
    private var confirmedTarget: Target?
    private var inFlight: InFlight?
    private var pendingTarget: Target?
    private var barrier: Barrier?
    private var nextSequence: UInt64 = 0

    init(
        speedKilometersPerHour: Double = RouteSession.defaultSpeedKilometersPerHour,
        roundTrip: Bool = false
    ) throws {
        guard Self.isValidSpeed(speedKilometersPerHour) else {
            throw RouteSessionError.invalidSpeed
        }
        self.speedKilometersPerHour = speedKilometersPerHour
        self.roundTrip = roundTrip
    }

    var confirmedDistance: Double {
        confirmedTarget?.distanceFromA ?? 0
    }

    var confirmedCoordinate: RouteCoordinate? {
        confirmedTarget?.coordinate
    }

    var confirmedDirection: RouteDirection {
        confirmedTarget?.direction ?? .towardB
    }

    var pendingDistance: Double? {
        pendingTarget?.distanceFromA
    }

    var estimatedDuration: TimeInterval {
        guard let preview else {
            return 0
        }
        return preview.totalDistance / metersPerSecond
    }

    func loadPreview(_ preview: RoutePreview) throws {
        guard phase == .idle else {
            throw invalidTransition(.loadPreview)
        }
        self.preview = preview
        confirmedTarget = target(forTravelledDistance: 0, on: preview)
        interruption = nil
        phase = .preview
    }

    func cancelPreview() throws {
        guard phase == .preview else {
            throw invalidTransition(.cancelPreview)
        }
        resetToIdle()
    }

    func start(at instant: TimeInterval) throws {
        guard phase == .preview, let preview else {
            throw invalidTransition(.start)
        }
        try validateInstant(instant)
        try advanceEpoch()

        confirmedTarget = target(forTravelledDistance: 0, on: preview)
        baselineTravelledDistance = 0
        baselineInstant = instant
        lastObservedInstant = instant
        lastScheduledInstant = instant
        interruption = nil
        phase = .running
    }

    func startFailed(reason: InterruptionReason) throws {
        guard phase == .preview else {
            throw invalidTransition(.startFailed)
        }
        transitionToInterrupted(reason: reason, positionKnowledge: .unknown)
    }

    @discardableResult
    func tick(at instant: TimeInterval) throws -> RouteUpdate? {
        guard phase == .running else {
            return nil
        }
        try observe(instant)
        guard instant - lastScheduledInstant >= Self.updateInterval else {
            return nil
        }
        lastScheduledInstant = instant

        guard let preview else {
            throw RouteSessionError.invalidRoute
        }
        let elapsed = instant - baselineInstant
        let travelledDistance = baselineTravelledDistance + elapsed * metersPerSecond
        let target = target(forTravelledDistance: travelledDistance, on: preview)

        guard inFlight == nil else {
            pendingTarget = target
            return nil
        }
        return try dispatch(target, kind: .routeProgress)
    }

    @discardableResult
    func completeUpdate(
        _ token: RouteUpdateToken,
        result: RouteUpdateResult,
        at instant: TimeInterval
    ) throws -> RouteUpdate? {
        guard let current = inFlight, current.update.token == token else {
            return nil
        }
        try observe(instant)
        inFlight = nil

        switch result {
        case .uncertain(let reason):
            transitionToInterrupted(reason: reason, positionKnowledge: .unknown)
            return nil
        case .success:
            break
        }

        if let barrier {
            switch barrier {
            case .pause(let snapshot):
                if current.update.kind == .pauseCorrection {
                    commit(snapshot.target)
                    self.barrier = nil
                    phase = .paused
                    return nil
                }

                commit(current.target)
                if current.target.coordinate == snapshot.target.coordinate,
                   current.target.distanceFromA == snapshot.target.distanceFromA
                {
                    self.barrier = nil
                    phase = .paused
                    return nil
                }
                return try dispatch(snapshot.target, kind: .pauseCorrection)

            case .speed(let newSpeed):
                commit(current.target)
                self.barrier = nil
                applySpeed(newSpeed, at: instant)
                if current.target.completesSingleTrip {
                    phase = .completed
                }
                return nil
            }
        }

        guard current.update.token.epoch == currentEpoch else {
            return nil
        }
        commit(current.target)

        if current.target.completesSingleTrip {
            pendingTarget = nil
            phase = .completed
            return nil
        }

        if let pendingTarget {
            self.pendingTarget = nil
            return try dispatch(pendingTarget, kind: .routeProgress)
        }
        return nil
    }

    @discardableResult
    func pause() throws -> RouteUpdate? {
        guard phase == .running else {
            throw invalidTransition(.pause)
        }
        guard let confirmedTarget else {
            throw RouteSessionError.invalidRoute
        }
        try advanceEpoch()
        pendingTarget = nil
        phase = .pausing

        if inFlight == nil {
            phase = .paused
            return nil
        }
        barrier = .pause(PauseSnapshot(target: confirmedTarget))
        return nil
    }

    func resume(at instant: TimeInterval) throws {
        guard phase == .paused, let confirmedTarget else {
            throw invalidTransition(.resume)
        }
        try observe(instant)
        try advanceEpoch()
        baselineTravelledDistance = confirmedTarget.travelledDistance
        baselineInstant = instant
        lastScheduledInstant = instant
        phase = .running
    }

    func setSpeed(kilometersPerHour: Double, at instant: TimeInterval) throws {
        guard phase == .running || phase == .paused else {
            throw invalidTransition(.setSpeed)
        }
        guard Self.isValidSpeed(kilometersPerHour) else {
            throw RouteSessionError.invalidSpeed
        }
        try observe(instant)
        try advanceEpoch()
        pendingTarget = nil

        if inFlight != nil {
            barrier = .speed(kilometersPerHour: kilometersPerHour)
        } else {
            applySpeed(kilometersPerHour, at: instant)
        }
    }

    @discardableResult
    func handleSleep() throws -> Bool {
        guard phase == .running else {
            return false
        }
        _ = try pause()
        return true
    }

    func interrupt(
        reason: InterruptionReason,
        positionKnowledge: PositionKnowledge
    ) throws {
        guard phase == .running
                || phase == .pausing
                || phase == .paused
                || phase == .completed
        else {
            throw invalidTransition(.interrupt)
        }
        transitionToInterrupted(
            reason: reason,
            positionKnowledge: positionKnowledge
        )
    }

    func requestStop() throws {
        guard phase == .running
                || phase == .pausing
                || phase == .paused
                || phase == .completed
                || phase == .interrupted
        else {
            throw invalidTransition(.stop)
        }
        try advanceEpoch()
        inFlight = nil
        pendingTarget = nil
        barrier = nil
        phase = .stopping
    }

    func clearSucceeded() throws {
        guard phase == .stopping else {
            throw invalidTransition(.clearSucceeded)
        }
        resetToIdle()
    }

    func clearFailed() throws {
        guard phase == .stopping else {
            throw invalidTransition(.clearFailed)
        }
    }

    private var metersPerSecond: Double {
        speedKilometersPerHour / 3.6
    }

    private static func isValidSpeed(_ speed: Double) -> Bool {
        speed.isFinite && allowedSpeedRange.contains(speed)
    }

    private func applySpeed(_ speed: Double, at instant: TimeInterval) {
        speedKilometersPerHour = speed
        baselineTravelledDistance = confirmedTarget?.travelledDistance ?? 0
        baselineInstant = instant
        lastScheduledInstant = instant
    }

    private func dispatch(
        _ target: Target,
        kind: RouteUpdateKind
    ) throws -> RouteUpdate {
        guard nextSequence < UInt64.max else {
            throw RouteSessionError.identityExhausted
        }
        nextSequence += 1
        let update = RouteUpdate(
            token: RouteUpdateToken(
                epoch: currentEpoch,
                sequence: nextSequence
            ),
            coordinate: target.coordinate,
            distanceFromA: target.distanceFromA,
            direction: target.direction,
            kind: kind
        )
        inFlight = InFlight(update: update, target: target)
        return update
    }

    private func commit(_ target: Target) {
        confirmedTarget = target
    }

    private func target(
        forTravelledDistance travelledDistance: Double,
        on preview: RoutePreview
    ) -> Target {
        if !roundTrip {
            let distance = min(travelledDistance, preview.totalDistance)
            return Target(
                travelledDistance: distance,
                distanceFromA: distance,
                coordinate: coordinate(at: distance, on: preview),
                direction: .towardB,
                completesSingleTrip: travelledDistance >= preview.totalDistance
            )
        }

        let period = preview.totalDistance * 2
        let cycleDistance = travelledDistance.truncatingRemainder(dividingBy: period)
        let distanceFromA: Double
        let direction: RouteDirection
        if cycleDistance <= preview.totalDistance {
            distanceFromA = cycleDistance
            direction = .towardB
        } else {
            distanceFromA = period - cycleDistance
            direction = .towardA
        }
        return Target(
            travelledDistance: travelledDistance,
            distanceFromA: distanceFromA,
            coordinate: coordinate(at: distanceFromA, on: preview),
            direction: direction,
            completesSingleTrip: false
        )
    }

    private func coordinate(
        at distance: Double,
        on preview: RoutePreview
    ) -> RouteCoordinate {
        if distance <= 0 {
            return preview.points[0].coordinate
        }
        if distance >= preview.totalDistance {
            return preview.points[preview.points.count - 1].coordinate
        }

        for index in 1 ..< preview.points.count {
            let end = preview.points[index]
            guard distance <= end.cumulativeDistance else {
                continue
            }
            let start = preview.points[index - 1]
            let segmentDistance = end.cumulativeDistance - start.cumulativeDistance
            let fraction = (distance - start.cumulativeDistance) / segmentDistance
            return RouteCoordinate(
                latitude: start.coordinate.latitude
                    + (end.coordinate.latitude - start.coordinate.latitude) * fraction,
                longitude: start.coordinate.longitude
                    + (end.coordinate.longitude - start.coordinate.longitude) * fraction
            )
        }

        return preview.points[preview.points.count - 1].coordinate
    }

    private func transitionToInterrupted(
        reason: InterruptionReason,
        positionKnowledge: PositionKnowledge
    ) {
        inFlight = nil
        pendingTarget = nil
        barrier = nil
        interruption = DeviceInterruption(
            reason: reason,
            positionKnowledge: positionKnowledge
        )
        phase = .interrupted
    }

    private func resetToIdle() {
        phase = .idle
        preview = nil
        interruption = nil
        baselineTravelledDistance = 0
        baselineInstant = 0
        lastObservedInstant = nil
        lastScheduledInstant = 0
        confirmedTarget = nil
        inFlight = nil
        pendingTarget = nil
        barrier = nil
    }

    private func observe(_ instant: TimeInterval) throws {
        try validateInstant(instant)
        if let lastObservedInstant, instant < lastObservedInstant {
            throw RouteSessionError.clockMovedBackwards
        }
        lastObservedInstant = instant
    }

    private func validateInstant(_ instant: TimeInterval) throws {
        guard instant.isFinite, instant >= 0 else {
            throw RouteSessionError.invalidMonotonicInstant
        }
    }

    private func advanceEpoch() throws {
        guard currentEpoch.rawValue < UInt64.max else {
            throw RouteSessionError.identityExhausted
        }
        currentEpoch = RouteUpdateEpoch(rawValue: currentEpoch.rawValue + 1)
    }

    private func invalidTransition(_ event: RouteSessionEvent) -> RouteSessionError {
        .invalidTransition(from: phase, event: event)
    }
}
