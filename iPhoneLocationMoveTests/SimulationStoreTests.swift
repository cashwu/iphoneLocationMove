import Foundation
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class SimulationStoreTests: XCTestCase {
    func testPointRequiresRiskConfirmationAndBecomesActiveOnlyAfterDeviceSuccess() async throws {
        let harness = try SimulationHarness()
        let point = try DeviceCoordinate(latitude: 25.033, longitude: 121.5654)

        await harness.store.confirmPoint(point, riskAccepted: false)
        XCTAssertEqual(harness.store.state, .idle)
        let callsBeforeConfirmation = await harness.device.setCallCount()
        XCTAssertEqual(callsBeforeConfirmation, 0)

        await harness.store.confirmPoint(point, riskAccepted: true)

        guard case let .pointActive(snapshot) = harness.store.state else {
            return XCTFail("Expected point active")
        }
        XCTAssertEqual(snapshot.coordinate, point)
        let pointCallCount = await harness.device.setCallCount()
        XCTAssertEqual(pointCallCount, 1)
    }

    func testPointFailureIsTypedAndNeverPublishedAsActive() async throws {
        let harness = try SimulationHarness()
        await harness.device.enqueue(.failure(.authorizationDenied))

        await harness.store.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )

        guard case let .interrupted(_, interruption, failure) = harness.store.state else {
            return XCTFail("Expected interrupted state")
        }
        XCTAssertEqual(interruption.reason, .authorizationDenied)
        XCTAssertEqual(interruption.positionKnowledge, .unknown)
        XCTAssertEqual(failure, .authorizationDenied)
    }

    func testRouteStartsAtAAndPointRouteReplacementUsesNewSessionIdentity() async throws {
        let harness = try SimulationHarness()
        let point = try DeviceCoordinate(latitude: 25, longitude: 121)
        await harness.store.confirmPoint(point, riskAccepted: true)
        let pointID = try XCTUnwrap(harness.store.activeSessionID)

        try await harness.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )

        let routeID = try XCTUnwrap(harness.store.activeSessionID)
        XCTAssertNotEqual(pointID, routeID)
        guard case let .route(snapshot, nil) = harness.store.state else {
            return XCTFail("Expected route state")
        }
        XCTAssertEqual(snapshot.phase, .running)
        XCTAssertEqual(snapshot.confirmedDistance, 0)
        let routeCalls = await harness.device.recordedSetCalls()
        XCTAssertEqual(routeCalls.last?.coordinate, try DeviceCoordinate(latitude: 0, longitude: 0))

        let replacementPoint = try DeviceCoordinate(latitude: 24, longitude: 120)
        await harness.store.confirmPoint(replacementPoint, riskAccepted: true)
        guard case let .pointActive(replaced) = harness.store.state else {
            return XCTFail("Expected replacement point")
        }
        XCTAssertNotEqual(replaced.sessionID, routeID)
        XCTAssertEqual(replaced.coordinate, replacementPoint)
    }

    func testReplacementFirstMutationFailureKeepsOwnershipInterrupted() async throws {
        let routeToPoint = try SimulationHarness()
        try await routeToPoint.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await routeToPoint.device.enqueue(.failure(.timeout))
        await routeToPoint.store.confirmPoint(
            try DeviceCoordinate(latitude: 24, longitude: 120),
            riskAccepted: true
        )
        guard case let .interrupted(_, interruption, _) = routeToPoint.store.state else {
            return XCTFail("Expected route-to-point interruption")
        }
        XCTAssertEqual(interruption, unknown(.timeout))

        let pointToRoute = try SimulationHarness()
        await pointToRoute.store.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        await pointToRoute.device.enqueue(.failure(.helperFailure("exited")))
        try await pointToRoute.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        guard case let .interrupted(_, routeInterruption, _) = pointToRoute.store.state else {
            return XCTFail("Expected point-to-route interruption")
        }
        XCTAssertEqual(routeInterruption, unknown(.helperExited))
    }

    func testSchedulerUsesOneSecondCadenceAndStopsOutsideRunning() async throws {
        let harness = try SimulationHarness()
        try await harness.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )

        await harness.scheduler.advance(to: 0.5)
        await Task.yield()
        let halfSecondCallCount = await harness.device.setCallCount()
        XCTAssertEqual(halfSecondCallCount, 1)

        await harness.scheduler.advance(to: 1)
        await harness.device.waitForSetCount(2)
        await harness.scheduler.advance(to: 2)
        await harness.device.waitForSetCount(3)
        let runningCallCount = await harness.device.setCallCount()
        XCTAssertEqual(runningCallCount, 3)

        try harness.store.pause()
        await harness.scheduler.setInstant(3)
        await Task.yield()
        let pausedCallCount = await harness.device.setCallCount()
        XCTAssertEqual(pausedCallCount, 3)
    }

    func testTickBurstIsSingleInflightAndLatestOnly() async throws {
        let harness = try SimulationHarness()
        try await harness.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await harness.device.enqueue(.suspended)

        try harness.store.tick(at: 1)
        await harness.device.waitForSetCount(2)
        try harness.store.tick(at: 2)
        try harness.store.tick(at: 3)
        let maximumConcurrent = await harness.device.maximumConcurrentCalls()
        XCTAssertEqual(maximumConcurrent, 1)
        XCTAssertEqual(harness.store.routeSnapshot?.confirmedDistance, 0)

        await harness.device.completeNextSuspended()
        await harness.device.waitForSetCount(3)

        let calls = await harness.device.recordedSetCalls()
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(
            try XCTUnwrap(calls.last?.coordinate.longitude),
            3.75 / 900,
            accuracy: 0.000_001
        )
    }

    func testPauseDuringInflightCorrectsSnapshotAndNoInflightPauseSendsNothing() async throws {
        let inflight = try SimulationHarness()
        try await inflight.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await inflight.device.enqueue(.suspended)
        await inflight.device.enqueue(.suspended)
        try inflight.store.tick(at: 4)
        await inflight.device.waitForSetCount(2)

        try inflight.store.pause()
        XCTAssertEqual(inflight.store.routeSnapshot?.phase, .pausing)
        await inflight.device.completeNextSuspended()
        await inflight.device.waitForSetCount(3)
        let correctionCalls = await inflight.device.recordedSetCalls()
        XCTAssertEqual(correctionCalls.last?.coordinate, try DeviceCoordinate(latitude: 0, longitude: 0))
        await inflight.device.completeNextSuspended()
        await eventually { inflight.store.routeSnapshot?.phase == .paused }
        XCTAssertEqual(inflight.store.routeSnapshot?.confirmedDistance, 0)

        let noInflight = try SimulationHarness()
        try await noInflight.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        try noInflight.store.pause()
        XCTAssertEqual(noInflight.store.routeSnapshot?.phase, .paused)
        let noInflightCallCount = await noInflight.device.setCallCount()
        XCTAssertEqual(noInflightCallCount, 1)
    }

    func testUncertainInflightAndCorrectionPauseNeverShowPaused() async throws {
        for failingBehavior in [
            FakeSimulationDevice.Behavior.failure(.timeout),
            .failure(.transportFailure("correction failed")),
        ] {
            let harness = try SimulationHarness()
            try await harness.store.startRoute(
                preview: route(),
                speedKilometersPerHour: 4.5,
                roundTrip: false,
                riskAccepted: true
            )
            await harness.device.enqueue(.suspended)
            if failingBehavior != .failure(.timeout) {
                await harness.device.enqueue(.suspended)
            }
            try harness.store.tick(at: 4)
            await harness.device.waitForSetCount(2)
            try harness.store.pause()

            if failingBehavior == .failure(.timeout) {
                await harness.device.failNextSuspended(.timeout)
            } else {
                await harness.device.completeNextSuspended()
                await harness.device.waitForSetCount(3)
                await harness.device.failNextSuspended(.transportFailure("correction failed"))
            }
            await eventually { harness.store.routeSnapshot?.phase == .interrupted }
            XCTAssertEqual(
                harness.store.routeSnapshot?.interruption?.positionKnowledge,
                .unknown
            )
        }
    }

    func testPauseResumeAndSpeedRebaseCommitOnlyConfirmedDistance() async throws {
        let harness = try SimulationHarness()
        try await harness.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await harness.device.enqueue(.suspended)
        try harness.store.tick(at: 4)
        await harness.device.waitForSetCount(2)
        try harness.store.tick(at: 5)
        XCTAssertEqual(harness.store.routeSnapshot?.confirmedDistance, 0)

        try harness.store.setSpeed(6, at: 5)
        await harness.device.completeNextSuspended()
        await eventually {
            harness.store.routeSnapshot?.speedKilometersPerHour == 6
        }
        XCTAssertEqual(harness.store.routeSnapshot?.confirmedDistance, 5)

        try harness.store.pause()
        try harness.store.resume(at: 100)
        try harness.store.tick(at: 101)
        await harness.device.waitForSetCount(3)
        let resumedCalls = await harness.device.recordedSetCalls()
        XCTAssertEqual(
            try XCTUnwrap(resumedCalls.last?.coordinate.longitude),
            (5 + 6 / 3.6) / 900,
            accuracy: 0.000_001
        )
    }

    func testUncertainSpeedBarrierInterruptsWithUnknownPosition() async throws {
        let harness = try SimulationHarness()
        try await harness.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await harness.device.enqueue(.suspended)
        try harness.store.tick(at: 4)
        await harness.device.waitForSetCount(2)
        try harness.store.setSpeed(6, at: 4)
        await harness.device.failNextSuspended(.timeout)

        await eventually { harness.store.routeSnapshot?.phase == .interrupted }
        XCTAssertEqual(harness.store.routeSnapshot?.interruption, unknown(.timeout))
    }

    func testSingleTripCompletesAtBWhileRoundTripKeepsRunning() async throws {
        let single = try SimulationHarness()
        try await single.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        try single.store.tick(at: 720)
        await single.device.waitForSetCount(2)
        await eventually { single.store.routeSnapshot?.phase == .completed }
        XCTAssertEqual(single.store.routeSnapshot?.confirmedCoordinate?.longitude, 1)
        let singleClearCount = await single.device.recordedClearCallCount()
        XCTAssertEqual(singleClearCount, 0)

        let roundTrip = try SimulationHarness()
        try await roundTrip.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: true,
            riskAccepted: true
        )
        try roundTrip.store.tick(at: 722)
        await roundTrip.device.waitForSetCount(2)
        await eventually { roundTrip.store.routeSnapshot?.confirmedDirection == .towardA }
        XCTAssertEqual(roundTrip.store.routeSnapshot?.phase, .running)
        XCTAssertEqual(roundTrip.store.routeSnapshot?.confirmedDistance, 897.5)
    }

    func testTimeoutHelperAndTunnelFailuresStopProducerWithTypedInterruption() async throws {
        let cases: [(DeviceLocationError, InterruptionReason)] = [
            (.timeout, .timeout),
            (.helperFailure("exited"), .helperExited),
            (.tunnelFailure("ended"), .tunnelEnded),
        ]
        for (failure, reason) in cases {
            let harness = try SimulationHarness()
            try await harness.store.startRoute(
                preview: route(),
                speedKilometersPerHour: 4.5,
                roundTrip: false,
                riskAccepted: true
            )
            await harness.device.enqueue(.failure(failure))
            try harness.store.tick(at: 1)
            await eventually { harness.store.routeSnapshot?.phase == .interrupted }
            XCTAssertEqual(harness.store.routeSnapshot?.interruption, unknown(reason))
        }
    }

    func testStopWaitsForInflightThenClearsAndClearFailureIsRetryable() async throws {
        let harness = try SimulationHarness()
        try await harness.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await harness.device.enqueue(.suspended)
        try harness.store.tick(at: 1)
        await harness.device.waitForSetCount(2)

        let stop = Task { await harness.store.stop() }
        await Task.yield()
        let clearCountBeforeBarrier = await harness.device.recordedClearCallCount()
        XCTAssertEqual(clearCountBeforeBarrier, 0)
        await harness.device.completeNextSuspended()
        await stop.value
        XCTAssertEqual(harness.store.state, .idle)
        XCTAssertNil(harness.store.activeSessionID)

        await harness.store.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        await harness.device.enqueueClearFailure(.clearFailed("busy"))
        await harness.store.stop()
        guard case let .stopping(_, failure?) = harness.store.state else {
            return XCTFail("Expected retryable clear failure")
        }
        XCTAssertEqual(failure, .clearFailed("busy"))
        await harness.store.stop()
        XCTAssertEqual(harness.store.state, .idle)
    }

    func testStaleSessionAndEpochCompletionsCannotRewriteReplacement() async throws {
        let harness = try SimulationHarness()
        try await harness.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await harness.device.enqueue(.suspended)
        try harness.store.tick(at: 1)
        await harness.device.waitForSetCount(2)

        let replacement = Task {
            await harness.store.confirmPoint(
                try! DeviceCoordinate(latitude: 24, longitude: 120),
                riskAccepted: true
            )
        }
        await harness.device.completeNextSuspended()
        await replacement.value
        guard case let .pointActive(point) = harness.store.state else {
            return XCTFail("Expected replacement point")
        }

        await harness.device.completeAllSuspended()
        await Task.yield()
        XCTAssertEqual(harness.store.state, .pointActive(point))
    }

    func testSystemSleepObserverForwardsSleepAndWakeNotifications() {
        let center = NotificationCenter()
        let sleepName = Notification.Name("test-system-will-sleep")
        let wakeName = Notification.Name("test-system-did-wake")
        let handler = FakeSystemSleepHandler()
        let observer = SystemSleepObserver(
            handler: handler,
            notificationCenter: center,
            willSleepNotification: sleepName,
            didWakeNotification: wakeName
        )
        observer.start()

        center.post(name: sleepName, object: nil)
        center.post(name: wakeName, object: nil)

        XCTAssertEqual(handler.sleepCount, 1)
        XCTAssertEqual(handler.wakeCount, 1)
        observer.stop()
    }

    func testSleepDuringInflightWaitsForCorrectionBeforePaused() async throws {
        let harness = try SimulationHarness()
        try await harness.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await harness.device.enqueue(.suspended)
        await harness.device.enqueue(.suspended)
        try harness.store.tick(at: 4)
        await harness.device.waitForSetCount(2)

        harness.store.systemWillSleep()
        XCTAssertEqual(harness.store.routeSnapshot?.phase, .pausing)
        harness.store.systemDidWake()
        XCTAssertEqual(harness.store.routeSnapshot?.phase, .pausing)

        await harness.device.completeNextSuspended()
        await harness.device.waitForSetCount(3)
        await harness.device.completeNextSuspended()
        await eventually { harness.store.routeSnapshot?.phase == .paused }
        XCTAssertEqual(harness.store.routeSnapshot?.confirmedDistance, 0)
    }

    func testSleepUncertainMutationInterruptsWithUnknownPosition() async throws {
        let harness = try SimulationHarness()
        try await harness.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await harness.device.enqueue(.suspended)
        try harness.store.tick(at: 4)
        await harness.device.waitForSetCount(2)

        harness.store.systemWillSleep()
        await harness.device.failNextSuspended(.timeout)

        await eventually { harness.store.routeSnapshot?.phase == .interrupted }
        XCTAssertEqual(
            harness.store.routeSnapshot?.interruption,
            unknown(.timeout)
        )
    }

    func testSleepIgnoresPointAndCompletedAndElapsedSleepAddsNoDistance() async throws {
        let point = try SimulationHarness()
        await point.store.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        let pointState = point.store.state
        point.store.systemWillSleep()
        XCTAssertEqual(point.store.state, pointState)

        let completed = try SimulationHarness()
        try await completed.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        try completed.store.tick(at: 720)
        await completed.device.waitForSetCount(2)
        await eventually { completed.store.routeSnapshot?.phase == .completed }
        completed.store.systemWillSleep()
        XCTAssertEqual(completed.store.routeSnapshot?.phase, .completed)

        let paused = try SimulationHarness()
        try await paused.store.startRoute(
            preview: route(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        paused.store.systemWillSleep()
        XCTAssertEqual(paused.store.routeSnapshot?.phase, .paused)
        await paused.scheduler.setInstant(100)
        paused.store.systemDidWake()
        try paused.store.resume(at: 100)
        try paused.store.tick(at: 101)
        await paused.device.waitForSetCount(2)
        await eventually { paused.store.routeSnapshot?.confirmedDistance == 1.25 }
        XCTAssertEqual(paused.store.routeSnapshot?.confirmedDistance, 1.25)
    }

    private func route() -> RoutePreview {
        try! RoutePreview(points: [
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 0, longitude: 0),
                cumulativeDistance: 0
            ),
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 0, longitude: 1),
                cumulativeDistance: 900
            ),
        ])
    }

    private func unknown(_ reason: InterruptionReason) -> DeviceInterruption {
        DeviceInterruption(reason: reason, positionKnowledge: .unknown)
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 200 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class FakeSystemSleepHandler: SystemSleepHandling {
    private(set) var sleepCount = 0
    private(set) var wakeCount = 0

    func systemWillSleep() {
        sleepCount += 1
    }

    func systemDidWake() {
        wakeCount += 1
    }
}

@MainActor
private struct SimulationHarness {
    let device = FakeSimulationDevice()
    let scheduler = FakeSimulationScheduler()
    let store: SimulationStore

    init() throws {
        store = SimulationStore(
            device: device,
            generation: DeviceSessionGeneration(rawValue: 1),
            scheduler: scheduler
        )
    }
}

private actor FakeSimulationDevice: DeviceLocationClient {
    enum Behavior: Equatable, Sendable {
        case success
        case failure(DeviceLocationError)
        case suspended
    }

    struct SetCall: Equatable, Sendable {
        let coordinate: DeviceCoordinate
        let context: DeviceMutationContext
    }

    private struct Pending {
        let continuation: CheckedContinuation<Void, Error>
    }

    private var behaviors: [Behavior] = []
    private var pending: [Pending] = []
    private(set) var setCalls: [SetCall] = []
    private(set) var clearCallCount = 0
    private var clearFailures: [DeviceLocationError] = []
    private var concurrentSetCount = 0
    private(set) var maximumConcurrentSetCount = 0

    func enqueue(_ behavior: Behavior) {
        behaviors.append(behavior)
    }

    func enqueueClearFailure(_ error: DeviceLocationError) {
        clearFailures.append(error)
    }

    func waitForSetCount(_ count: Int) async {
        while setCalls.count < count {
            await Task.yield()
        }
    }

    func setCallCount() -> Int {
        setCalls.count
    }

    func recordedSetCalls() -> [SetCall] {
        setCalls
    }

    func maximumConcurrentCalls() -> Int {
        maximumConcurrentSetCount
    }

    func recordedClearCallCount() -> Int {
        clearCallCount
    }

    func completeNextSuspended() {
        pending.removeFirst().continuation.resume()
    }

    func failNextSuspended(_ error: DeviceLocationError) {
        pending.removeFirst().continuation.resume(throwing: error)
    }

    func completeAllSuspended() {
        while !pending.isEmpty {
            pending.removeFirst().continuation.resume()
        }
    }

    func discoverUSBDevices() async throws -> [USBDevice] {
        []
    }

    func prepare(deviceID: DeviceID) async throws -> PreparedDeviceSession {
        throw DeviceLocationError.deviceNotFound
    }

    func setLocation(
        _ coordinate: DeviceCoordinate,
        context: DeviceMutationContext
    ) async throws {
        setCalls.append(SetCall(coordinate: coordinate, context: context))
        concurrentSetCount += 1
        maximumConcurrentSetCount = max(maximumConcurrentSetCount, concurrentSetCount)
        defer { concurrentSetCount -= 1 }

        let behavior = behaviors.isEmpty ? .success : behaviors.removeFirst()
        switch behavior {
        case .success:
            return
        case let .failure(error):
            throw error
        case .suspended:
            try await withCheckedThrowingContinuation { continuation in
                pending.append(Pending(continuation: continuation))
            }
        }
    }

    func clearLocation(context: DeviceCleanupContext) async throws {
        clearCallCount += 1
        if !clearFailures.isEmpty {
            throw clearFailures.removeFirst()
        }
    }

    func shutdown(generation: DeviceSessionGeneration) async {}
}

private actor FakeSimulationScheduler: SimulationScheduling {
    private var instant: TimeInterval = 0
    private var sleepers: [CheckedContinuation<Void, Error>] = []

    func now() -> TimeInterval {
        instant
    }

    func waitForNextTick() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append(continuation)
        }
    }

    func advance(to newInstant: TimeInterval) async {
        while sleepers.isEmpty {
            await Task.yield()
        }
        instant = newInstant
        sleepers.removeFirst().resume()
    }

    func setInstant(_ newInstant: TimeInterval) {
        instant = newInstant
    }
}
