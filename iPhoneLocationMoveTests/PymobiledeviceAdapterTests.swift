import Foundation
import XCTest
@testable import iPhoneLocationMove

final class PymobiledeviceAdapterTests: XCTestCase {
    func testPreparationUsesFixedPrerequisiteOrder() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)

        let session = try await adapter.connect()

        XCTAssertEqual(session.device, device)
        XCTAssertEqual(session.generation, DeviceSessionGeneration(rawValue: 1))
        await XCTAssertEqualAsync(
            { await boundary.events },
            [
                .runtime,
                .usbDiscovery,
                .trust(device.id),
                .developerMode(device.id),
                .developerDiskImage(device.id),
                .startTunnel(device.id),
                .startDVT(DeviceSessionGeneration(rawValue: 1)),
            ]
        )
    }

    func testZeroOneAndMultipleDeviceSelection() async throws {
        let noDevices = FakePymobiledeviceBoundary(devices: [])
        let emptyAdapter = PymobiledeviceAdapter(boundary: noDevices)
        await XCTAssertThrowsDeviceError(.noUSBDevice) {
            _ = try await emptyAdapter.connect()
        }

        let onlyDevice = try makeDevice(id: "only-device")
        let oneDevice = FakePymobiledeviceBoundary(devices: [onlyDevice])
        let oneAdapter = PymobiledeviceAdapter(boundary: oneDevice)
        try await XCTAssertEqualAsync(
            { try await oneAdapter.connect().device },
            onlyDevice
        )

        let otherDevice = try makeDevice(id: "other-device")
        let manyDevices = FakePymobiledeviceBoundary(devices: [onlyDevice, otherDevice])
        let manyAdapter = PymobiledeviceAdapter(boundary: manyDevices)
        await XCTAssertThrowsDeviceError(.selectionRequired) {
            _ = try await manyAdapter.connect()
        }
        await XCTAssertEqualAsync(
            { await manyAdapter.state },
            .selectionRequired([onlyDevice, otherDevice])
        )
        try await XCTAssertEqualAsync(
            {
                try await manyAdapter.connect(
                    selectedDeviceID: otherDevice.id
                ).device
            },
            otherDevice
        )
    }

    func testIOS16DeviceIsVisibleButPreparationStopsBeforeTunnel() async throws {
        let device = try makeDevice(id: "device-16", majorVersion: 16)
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)

        await XCTAssertThrowsDeviceError(.unsupportedDevice) {
            _ = try await adapter.connect()
        }

        await XCTAssertEqualAsync(
            { await adapter.state },
            .selectionRequired([device])
        )
        await XCTAssertEqualAsync(
            { await boundary.events },
            [.runtime, .usbDiscovery]
        )
    }

    func testMutatingCommandsAreSerializedAndRepliesAreCorrelated() async throws {
        let boundary = FakePymobiledeviceBoundary(devices: [try makeDevice(id: "device-17")])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        await boundary.setMutationSuspended(true)
        let simulationID = SimulationSessionID()
        let firstContext = DeviceMutationContext(
            requestID: DeviceRequestID(rawValue: UUID()),
            simulationSessionID: simulationID,
            generation: session.generation
        )
        let secondContext = DeviceMutationContext(
            requestID: DeviceRequestID(rawValue: UUID()),
            simulationSessionID: simulationID,
            generation: session.generation
        )
        let coordinate = try DeviceCoordinate(latitude: 25.033, longitude: 121.5654)

        let first = Task {
            try await adapter.setLocation(coordinate, context: firstContext)
        }
        await boundary.waitForPendingMutationCount(1)
        let second = Task {
            try await adapter.setLocation(coordinate, context: secondContext)
        }
        await Task.yield()
        await XCTAssertEqualAsync(
            { await boundary.pendingMutationCount },
            1
        )

        await boundary.completeNextMutation(requestID: firstContext.requestID)
        try await first.value
        await boundary.waitForPendingMutationCount(1)
        await boundary.completeNextMutation(requestID: secondContext.requestID)
        try await second.value

        await XCTAssertEqualAsync(
            { await boundary.maximumConcurrentMutationCount },
            1
        )

        await boundary.setMutationSuspended(true)
        let mismatched = DeviceMutationContext(
            requestID: DeviceRequestID(),
            simulationSessionID: simulationID,
            generation: session.generation
        )
        let mismatchTask = Task {
            try await adapter.setLocation(coordinate, context: mismatched)
        }
        await boundary.waitForPendingMutationCount(1)
        await boundary.completeNextMutation(requestID: DeviceRequestID())
        await XCTAssertThrowsDeviceError(.responseMismatch) {
            try await mismatchTask.value
        }
    }

    func testOldGenerationCompletionCannotRewriteReconnectedSession() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let oldSession = try await adapter.connect()
        await boundary.setMutationSuspended(true)
        let context = DeviceMutationContext(
            simulationSessionID: SimulationSessionID(),
            generation: oldSession.generation
        )
        let coordinate = try DeviceCoordinate(latitude: 25, longitude: 121)
        let oldMutation = Task {
            try await adapter.setLocation(coordinate, context: context)
        }
        await boundary.waitForPendingMutationCount(1)

        await adapter.handleUSBDisconnect(deviceID: device.id)
        await boundary.completeNextMutation(requestID: context.requestID)

        await XCTAssertThrowsDeviceError(.staleGeneration) {
            try await oldMutation.value
        }
        let interrupted = DeviceInterruption(
            reason: .usbDisconnected,
            positionKnowledge: .unknown
        )
        await XCTAssertEqualAsync(
            { await adapter.state },
            .interrupted(session: oldSession, interruption: interrupted)
        )

        await boundary.setMutationSuspended(false)
        let reconnected = try await adapter.reconnect()
        XCTAssertEqual(reconnected.generation, DeviceSessionGeneration(rawValue: 3))
        await XCTAssertEqualAsync(
            { await adapter.state },
            .ready(reconnected)
        )
        await XCTAssertEqualAsync(
            { Array((await boundary.events).suffix(2)) },
            [.startDVT(reconnected.generation), .clear(reconnected.generation)]
        )
    }

    func testActiveDeviceSwitchCleansOldOwnershipBeforeCommittingSelection() async throws {
        let firstDevice = try makeDevice(id: "first-device")
        let secondDevice = try makeDevice(id: "second-device")
        let boundary = FakePymobiledeviceBoundary(devices: [firstDevice, secondDevice])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let firstSession = try await adapter.connect(selectedDeviceID: firstDevice.id)
        let context = DeviceMutationContext(
            simulationSessionID: SimulationSessionID(),
            generation: firstSession.generation
        )
        try await adapter.setLocation(
            DeviceCoordinate(latitude: 25, longitude: 121),
            context: context
        )
        await boundary.resetEvents()

        let secondSession = try await adapter.switchDevice(to: secondDevice.id)

        XCTAssertEqual(secondSession.device, secondDevice)
        let events = await boundary.events
        XCTAssertEqual(
            Array(events.prefix(3)),
            [
                .clear(firstSession.generation),
                .shutdownDVT(firstSession.generation),
                .stopTunnel(firstDevice.id),
            ]
        )
        XCTAssertEqual(events[3], .runtime)
        XCTAssertEqual(events[4], .usbDiscovery)
    }

    func testDeviceSwitchClearFailurePreservesOldOwnership() async throws {
        let firstDevice = try makeDevice(id: "first-device")
        let secondDevice = try makeDevice(id: "second-device")
        let boundary = FakePymobiledeviceBoundary(devices: [firstDevice, secondDevice])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let firstSession = try await adapter.connect(selectedDeviceID: firstDevice.id)
        try await adapter.setLocation(
            DeviceCoordinate(latitude: 25, longitude: 121),
            context: DeviceMutationContext(
                simulationSessionID: SimulationSessionID(),
                generation: firstSession.generation
            )
        )
        await boundary.setNextMutationError(.clearFailed("clear failed"))
        await boundary.resetEvents()

        await XCTAssertThrowsDeviceError(.clearFailed("clear failed")) {
            _ = try await adapter.switchDevice(to: secondDevice.id)
        }

        await XCTAssertEqualAsync(
            { await adapter.selectedDevice },
            firstDevice
        )
        await XCTAssertEqualAsync(
            { await adapter.state },
            .cleanupPending(
                session: firstSession,
                failure: .clearFailed("clear failed")
            )
        )
        await XCTAssertEqualAsync(
            { await boundary.events },
            [.clear(firstSession.generation)]
        )
    }

    func testDisconnectDuringDeviceSwitchCannotCommitNewSelection() async throws {
        let firstDevice = try makeDevice(id: "first-device")
        let secondDevice = try makeDevice(id: "second-device")
        let boundary = FakePymobiledeviceBoundary(devices: [firstDevice, secondDevice])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let firstSession = try await adapter.connect(
            selectedDeviceID: firstDevice.id
        )
        try await adapter.setLocation(
            DeviceCoordinate(latitude: 25, longitude: 121),
            context: DeviceMutationContext(
                simulationSessionID: SimulationSessionID(),
                generation: firstSession.generation
            )
        )
        await boundary.resetEvents()
        await boundary.setMutationSuspended(true)

        let deviceSwitch = Task {
            try await adapter.switchDevice(to: secondDevice.id)
        }
        await boundary.waitForPendingMutationCount(1)
        await adapter.handleUSBDisconnect(deviceID: firstDevice.id)
        await boundary.completeNextMutation(requestID: DeviceRequestID())

        await XCTAssertThrowsDeviceError(.staleGeneration) {
            _ = try await deviceSwitch.value
        }
        await XCTAssertEqualAsync(
            { await adapter.selectedDevice },
            firstDevice
        )
        await XCTAssertEqualAsync(
            { await adapter.state },
            .interrupted(
                session: firstSession,
                interruption: DeviceInterruption(
                    reason: .usbDisconnected,
                    positionKnowledge: .unknown
                )
            )
        )
        await XCTAssertEqualAsync(
            { await boundary.events },
            [
                .clear(firstSession.generation),
                .shutdownDVT(firstSession.generation),
                .stopTunnel(firstDevice.id),
            ]
        )
    }

    func testUSBDisconnectStopsLocalSessionAndReportsUnknownPosition() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        await boundary.resetEvents()

        await adapter.handleUSBDisconnect(deviceID: device.id)

        await XCTAssertEqualAsync(
            { await adapter.state },
            .interrupted(
                session: session,
                interruption: DeviceInterruption(
                    reason: .usbDisconnected,
                    positionKnowledge: .unknown
                )
            )
        )
        await XCTAssertEqualAsync(
            { await boundary.events },
            [.shutdownDVT(session.generation), .stopTunnel(device.id)]
        )
    }

    func testAuthorizationAndTransportFailuresRemainDistinct() async throws {
        let device = try makeDevice(id: "device-17")
        let authorizationBoundary = FakePymobiledeviceBoundary(devices: [device])
        await authorizationBoundary.setFailure(.authorizationDenied, at: .trust(device.id))
        let authorizationAdapter = PymobiledeviceAdapter(boundary: authorizationBoundary)
        await XCTAssertThrowsDeviceError(.authorizationDenied) {
            _ = try await authorizationAdapter.connect()
        }

        let transportBoundary = FakePymobiledeviceBoundary(devices: [device])
        let transportAdapter = PymobiledeviceAdapter(boundary: transportBoundary)
        let session = try await transportAdapter.connect()
        await transportBoundary.setNextMutationError(.transportFailure("pipe closed"))
        await XCTAssertThrowsDeviceError(.transportFailure("pipe closed")) {
            try await transportAdapter.setLocation(
                DeviceCoordinate(latitude: 25, longitude: 121),
                context: DeviceMutationContext(
                    simulationSessionID: SimulationSessionID(),
                    generation: session.generation
                )
            )
        }
    }

    func testReadyAndActiveQuitTeardownUseRequiredOrder() async throws {
        let device = try makeDevice(id: "device-17")
        let readyBoundary = FakePymobiledeviceBoundary(devices: [device])
        let readyAdapter = PymobiledeviceAdapter(boundary: readyBoundary)
        let readySession = try await readyAdapter.connect()
        await readyBoundary.resetEvents()

        try await readyAdapter.teardownForQuit()

        await XCTAssertEqualAsync(
            { await readyBoundary.events },
            [
                .shutdownDVT(readySession.generation),
                .stopTunnel(device.id),
                .reconcile,
            ]
        )

        let activeBoundary = FakePymobiledeviceBoundary(devices: [device])
        let activeAdapter = PymobiledeviceAdapter(boundary: activeBoundary)
        let activeSession = try await activeAdapter.connect()
        try await activeAdapter.setLocation(
            DeviceCoordinate(latitude: 25, longitude: 121),
            context: DeviceMutationContext(
                simulationSessionID: SimulationSessionID(),
                generation: activeSession.generation
            )
        )
        await activeBoundary.resetEvents()

        try await activeAdapter.teardownForQuit()

        await XCTAssertEqualAsync(
            { await activeBoundary.events },
            [
                .clear(activeSession.generation),
                .shutdownDVT(activeSession.generation),
                .stopTunnel(device.id),
                .reconcile,
            ]
        )
    }

    private func makeDevice(
        id: String,
        majorVersion: Int = 17
    ) throws -> USBDevice {
        try USBDevice(
            id: DeviceID(id),
            name: "iPhone",
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: majorVersion,
                minorVersion: 0,
                patchVersion: 0
            )
        )
    }
}

