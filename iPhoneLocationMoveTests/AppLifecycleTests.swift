import XCTest
@testable import iPhoneLocationMove

@MainActor
final class AppLifecycleTests: XCTestCase {
    func testPrivilegedAcceptanceArgumentsOnlyAllowFixedCases() {
        for acceptanceCase in PrivilegedHelperAcceptanceCase.allCases {
            XCTAssertEqual(
                PrivilegedHelperAcceptanceCase.parse(
                    [
                        "iPhoneLocationMove",
                        "--privileged-helper-acceptance-case",
                        acceptanceCase.rawValue,
                    ]
                ),
                acceptanceCase
            )
        }
        XCTAssertNil(
            PrivilegedHelperAcceptanceCase.parse(
                [
                    "iPhoneLocationMove",
                    "--privileged-helper-acceptance-case",
                    "run-command",
                    "/tmp/payload",
                ]
            )
        )
        XCTAssertNil(
            PrivilegedHelperAcceptanceCase.parse(
                [
                    "iPhoneLocationMove",
                    "--privileged-helper-acceptance-case",
                    "positive-start",
                    "--output",
                    "/tmp/result.json",
                ]
            )
        )
    }

    func testPrivilegedNegativeAcceptanceCasesRequireTheirSpecificFailure() {
        XCTAssertTrue(
            PrivilegedHelperAcceptanceCase.endpointTimeout.acceptsExpectedFailure(
                DeviceLocationError.timeout
            )
        )
        XCTAssertFalse(
            PrivilegedHelperAcceptanceCase.endpointTimeout.acceptsExpectedFailure(
                DeviceLocationError.tunnelFailure(
                    "The tunnel process exited before becoming ready."
                )
            )
        )
        XCTAssertTrue(
            PrivilegedHelperAcceptanceCase.runtimeSealTamper.acceptsExpectedFailure(
                DeviceLocationError.tunnelFailure(
                    "Generated runtime file set does not match its seal."
                )
            )
        )
        XCTAssertFalse(
            PrivilegedHelperAcceptanceCase.runtimeSealTamper.acceptsExpectedFailure(
                DeviceLocationError.authorizationDenied
            )
        )
    }

    func testClosingMainWindowDoesNotStopActiveSimulation() async {
        let recorder = LifecycleEventRecorder()
        let simulation = FakeLifecycleSimulation(
            active: true,
            recorder: recorder
        )
        let device = FakeLifecycleDevice(recorder: recorder)
        let coordinator = AppLifecycleCoordinator(
            simulation: simulation,
            device: device
        )

        coordinator.handleMainWindowClosed()

        XCTAssertEqual(coordinator.state, .idle)
        let events = await recorder.events
        XCTAssertEqual(events, [])
    }

    func testActiveQuitRequiresConfirmationAndUsesSafeCleanupOrder() async {
        let recorder = LifecycleEventRecorder()
        let simulation = FakeLifecycleSimulation(
            active: true,
            recorder: recorder
        )
        let device = FakeLifecycleDevice(recorder: recorder)
        let coordinator = AppLifecycleCoordinator(
            simulation: simulation,
            device: device
        )

        let initialDecision = await coordinator.requestQuit()

        XCTAssertEqual(initialDecision, .awaitingConfirmation)
        XCTAssertEqual(coordinator.state, .confirmationRequired)
        let eventsBeforeConfirmation = await recorder.events
        XCTAssertEqual(eventsBeforeConfirmation, [])

        let confirmedDecision = await coordinator.confirmQuit()

        XCTAssertEqual(confirmedDecision, .terminate)
        XCTAssertEqual(
            coordinator.state,
            .readyToTerminate(safelyCleared: true)
        )
        let events = await recorder.events
        XCTAssertEqual(
            events,
            [.producerStopped, .locationCleared, .dvtShutdown, .tunnelStopped]
        )
    }

