import Foundation
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class DisconnectReconnectIntegrationTests: XCTestCase {
    func testDisconnectStopsRouteProducerAndPublishesUnknownPosition() async throws {
        let device = try makeRecoveryDevice()
        let boundary = RecoveryBoundary(device: device)
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        let scheduler = RecoveryScheduler()
        let simulation = SimulationStore(
            device: adapter,
            generation: session.generation,
            scheduler: scheduler
        )
        let coordinator = DeviceRecoveryCoordinator(
            adapter: adapter,
            simulation: simulation
        )
        try await simulation.startRoute(
            preview: makeRecoveryRoute(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await scheduler.waitUntilWaiting()
        await scheduler.advance(to: 1)
        await boundary.waitForSetCount(2)

        await coordinator.handleUSBDisconnect(deviceID: device.id)
        let setCountAfterDisconnect = await boundary.setCount
        await scheduler.advance(to: 2)
        await Task.yield()

        let finalSetCount = await boundary.setCount
        XCTAssertEqual(finalSetCount, setCountAfterDisconnect)
        guard case let .route(snapshot, failure) = simulation.state else {
            return XCTFail("Route must remain owned in an interrupted phase")
        }
        XCTAssertEqual(snapshot.phase, .interrupted)
        XCTAssertEqual(
            snapshot.interruption,
            DeviceInterruption(
                reason: .usbDisconnected,
                positionKnowledge: .unknown
            )
        )
        XCTAssertEqual(failure, .usbDisconnected)
        let adapterState = await adapter.state
        XCTAssertEqual(
            adapterState,
            .interrupted(
                session: session,
                interruption: DeviceInterruption(
                    reason: .usbDisconnected,
                    positionKnowledge: .unknown
                )
            )
        )
    }

    func testReconnectBuildsNewGenerationClearsBeforeReadyAndDoesNotResume() async throws {
        let device = try makeRecoveryDevice()
        let boundary = RecoveryBoundary(device: device)
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let oldSession = try await adapter.connect()
        let scheduler = RecoveryScheduler()
        let simulation = SimulationStore(
            device: adapter,
            generation: oldSession.generation,
            scheduler: scheduler
        )
        let coordinator = DeviceRecoveryCoordinator(
            adapter: adapter,
            simulation: simulation
        )
        await simulation.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        await coordinator.handleUSBDisconnect(deviceID: device.id)
        await boundary.resetEvents()

        let reconnected = try await coordinator.reconnect()

        XCTAssertEqual(reconnected.generation, DeviceSessionGeneration(rawValue: 3))
        let adapterState = await adapter.state
        XCTAssertEqual(adapterState, .ready(reconnected))
        let events = await boundary.events
        XCTAssertEqual(
            events,
            [.startDVT(reconnected.generation), .clear(reconnected.generation)]
        )
        guard case .interrupted = simulation.state else {
            return XCTFail("Old simulation must remain interrupted")
        }
    }

    func testReconnectClearFailureStaysNonReadyAndRetryable() async throws {
        let device = try makeRecoveryDevice()
        let boundary = RecoveryBoundary(device: device)
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let oldSession = try await adapter.connect()
        let simulation = SimulationStore(
            device: adapter,
            generation: oldSession.generation
        )
        let coordinator = DeviceRecoveryCoordinator(
            adapter: adapter,
            simulation: simulation
        )
        await simulation.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        await coordinator.handleUSBDisconnect(deviceID: device.id)
        await boundary.failNextClear()

        do {
            _ = try await coordinator.reconnect()
            XCTFail("Expected reconnect clear failure")
        } catch let failure as DeviceLocationError {
            XCTAssertEqual(failure, .clearFailed("reconnect clear failed"))
        }

        guard case let .cleanupPending(newSession, failure) = await adapter.state else {
            return XCTFail("Adapter must remain non-ready with cleanup ownership")
        }
        XCTAssertEqual(newSession.generation, DeviceSessionGeneration(rawValue: 3))
        XCTAssertEqual(failure, .clearFailed("reconnect clear failed"))
    }

    func testTunnelExitedDuringPointStartAutoReconnectsAndRunsOnTheNewGeneration()
        async throws
    {
        let device = try makeRecoveryDevice()
        let boundary = RecoveryBoundary(device: device)
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        let simulation = SimulationStore(
            device: adapter,
            generation: session.generation,
            scheduler: RecoveryScheduler()
        )
        await boundary.setTunnelStatus(.exited)
        await boundary.failNextSet(transportClosedFailure())

        await simulation.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )

        guard case .pointActive = simulation.state else {
            return XCTFail("Expected the replayed set to publish point active")
        }
        guard case let .ready(newSession) = await adapter.state else {
            return XCTFail("Expected the adapter to be ready again")
        }
        XCTAssertGreaterThan(
            newSession.generation.rawValue,
            session.generation.rawValue
        )
        XCTAssertEqual(simulation.generation, newSession.generation)
    }

    func testReconnectClearFailureIsRecoveredByStoppingAgain() async throws {
        let device = try makeRecoveryDevice()
        let boundary = RecoveryBoundary(device: device)
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        let simulation = SimulationStore(
            device: adapter,
            generation: session.generation,
            scheduler: RecoveryScheduler()
        )
        await boundary.setTunnelStatus(.exited)
        await boundary.failNextSet(transportClosedFailure())
        await boundary.failNextClear()

        await simulation.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )

        guard case let .interrupted(_, _, failure) = simulation.state else {
            return XCTFail("Expected interrupted after the reconnect clear failed")
        }
        XCTAssertEqual(failure, .clearFailed("reconnect clear failed"))
        guard case .cleanupPending = await adapter.state else {
            return XCTFail("Expected the adapter to keep cleanup ownership")
        }

        await simulation.stop()

        XCTAssertEqual(simulation.state, .idle)
        XCTAssertNil(simulation.activeSessionID)
        guard case let .ready(finalSession) = await adapter.state else {
            return XCTFail("Expected the second reconnect to reach ready")
        }
        XCTAssertEqual(simulation.generation, finalSession.generation)
    }

    private func makeRecoveryDevice() throws -> USBDevice {
        try USBDevice(
            id: DeviceID("00008110-001234567890001E"),
            name: "iPhone",
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 17,
                minorVersion: 6,
                patchVersion: 1
            )
        )
    }

    private func makeRecoveryRoute() throws -> RoutePreview {
        try RoutePreview(points: [
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 25, longitude: 121),
                cumulativeDistance: 0
            ),
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 25.001, longitude: 121),
                cumulativeDistance: 100
            ),
        ])
    }
}