private enum FakeBoundaryEvent: Equatable, Hashable, Sendable {
    case runtime
    case usbDiscovery
    case trust(DeviceID)
    case developerMode(DeviceID)
    case developerDiskImage(DeviceID)
    case startTunnel(DeviceID)
    case startDVT(DeviceSessionGeneration)
    case set(DeviceSessionGeneration)
    case clear(DeviceSessionGeneration)
    case shutdownDVT(DeviceSessionGeneration)
    case stopTunnel(DeviceID)
    case reconcile
}

private actor FakePymobiledeviceBoundary: PymobiledeviceBoundary {
    private struct PendingMutation {
        let continuation: CheckedContinuation<DVTLocationReply, Error>
    }

    let devices: [USBDevice]
    private(set) var events: [FakeBoundaryEvent] = []
    private(set) var pendingMutationCount = 0
    private(set) var maximumConcurrentMutationCount = 0
    private var failures: [FakeBoundaryEvent: DeviceLocationError] = [:]
    private var nextMutationError: DeviceLocationError?
    private var mutationSuspended = false
    private var pendingMutations: [PendingMutation] = []

    init(devices: [USBDevice]) {
        self.devices = devices
    }

    func inspectRuntime() async -> RuntimeAvailability {
        events.append(.runtime)
        return .ready(
            RuntimeInstallation(
                executableURL: URL(fileURLWithPath: "/runtime/pymobiledevice3"),
                source: .existing
            )
        )
    }

    func discoverUSBDevices(runtime: RuntimeInstallation) async throws -> [USBDevice] {
        try record(.usbDiscovery)
        return devices
    }

    func verifyTrust(for device: USBDevice, runtime: RuntimeInstallation) async throws {
        try record(.trust(device.id))
    }

    func verifyDeveloperMode(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws {
        try record(.developerMode(device.id))
    }

    func prepareDeveloperDiskImage(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws {
        try record(.developerDiskImage(device.id))
    }

    func startTunnel(
        for device: USBDevice,
        idempotencyKey: UUID
    ) async throws -> DeviceTunnelLease {
        try record(.startTunnel(device.id))
        return DeviceTunnelLease(
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
        try record(.startDVT(generation))
    }

    func sendDVT(
        _ command: DVTLocationCommand,
        generation: DeviceSessionGeneration
    ) async throws -> DVTLocationReply {
        switch command {
        case .set:
            events.append(.set(generation))
        case .clear:
            events.append(.clear(generation))
        }
        if let error = nextMutationError {
            nextMutationError = nil
            throw error
        }
        guard mutationSuspended else {
            return DVTLocationReply(requestID: command.requestID)
        }
        pendingMutationCount += 1
        maximumConcurrentMutationCount = max(
            maximumConcurrentMutationCount,
            pendingMutationCount
        )
        return try await withCheckedThrowingContinuation { continuation in
            pendingMutations.append(PendingMutation(continuation: continuation))
        }
    }

    func shutdownDVT(generation: DeviceSessionGeneration) async throws {
        try record(.shutdownDVT(generation))
    }

    func stopTunnel(_ lease: DeviceTunnelLease) async throws {
        try record(.stopTunnel(lease.deviceID))
    }

    func reconcileTunnels() async throws {
        try record(.reconcile)
    }

    func setFailure(_ error: DeviceLocationError, at event: FakeBoundaryEvent) {
        failures[event] = error
    }

    func setNextMutationError(_ error: DeviceLocationError) {
        nextMutationError = error
    }

    func setMutationSuspended(_ suspended: Bool) {
        mutationSuspended = suspended
    }

    func completeNextMutation(requestID: DeviceRequestID) {
        let pending = pendingMutations.removeFirst()
        pendingMutationCount -= 1
        pending.continuation.resume(returning: DVTLocationReply(requestID: requestID))
    }

    func waitForPendingMutationCount(_ expected: Int) async {
        while pendingMutationCount != expected {
            await Task.yield()
        }
    }

    func resetEvents() {
        events = []
    }

    private func record(_ event: FakeBoundaryEvent) throws {
        events.append(event)
        if let failure = failures[event] {
            throw failure
        }
    }
}

private func XCTAssertThrowsDeviceError<T>(
    _ expected: DeviceLocationError,
    operation: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await operation()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as DeviceLocationError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}

private func XCTAssertEqualAsync<T: Equatable>(
    _ expression: () async throws -> T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    let actual = try await expression()
    XCTAssertEqual(actual, expected, file: file, line: line)
}
