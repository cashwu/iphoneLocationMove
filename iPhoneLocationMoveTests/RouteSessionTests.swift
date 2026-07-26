import XCTest
@testable import iPhoneLocationMove

final class RouteSessionTests: XCTestCase {
    func testNormativeStateTransitionsRejectUnlistedTransitions() throws {
        let session = try makeSession()

        XCTAssertEqual(session.phase, .idle)
        XCTAssertThrowsError(try session.start(at: 0))

        try session.loadPreview(route())
        XCTAssertEqual(session.phase, .preview)
        try session.cancelPreview()
        XCTAssertEqual(session.phase, .idle)

        try session.loadPreview(route())
        try session.start(at: 0)
        XCTAssertEqual(session.phase, .running)

        XCTAssertNil(try session.pause())
        XCTAssertEqual(session.phase, .paused)
        try session.resume(at: 30)
        XCTAssertEqual(session.phase, .running)

        try session.requestStop()
        XCTAssertEqual(session.phase, .stopping)
        try session.clearFailed()
        XCTAssertEqual(session.phase, .stopping)
        try session.clearSucceeded()
        XCTAssertEqual(session.phase, .idle)
    }

    func testFirstMutationFailureInterruptsWithUnknownPosition() throws {
        let session = try makeSession()
        try session.loadPreview(route())

        try session.startFailed(reason: .deviceMutationFailed)

        XCTAssertEqual(session.phase, .interrupted)
        XCTAssertEqual(
            session.interruption,
            DeviceInterruption(reason: .deviceMutationFailed, positionKnowledge: .unknown)
        )
        XCTAssertNil(try session.tick(at: 10))
    }

