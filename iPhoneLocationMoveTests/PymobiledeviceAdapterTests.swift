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

    func testSetTransportClosureRecoversOnceAndReplaysAfterOldTransportStops() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let logger = RecordingDiagnosticLogger()
        let adapter = PymobiledeviceAdapter(boundary: boundary, diagnosticLogger: logger)
        let session = try await adapter.connect()
        await boundary.resetEvents()
        await boundary.enqueueMutationBehaviors([
            .failure(transportClosedFailure()),
            .success,
        ])
        let context = DeviceMutationContext(
            simulationSessionID: SimulationSessionID(),
            generation: session.generation
        )

        try await adapter.setLocation(
            DeviceCoordinate(latitude: 25, longitude: 121),
            context: context
        )

        await XCTAssertEqualAsync(
            { await boundary.events },
            [
                .set(session.generation),
                .shutdownDVT(session.generation),
                .stopTunnel(device.id),
                .startTunnel(device.id),
                .startDVT(session.generation),
                .set(session.generation),
            ]
        )
        XCTAssertEqual(
            logger.events.map(\.event).filter {
                $0 == "tunnel.status_probed"
                    || $0 == "transport.recovery_started"
                    || $0 == "location.set_succeeded"
            },
            [
                "transport.recovery_started",
                "tunnel.status_probed",
                "location.set_succeeded",
            ]
        )
    }

    func testRecoveryDiagnosticFileUsesAllowlistedFieldsAndPreservesEventOrder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = DiagnosticLogger(directoryURL: directory)
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(
            boundary: boundary,
            diagnosticLogger: logger
        )
        let session = try await adapter.connect()

        let endpoint = "fd7e:5f3a:9c21::42"
        let port = "62078"
        let coordinate = "25.0330,121.5654"
        let rawDetail = "closed at [\(endpoint)]:\(port) coordinate \(coordinate)"
        let failure = try XCTUnwrap(
            parseDeviceBackendFailure([
                "code": "transport-closed",
                "exceptionType": "ConnectionTerminatedError",
                "errno": 54,
                "detail": rawDetail,
            ])
        )
        recordDeviceBackendFailure(
            failure,
            requestID: "fixture-request",
            command: "set",
            diagnosticLogger: logger
        )
        await boundary.setTunnelStatus(
            state: .exited,
            diagnostics: DeviceTunnelDiagnostics(
                terminationStatus: 15,
                stderrTail: "RSD [\(endpoint)]:\(port) latitudeLongitude=\(coordinate)",
                stderrByteCount: 8_192
            )
        )
        await boundary.setNextMutationError(.transportClosed(failure))

        await XCTAssertThrowsDeviceError(
            .tunnelFailure("Tunnel process exited before recovery")
        ) {
            try await adapter.setLocation(
                DeviceCoordinate(latitude: 25, longitude: 121),
                context: DeviceMutationContext(
                    simulationSessionID: SimulationSessionID(),
                    generation: session.generation
                )
            )
        }

        let data = try Data(contentsOf: logger.fileURL)
        let serialized = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(serialized.contains(rawDetail))
        XCTAssertFalse(serialized.contains(endpoint))
        XCTAssertFalse(serialized.contains(port))
        XCTAssertFalse(serialized.contains(coordinate))

        let entries = try serialized
            .split(whereSeparator: \.isNewline)
            .map { line -> [String: Any] in
                try XCTUnwrap(
                    JSONSerialization.jsonObject(
                        with: Data(line.utf8)
                    ) as? [String: Any]
                )
            }
        let recoveryEvents = entries.compactMap { $0["event"] as? String }
            .filter {
                [
                    "dvt.transport_closed",
                    "transport.recovery_started",
                    "tunnel.status_probed",
                    "transport.recovery_failed",
                ].contains($0)
            }
        XCTAssertEqual(
            recoveryEvents,
            [
                "dvt.transport_closed",
                "transport.recovery_started",
                "tunnel.status_probed",
                "transport.recovery_failed",
            ]
        )

        let allowedMetadataKeys: Set<String> = [
            "requestID",
            "command",
            "failureCode",
            "exceptionType",
            "errno",
            "logicalGeneration",
            "transportGeneration",
            "attempt",
            "state",
            "terminationStatus",
            "stderrByteCount",
        ]
        for entry in entries where recoveryEvents.contains(entry["event"] as? String ?? "") {
            let metadata = try XCTUnwrap(entry["metadata"] as? [String: String])
            XCTAssertTrue(Set(metadata.keys).isSubset(of: allowedMetadataKeys))
        }
        let statusEntry = try XCTUnwrap(
            entries.first { $0["event"] as? String == "tunnel.status_probed" }
        )
        let statusMetadata = try XCTUnwrap(
            statusEntry["metadata"] as? [String: String]
        )
        XCTAssertEqual(statusMetadata["state"], "exited")
        XCTAssertEqual(statusMetadata["terminationStatus"], "15")
        XCTAssertEqual(statusMetadata["stderrByteCount"], "8192")
    }

    func testClearTransportClosureRecoversOnceBeforeReleasingOwnership() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        try await adapter.setLocation(
            DeviceCoordinate(latitude: 25, longitude: 121),
            context: DeviceMutationContext(
                simulationSessionID: SimulationSessionID(),
                generation: session.generation
            )
        )
        await boundary.resetEvents()
        await boundary.enqueueMutationBehaviors([
            .failure(transportClosedFailure()),
            .success,
        ])

        try await adapter.clearLocation(
            context: DeviceCleanupContext(generation: session.generation)
        )

        await XCTAssertEqualAsync(
            { await boundary.events },
            [
                .clear(session.generation),
                .shutdownDVT(session.generation),
                .stopTunnel(device.id),
                .startTunnel(device.id),
                .startDVT(session.generation),
                .clear(session.generation),
            ]
        )
        await XCTAssertEqualAsync(
            { await adapter.state },
            .ready(session)
        )
    }

    func testRecoveryReplayFailureIsTerminalWithoutRecursiveRecovery() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        await boundary.resetEvents()
        await boundary.enqueueMutationBehaviors([
            .failure(transportClosedFailure()),
            .failure(transportClosedFailure()),
        ])

        await XCTAssertThrowsDeviceError(transportClosedFailure()) {
            try await adapter.setLocation(
                DeviceCoordinate(latitude: 25, longitude: 121),
                context: DeviceMutationContext(
                    simulationSessionID: SimulationSessionID(),
                    generation: session.generation
                )
            )
        }

        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .startTunnel(device.id) }.count },
            1
        )
        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .set(session.generation) }.count },
            2
        )
    }

    func testTunnelExitedFailureIsTerminalAndDoesNotStartReplacement() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        await boundary.resetEvents()
        await boundary.enqueueMutationBehaviors([
            .failure(.tunnelFailure("exited")),
        ])

        await XCTAssertThrowsDeviceError(.tunnelFailure("exited")) {
            try await adapter.setLocation(
                DeviceCoordinate(latitude: 25, longitude: 121),
                context: DeviceMutationContext(
                    simulationSessionID: SimulationSessionID(),
                    generation: session.generation
                )
            )
        }

        await XCTAssertEqualAsync(
            { await boundary.events },
            [.set(session.generation)]
        )
    }

    func testCandidateReplayDoesNotPublishSuccessBeforeAtomicCommit() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let logger = RecordingDiagnosticLogger()
        let adapter = PymobiledeviceAdapter(boundary: boundary, diagnosticLogger: logger)
        let session = try await adapter.connect()
        await boundary.enqueueMutationBehaviors([
            .failure(transportClosedFailure()),
            .suspended,
        ])
        let context = DeviceMutationContext(
            simulationSessionID: SimulationSessionID(),
            generation: session.generation
        )
        let mutation = Task {
            try await adapter.setLocation(
                DeviceCoordinate(latitude: 25, longitude: 121),
                context: context
            )
        }
        guard await boundary.waitForPendingMutationCount(1) else {
            _ = try? await mutation.value
            return XCTFail("Expected candidate replay to remain pending before commit")
        }

        XCTAssertFalse(logger.events.map(\.event).contains("location.set_succeeded"))
        await XCTAssertEqualAsync(
            { await adapter.state },
            .ready(session)
        )

        await boundary.completeNextMutation(requestID: context.requestID)
        try await mutation.value
        XCTAssertTrue(logger.events.map(\.event).contains("location.set_succeeded"))

        try await adapter.setLocation(
            DeviceCoordinate(latitude: 24, longitude: 120),
            context: DeviceMutationContext(
                simulationSessionID: context.simulationSessionID,
                generation: session.generation
            )
        )
    }

    func testCandidateLeaseIsCleanedWhenDVTStartFailsBeforeIdentityIsComplete() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        await boundary.resetEvents()
        await boundary.enqueueMutationBehaviors([
            .failure(transportClosedFailure()),
        ])
        await boundary.setFailure(
            .helperFailure("candidate DVT failed"),
            at: .startDVT(session.generation)
        )

        await XCTAssertThrowsDeviceError(.helperFailure("candidate DVT failed")) {
            try await adapter.setLocation(
                DeviceCoordinate(latitude: 25, longitude: 121),
                context: DeviceMutationContext(
                    simulationSessionID: SimulationSessionID(),
                    generation: session.generation
                )
            )
        }

        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .startTunnel(device.id) }.count },
            1
        )
        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .startDVT(session.generation) }.count },
            1
        )
        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .stopTunnel(device.id) }.count },
            2
        )
        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .set(session.generation) }.count },
            1
        )
    }

    func testDisconnectAfterStatusProbeCancelsRecoveryBeforeRestart() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect()
        await boundary.enqueueMutationBehaviors([
            .failure(transportClosedFailure()),
        ])
        await boundary.suspendNextTunnelStop()
        let mutation = Task {
            try await adapter.setLocation(
                DeviceCoordinate(latitude: 25, longitude: 121),
                context: DeviceMutationContext(
                    simulationSessionID: SimulationSessionID(),
                    generation: session.generation
                )
            )
        }
        let reachedStatusBoundary = await boundary.waitForPendingTunnelStop()
        XCTAssertTrue(reachedStatusBoundary)

        let disconnect = Task {
            await adapter.handleUSBDisconnect(deviceID: device.id)
        }
        await Task.yield()
        await boundary.completePendingTunnelStop()
        await disconnect.value

        await XCTAssertThrowsDeviceError(.staleGeneration) {
            try await mutation.value
        }
        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .set(session.generation) }.count },
            1
        )
        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .stopTunnel(device.id) }.count },
            2
        )
    }

    func testReconnectWhileReplayPendingKeepsNewSessionAndIgnoresStaleCompletion() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let oldSession = try await adapter.connect()
        await boundary.enqueueMutationBehaviors([
            .failure(transportClosedFailure()),
            .suspended,
        ])
        let oldContext = DeviceMutationContext(
            simulationSessionID: SimulationSessionID(),
            generation: oldSession.generation
        )
        let oldMutation = Task {
            try await adapter.setLocation(
                DeviceCoordinate(latitude: 25, longitude: 121),
                context: oldContext
            )
        }
        guard await boundary.waitForPendingMutationCount(1) else {
            _ = try? await oldMutation.value
            return XCTFail("Expected recovery replay to remain pending")
        }

        await adapter.handleUSBDisconnect(deviceID: device.id)
        let reconnect = Task { try await adapter.reconnect() }
        await boundary.completeNextMutation(requestID: oldContext.requestID)

        await XCTAssertThrowsDeviceError(.staleGeneration) {
            try await oldMutation.value
        }
        let newSession = try await reconnect.value
        XCTAssertNotEqual(newSession.generation, oldSession.generation)
        await XCTAssertEqualAsync(
            { await adapter.state },
            .ready(newSession)
        )
        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .set(oldSession.generation) }.count },
            2
        )
    }

    func testQuitDuringCandidateTunnelStartCleansCandidateWithoutPublishingSuccess() async throws {
        let device = try makeDevice(id: "device-17")
        let boundary = FakePymobiledeviceBoundary(devices: [device])
        let logger = RecordingDiagnosticLogger()
        let adapter = PymobiledeviceAdapter(boundary: boundary, diagnosticLogger: logger)
        let session = try await adapter.connect()
        let simulationID = SimulationSessionID()
        try await adapter.setLocation(
            DeviceCoordinate(latitude: 25, longitude: 121),
            context: DeviceMutationContext(
                simulationSessionID: simulationID,
                generation: session.generation
            )
        )
        let successCountBeforeRecovery = logger.events
            .map(\.event)
            .filter { $0 == "location.set_succeeded" }
            .count
        await boundary.enqueueMutationBehaviors([
            .failure(transportClosedFailure()),
        ])
        await boundary.suspendNextTunnelStart()
        let context = DeviceMutationContext(
            simulationSessionID: simulationID,
            generation: session.generation
        )
        let mutation = Task {
            try await adapter.setLocation(
                DeviceCoordinate(latitude: 24, longitude: 120),
                context: context
            )
        }
        guard await boundary.waitForPendingTunnelStart() else {
            _ = try? await mutation.value
            return XCTFail("Expected candidate tunnel start to remain pending")
        }

        let quit = Task { try await adapter.teardownForQuit() }
        await Task.yield()
        await boundary.completePendingTunnelStart()
        await XCTAssertThrowsDeviceError(.staleGeneration) {
            try await mutation.value
        }
        try await quit.value

        XCTAssertEqual(
            logger.events.map(\.event).filter { $0 == "location.set_succeeded" }.count,
            successCountBeforeRecovery
        )
        await XCTAssertEqualAsync(
            { (await boundary.events).contains(.clear(session.generation)) },
            true
        )
        await XCTAssertEqualAsync(
            { await adapter.state },
            .disconnected
        )
    }

    func testDeviceSwitchDuringCandidateTunnelStartDoesNotReplayOldCoordinate() async throws {
        let firstDevice = try makeDevice(id: "first-device")
        let secondDevice = try makeDevice(id: "second-device")
        let boundary = FakePymobiledeviceBoundary(devices: [firstDevice, secondDevice])
        let adapter = PymobiledeviceAdapter(boundary: boundary)
        let session = try await adapter.connect(selectedDeviceID: firstDevice.id)
        await boundary.enqueueMutationBehaviors([
            .failure(transportClosedFailure()),
        ])
        await boundary.suspendNextTunnelStart()
        let mutation = Task {
            try await adapter.setLocation(
                DeviceCoordinate(latitude: 25, longitude: 121),
                context: DeviceMutationContext(
                    simulationSessionID: SimulationSessionID(),
                    generation: session.generation
                )
            )
        }
        let reachedCandidateTunnel = await boundary.waitForPendingTunnelStart()
        XCTAssertTrue(reachedCandidateTunnel)

        let deviceSwitch = Task {
            try await adapter.switchDevice(to: secondDevice.id)
        }
        await boundary.completePendingTunnelStart()
        await XCTAssertThrowsDeviceError(.staleGeneration) {
            try await mutation.value
        }
        let switched = try await deviceSwitch.value

        XCTAssertEqual(switched.device, secondDevice)
        await XCTAssertEqualAsync(
            { (await boundary.events).filter { $0 == .set(session.generation) }.count },
            1
        )
        await XCTAssertEqualAsync(
            { (await boundary.events).contains(.clear(session.generation)) },
            true
        )
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

private enum FakeMutationBehavior: Equatable, Sendable {
    case success
    case failure(DeviceLocationError)
    case suspended
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
    private var mutationBehaviors: [FakeMutationBehavior] = []
    private var mutationSuspended = false
    private var pendingMutations: [PendingMutation] = []
    private var shouldSuspendNextTunnelStart = false
    private var pendingTunnelStart: CheckedContinuation<Void, Never>?
    private var shouldSuspendNextTunnelStop = false
    private var pendingTunnelStop: CheckedContinuation<Void, Never>?
    private var tunnelLeaseState: DeviceTunnelLeaseState = .running
    private var tunnelDiagnostics = DeviceTunnelDiagnostics(
        terminationStatus: nil,
        stderrTail: "",
        stderrByteCount: 0
    )

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
        if shouldSuspendNextTunnelStart {
            shouldSuspendNextTunnelStart = false
            await withCheckedContinuation { continuation in
                pendingTunnelStart = continuation
            }
        }
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
        if !mutationBehaviors.isEmpty {
            let behavior = mutationBehaviors.removeFirst()
            switch behavior {
            case .success:
                return DVTLocationReply(requestID: command.requestID)
            case let .failure(error):
                throw error
            case .suspended:
                return try await suspendMutation()
            }
        }
        if let error = nextMutationError {
            nextMutationError = nil
            throw error
        }
        guard mutationSuspended else {
            return DVTLocationReply(requestID: command.requestID)
        }
        return try await suspendMutation()
    }

    func shutdownDVT(generation: DeviceSessionGeneration) async throws {
        try record(.shutdownDVT(generation))
    }

    func stopTunnel(_ lease: DeviceTunnelLease) async throws {
        try record(.stopTunnel(lease.deviceID))
        if shouldSuspendNextTunnelStop {
            shouldSuspendNextTunnelStop = false
            await withCheckedContinuation { continuation in
                pendingTunnelStop = continuation
            }
        }
    }

    func tunnelStatus(
        _ lease: DeviceTunnelLease
    ) async throws -> DeviceTunnelStatus {
        DeviceTunnelStatus(
            leaseID: lease.id,
            deviceID: lease.deviceID,
            endpoint: lease.endpoint,
            state: tunnelLeaseState,
            diagnostics: tunnelDiagnostics
        )
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

    func enqueueMutationBehaviors(_ newBehaviors: [FakeMutationBehavior]) {
        mutationBehaviors.append(contentsOf: newBehaviors)
    }

    func setMutationSuspended(_ suspended: Bool) {
        mutationSuspended = suspended
    }

    func setTunnelStatus(
        state: DeviceTunnelLeaseState,
        diagnostics: DeviceTunnelDiagnostics
    ) {
        tunnelLeaseState = state
        tunnelDiagnostics = diagnostics
    }

    func suspendNextTunnelStart() {
        shouldSuspendNextTunnelStart = true
    }

    func suspendNextTunnelStop() {
        shouldSuspendNextTunnelStop = true
    }

    func waitForPendingTunnelStart() async -> Bool {
        for _ in 0 ..< 500 {
            if pendingTunnelStart != nil {
                return true
            }
            await Task.yield()
        }
        return false
    }

    func completePendingTunnelStart() {
        shouldSuspendNextTunnelStart = false
        pendingTunnelStart?.resume()
        pendingTunnelStart = nil
    }

    func waitForPendingTunnelStop() async -> Bool {
        for _ in 0 ..< 500 {
            if pendingTunnelStop != nil {
                return true
            }
            await Task.yield()
        }
        return false
    }

    func completePendingTunnelStop() {
        shouldSuspendNextTunnelStop = false
        pendingTunnelStop?.resume()
        pendingTunnelStop = nil
    }

    func completeNextMutation(requestID: DeviceRequestID) {
        let pending = pendingMutations.removeFirst()
        pendingMutationCount -= 1
        pending.continuation.resume(returning: DVTLocationReply(requestID: requestID))
    }

    @discardableResult
    func waitForPendingMutationCount(_ expected: Int) async -> Bool {
        for _ in 0 ..< 2_000 {
            if pendingMutationCount == expected {
                return true
            }
            await Task.yield()
        }
        return false
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

    private func suspendMutation() async throws -> DVTLocationReply {
        pendingMutationCount += 1
        maximumConcurrentMutationCount = max(
            maximumConcurrentMutationCount,
            pendingMutationCount
        )
        return try await withCheckedThrowingContinuation { continuation in
            pendingMutations.append(PendingMutation(continuation: continuation))
        }
    }
}

private final class RecordingDiagnosticLogger: DiagnosticLogging, @unchecked Sendable {
    struct Event: Sendable {
        let level: DiagnosticLogLevel
        let category: String
        let event: String
        let metadata: [String: String]
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    var events: [Event] {
        lock.withLock { recordedEvents }
    }

    func record(
        _ level: DiagnosticLogLevel,
        category: String,
        event: String,
        metadata: [String: String]
    ) {
        lock.withLock {
            recordedEvents.append(
                Event(
                    level: level,
                    category: category,
                    event: event,
                    metadata: metadata
                )
            )
        }
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