    func testReadySessionWithoutActiveSimulationStillTearsDownDevice() async {
        let recorder = LifecycleEventRecorder()
        let simulation = FakeLifecycleSimulation(
            active: false,
            recorder: recorder
        )
        let device = FakeLifecycleDevice(recorder: recorder)
        let coordinator = AppLifecycleCoordinator(
            simulation: simulation,
            device: device
        )

        let decision = await coordinator.requestQuit()

        XCTAssertEqual(decision, .terminate)
        XCTAssertEqual(
            coordinator.state,
            .readyToTerminate(safelyCleared: true)
        )
        let events = await recorder.events
        XCTAssertEqual(
            events,
            [.dvtShutdown, .tunnelStopped]
        )
    }

    func testClearFailureDoesNotTearDownOrClaimRealLocationWasRestored() async {
        let recorder = LifecycleEventRecorder()
        let failure = DeviceLocationError.clearFailed("clear rejected")
        let simulation = FakeLifecycleSimulation(
            active: true,
            cleanupFailure: failure,
            recorder: recorder
        )
        let device = FakeLifecycleDevice(recorder: recorder)
        let coordinator = AppLifecycleCoordinator(
            simulation: simulation,
            device: device
        )

        _ = await coordinator.requestQuit()
        let decision = await coordinator.confirmQuit()

        XCTAssertEqual(decision, .keepRunning)
        XCTAssertEqual(coordinator.state, .cleanupFailed(failure))
        let events = await recorder.events
        XCTAssertEqual(
            events,
            [.producerStopped, .locationClearFailed]
        )
    }

    func testForceQuitRequiresSecondExplicitWarningAndNeverClaimsSafeClear() async {
        let recorder = LifecycleEventRecorder()
        let failure = DeviceLocationError.clearFailed("clear rejected")
        let simulation = FakeLifecycleSimulation(
            active: true,
            cleanupFailure: failure,
            recorder: recorder
        )
        let device = FakeLifecycleDevice(recorder: recorder)
        let coordinator = AppLifecycleCoordinator(
            simulation: simulation,
            device: device
        )
        _ = await coordinator.requestQuit()
        _ = await coordinator.confirmQuit()

        coordinator.requestForceQuit()

        XCTAssertEqual(coordinator.state, .forceQuitWarning(failure))
        XCTAssertEqual(coordinator.confirmForceQuit(), .terminate)
        XCTAssertEqual(
            coordinator.state,
            .readyToTerminate(safelyCleared: false)
        )
    }
}

private enum LifecycleEvent: Equatable, Sendable {
    case producerStopped
    case locationCleared
    case locationClearFailed
    case dvtShutdown
    case tunnelStopped
}

private actor LifecycleEventRecorder {
    private(set) var events: [LifecycleEvent] = []

    func append(_ event: LifecycleEvent) {
        events.append(event)
    }
}

@MainActor
private final class FakeLifecycleSimulation: SimulationLifecycleControlling {
    private(set) var hasActiveSimulation: Bool
    private(set) var cleanupFailure: DeviceLocationError?
    private let configuredFailure: DeviceLocationError?
    private let recorder: LifecycleEventRecorder

    init(
        active: Bool,
        cleanupFailure: DeviceLocationError? = nil,
        recorder: LifecycleEventRecorder
    ) {
        hasActiveSimulation = active
        configuredFailure = cleanupFailure
        self.recorder = recorder
    }

    func stopForQuit() async {
        await recorder.append(.producerStopped)
        if let configuredFailure {
            cleanupFailure = configuredFailure
            await recorder.append(.locationClearFailed)
        } else {
            cleanupFailure = nil
            hasActiveSimulation = false
            await recorder.append(.locationCleared)
        }
    }
}

private actor FakeLifecycleDevice: DeviceSessionQuitTeardown {
    private let recorder: LifecycleEventRecorder

    init(recorder: LifecycleEventRecorder) {
        self.recorder = recorder
    }

    func teardownForQuit() async throws {
        await recorder.append(.dvtShutdown)
        await recorder.append(.tunnelStopped)
    }
}