    func testDefaultSpeedCompletesNineHundredMetersInTwelveMinutes() throws {
        let session = try runningSession()

        let update = try XCTUnwrap(session.tick(at: 720))
        XCTAssertEqual(update.distanceFromA, 900, accuracy: 0.000_001)
        XCTAssertEqual(update.coordinate, RouteCoordinate(latitude: 0, longitude: 1))
        XCTAssertEqual(session.phase, .running, "B is not committed until the mutation succeeds")

        _ = try session.completeUpdate(update.token, result: .success, at: 720)

        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.confirmedDistance, 900, accuracy: 0.000_001)
        XCTAssertEqual(session.estimatedDuration, 720, accuracy: 0.000_001)
    }

    func testDelayedTickUsesActualMonotonicElapsedTime() throws {
        let session = try runningSession()

        let delayedUpdate = try XCTUnwrap(session.tick(at: 8))

        XCTAssertEqual(delayedUpdate.distanceFromA, 10, accuracy: 0.000_001)
    }

    func testUpdatesAreScheduledAtApproximatelyOneSecondIntervals() throws {
        let session = try runningSession()

        XCTAssertNil(try session.tick(at: 0.9))
        let first = try XCTUnwrap(session.tick(at: 1.0))
        XCTAssertNil(try session.tick(at: 1.5))
        _ = try session.completeUpdate(first.token, result: .success, at: 1.5)
        XCTAssertNotNil(try session.tick(at: 2.0))
    }

    func testPauseAndResumeExcludePausedElapsedTime() throws {
        let session = try runningSession()
        let first = try XCTUnwrap(session.tick(at: 8))
        _ = try session.completeUpdate(first.token, result: .success, at: 8)

        XCTAssertNil(try session.pause())
        XCTAssertEqual(session.phase, .paused)
        XCTAssertNil(try session.tick(at: 100))

        try session.resume(at: 100)
        let resumed = try XCTUnwrap(session.tick(at: 104))

        XCTAssertEqual(resumed.distanceFromA, 15, accuracy: 0.000_001)
    }

    func testSpeedRebaseWaitsForInflightSuccessAndUsesConfirmedDistance() throws {
        let session = try runningSession()
        let inflight = try XCTUnwrap(session.tick(at: 8))

        try session.setSpeed(kilometersPerHour: 7, at: 9)

        XCTAssertEqual(session.speedKilometersPerHour, 4.5)
        XCTAssertEqual(session.confirmedDistance, 0)
        XCTAssertNil(try session.tick(at: 10))

        _ = try session.completeUpdate(inflight.token, result: .success, at: 10)

        XCTAssertEqual(session.speedKilometersPerHour, 7)
        XCTAssertEqual(session.confirmedDistance, 10, accuracy: 0.000_001)
        let rebased = try XCTUnwrap(session.tick(at: 11))
        XCTAssertEqual(rebased.distanceFromA, 10 + (7.0 / 3.6), accuracy: 0.000_001)
    }

    func testSpeedRebaseUncertainResultInterruptsWithoutPublishingUnconfirmedProgress() throws {
        let session = try runningSession()
        let inflight = try XCTUnwrap(session.tick(at: 8))

        try session.setSpeed(kilometersPerHour: 6, at: 9)
        _ = try session.completeUpdate(
            inflight.token,
            result: .uncertain(.timeout),
            at: 10
        )

        XCTAssertEqual(session.phase, .interrupted)
        XCTAssertEqual(session.confirmedDistance, 0)
        XCTAssertEqual(session.interruption?.positionKnowledge, .unknown)
    }

    func testEndpointSuccessDuringSpeedBarrierStillCompletesSingleTrip() throws {
        let session = try runningSession()
        let endpoint = try XCTUnwrap(session.tick(at: 720))

        try session.setSpeed(kilometersPerHour: 6, at: 721)
        _ = try session.completeUpdate(endpoint.token, result: .success, at: 722)

        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.confirmedDistance, 900, accuracy: 0.000_001)
    }

    func testSingleInflightUpdateCoalescesOnlyLatestPendingCoordinate() throws {
        let session = try runningSession()
        let first = try XCTUnwrap(session.tick(at: 1))

        XCTAssertNil(try session.tick(at: 2))
        XCTAssertNil(try session.tick(at: 3))
        XCTAssertEqual(
            try XCTUnwrap(session.pendingDistance),
            3.75,
            accuracy: 0.000_001
        )

        let next = try XCTUnwrap(
            session.completeUpdate(first.token, result: .success, at: 3)
        )

        XCTAssertEqual(next.distanceFromA, 3.75, accuracy: 0.000_001)
        XCTAssertEqual(session.confirmedDistance, 1.25, accuracy: 0.000_001)
    }

    func testStaleCompletionAfterStopCannotRewriteCurrentState() throws {
        let session = try runningSession()
        let stale = try XCTUnwrap(session.tick(at: 1))

        try session.requestStop()
        XCTAssertNil(
            try session.completeUpdate(stale.token, result: .success, at: 2)
        )

        XCTAssertEqual(session.phase, .stopping)
        XCTAssertEqual(session.confirmedDistance, 0)
    }

    func testPauseDuringInflightCorrectsToSnapshotBeforeBecomingPaused() throws {
        let session = try runningSession()
        let inflight = try XCTUnwrap(session.tick(at: 4))
        XCTAssertNil(try session.tick(at: 5))

        XCTAssertNil(try session.pause())
        XCTAssertEqual(session.phase, .pausing)
        XCTAssertNil(session.pendingDistance)

        let correction = try XCTUnwrap(
            session.completeUpdate(inflight.token, result: .success, at: 5)
        )
        XCTAssertEqual(session.phase, .pausing)
        XCTAssertEqual(correction.kind, .pauseCorrection)
        XCTAssertEqual(correction.distanceFromA, 0, accuracy: 0.000_001)

        _ = try session.completeUpdate(correction.token, result: .success, at: 6)
        XCTAssertEqual(session.phase, .paused)
        XCTAssertEqual(session.confirmedDistance, 0, accuracy: 0.000_001)
    }

    func testPauseDuringInflightUncertainResultInterrupts() throws {
        let session = try runningSession()
        let inflight = try XCTUnwrap(session.tick(at: 4))
        _ = try session.pause()

        _ = try session.completeUpdate(
            inflight.token,
            result: .uncertain(.timeout),
            at: 5
        )

        XCTAssertEqual(session.phase, .interrupted)
        XCTAssertEqual(session.interruption?.positionKnowledge, .unknown)
    }

    func testRoundTripPreservesEndpointOverflowAndReversesDirection() throws {
        let session = try runningSession(roundTrip: true)

        let update = try XCTUnwrap(session.tick(at: 722))

        XCTAssertEqual(update.distanceFromA, 897.5, accuracy: 0.000_001)
        XCTAssertEqual(update.direction, .towardA)
        XCTAssertEqual(update.coordinate.longitude, 897.5 / 900, accuracy: 0.000_001)
    }

    func testRoundTripMapsAcrossMultipleCycles() throws {
        let session = try runningSession(roundTrip: true)

        let update = try XCTUnwrap(session.tick(at: 2_882))

        XCTAssertEqual(update.distanceFromA, 2.5, accuracy: 0.000_001)
        XCTAssertEqual(update.direction, .towardB)
    }

    func testSleepPauseOnlyAppliesWhileRunning() throws {
        let preview = try makeSession()
        try preview.loadPreview(route())
        XCTAssertFalse(try preview.handleSleep())
        XCTAssertEqual(preview.phase, .preview)

        let running = try runningSession()
        XCTAssertTrue(try running.handleSleep())
        XCTAssertEqual(running.phase, .paused)

        let completed = try runningSession()
        let endpoint = try XCTUnwrap(completed.tick(at: 720))
        _ = try completed.completeUpdate(endpoint.token, result: .success, at: 720)
        XCTAssertFalse(try completed.handleSleep())
        XCTAssertEqual(completed.phase, .completed)
    }

    func testRoundTripAndCompletedSessionsSupportInterruptionAndStopTransitions() throws {
        let interrupted = try runningSession(roundTrip: true)
        try interrupted.interrupt(
            reason: .transportFailure,
            positionKnowledge: .unknown
        )
        XCTAssertEqual(interrupted.phase, .interrupted)
        XCTAssertNil(try interrupted.tick(at: 10))
        try interrupted.requestStop()
        XCTAssertEqual(interrupted.phase, .stopping)

        let completed = try runningSession()
        let endpoint = try XCTUnwrap(completed.tick(at: 720))
        _ = try completed.completeUpdate(endpoint.token, result: .success, at: 720)
        try completed.requestStop()
        XCTAssertEqual(completed.phase, .stopping)
    }

    private func makeSession(
        roundTrip: Bool = false,
        speed: Double = 4.5
    ) throws -> RouteSession {
        try RouteSession(
            speedKilometersPerHour: speed,
            roundTrip: roundTrip
        )
    }

    private func runningSession(
        roundTrip: Bool = false,
        speed: Double = 4.5
    ) throws -> RouteSession {
        let session = try makeSession(roundTrip: roundTrip, speed: speed)
        try session.loadPreview(route())
        try session.start(at: 0)
        return session
    }

    private func route() -> RoutePreview {
        try! RoutePreview(points: [
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 0, longitude: 0),
                cumulativeDistance: 0
            ),
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 0, longitude: 0.5),
                cumulativeDistance: 450
            ),
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 0, longitude: 1),
                cumulativeDistance: 900
            ),
        ])
    }
}