private func transportClosedFailure() -> DeviceLocationError {
    .transportClosed(
        DeviceBackendFailure(
            code: .transportClosed,
            exceptionType: "ConnectionTerminatedError",
            errorNumber: nil
        )
    )
}

private enum RecoveryBoundaryEvent: Equatable, Sendable {
    case startDVT(DeviceSessionGeneration)
    case set(DeviceSessionGeneration)
    case clear(DeviceSessionGeneration)
}

private actor RecoveryBoundary: PymobiledeviceBoundary {
    let device: USBDevice
    private(set) var events: [RecoveryBoundaryEvent] = []
    private(set) var setCount = 0
    private var shouldFailNextClear = false
    private var nextSetFailure: DeviceLocationError?
    private var tunnelLeaseState: DeviceTunnelLeaseState = .running

    init(device: USBDevice) {
        self.device = device
    }

    func inspectRuntime() async -> RuntimeAvailability {
        .ready(
            RuntimeInstallation(
                executableURL: URL(fileURLWithPath: "/runtime/pymobiledevice3"),
                source: .existing
            )
        )
    }

    func discoverUSBDevices(runtime: RuntimeInstallation) async throws -> [USBDevice] {
        [device]
    }

    func verifyTrust(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws {}

    func verifyDeveloperMode(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws {}

    func prepareDeveloperDiskImage(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws {}

    func startTunnel(
        for device: USBDevice,
        idempotencyKey: UUID
    ) async throws -> DeviceTunnelLease {
        DeviceTunnelLease(
            id: DeviceTunnelLeaseID(),
            deviceID: device.id,
            endpoint: DeviceTunnelEndpoint(address: "::1", port: 62078)
        )
    }

    func startDVT(
        runtime: RuntimeInstallation,
        lease: DeviceTunnelLease,
        generation: DeviceSessionGeneration
    ) async throws {
        events.append(.startDVT(generation))
    }

    func sendDVT(
        _ command: DVTLocationCommand,
        generation: DeviceSessionGeneration
    ) async throws -> DVTLocationReply {
        switch command {
        case .set:
            setCount += 1
            events.append(.set(generation))
            if let nextSetFailure {
                self.nextSetFailure = nil
                throw nextSetFailure
            }
        case .clear:
            events.append(.clear(generation))
            if shouldFailNextClear {
                shouldFailNextClear = false
                throw DeviceLocationError.clearFailed("reconnect clear failed")
            }
        }
        return DVTLocationReply(requestID: command.requestID)
    }

    func shutdownDVT(generation: DeviceSessionGeneration) async throws {}
    func stopTunnel(_ lease: DeviceTunnelLease) async throws {}
    func reconcileTunnels() async throws {}

    func tunnelStatus(
        _ lease: DeviceTunnelLease
    ) async throws -> DeviceTunnelStatus {
        DeviceTunnelStatus(
            leaseID: lease.id,
            deviceID: lease.deviceID,
            endpoint: lease.endpoint,
            state: tunnelLeaseState,
            diagnostics: DeviceTunnelDiagnostics(
                terminationStatus: 0,
                stderrTail: "",
                stderrByteCount: 0
            )
        )
    }

    func setTunnelStatus(_ state: DeviceTunnelLeaseState) {
        tunnelLeaseState = state
    }

    func failNextSet(_ failure: DeviceLocationError) {
        nextSetFailure = failure
    }

    func waitForSetCount(_ count: Int) async {
        while setCount < count {
            await Task.yield()
        }
    }

    func failNextClear() {
        shouldFailNextClear = true
    }

    func resetEvents() {
        events = []
    }
}

private actor RecoveryScheduler: SimulationScheduling {
    private var instant: TimeInterval = 0
    private var sleepers: [CheckedContinuation<Void, Error>] = []

    func now() async -> TimeInterval {
        instant
    }

    func waitForNextTick() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append(continuation)
        }
    }

    func waitUntilWaiting() async {
        while sleepers.isEmpty {
            await Task.yield()
        }
    }

    func advance(to instant: TimeInterval) {
        self.instant = instant
        let waiting = sleepers
        sleepers = []
        waiting.forEach { $0.resume() }
    }
}
