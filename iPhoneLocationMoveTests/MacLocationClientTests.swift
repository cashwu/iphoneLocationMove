import CoreLocation
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class MacLocationClientTests: XCTestCase {
    func testAuthorizedRequestReturnsCurrentCoordinate() async throws {
        let boundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let factory = FakeMacLocationManagerFactory([boundary])
        let client = makeClient(factory: factory)

        let request = requestTask(client)
        await waitUntil { boundary.requestLocationCallCount == 1 }
        boundary.sendLocation(latitude: 25.033_968, longitude: 121.564_468)

        let coordinate = try await request.value.get()
        XCTAssertEqual(
            coordinate,
            try MapCoordinate(latitude: 25.033_968, longitude: 121.564_468)
        )
        XCTAssertEqual(boundary.requestAuthorizationCallCount, 0)
        XCTAssertEqual(boundary.requestLocationCallCount, 1)
    }

    func testNotDeterminedRequestsWhenInUseAuthorizationThenRequestsOneLocation() async throws {
        let boundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .notDetermined
        )
        let factory = FakeMacLocationManagerFactory([boundary])
        let client = makeClient(factory: factory)

        let request = requestTask(client)
        await waitUntil { boundary.requestAuthorizationCallCount == 1 }
        XCTAssertEqual(boundary.requestLocationCallCount, 0)

        boundary.sendAuthorization(.authorizedAlways)
        XCTAssertEqual(boundary.requestLocationCallCount, 1)
        boundary.sendLocation(latitude: 25, longitude: 121)

        _ = try await request.value.get()
        XCTAssertEqual(boundary.requestAuthorizationCallCount, 1)
        XCTAssertEqual(boundary.requestLocationCallCount, 1)
    }

    func testDeniedAuthorizationReturnsTypedErrorWithoutRequestingLocation() async {
        let boundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .denied
        )
        let client = makeClient(
            factory: FakeMacLocationManagerFactory([boundary])
        )

        let result = await client.requestCurrentLocationResult()

        assertFailure(result, equals: .authorizationDenied)
        XCTAssertEqual(boundary.requestLocationCallCount, 0)
    }

    func testRestrictedAuthorizationReturnsTypedErrorWithoutRequestingLocation() async {
        let boundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .restricted
        )
        let client = makeClient(
            factory: FakeMacLocationManagerFactory([boundary])
        )

        let result = await client.requestCurrentLocationResult()

        assertFailure(result, equals: .authorizationRestricted)
        XCTAssertEqual(boundary.requestLocationCallCount, 0)
    }

    func testDisabledLocationServicesReturnsTypedErrorWithoutCreatingManager() async {
        let factory = FakeMacLocationManagerFactory([])
        let client = makeClient(
            locationServicesEnabled: { false },
            factory: factory
        )

        let result = await client.requestCurrentLocationResult()

        assertFailure(result, equals: .locationServicesDisabled)
        XCTAssertTrue(factory.createdManagers.isEmpty)
    }

    func testDelegateFailureReturnsTypedError() async {
        let boundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let client = makeClient(
            factory: FakeMacLocationManagerFactory([boundary])
        )

        let request = requestTask(client)
        await waitUntil { boundary.requestLocationCallCount == 1 }
        boundary.sendFailure(TestLocationError.expected)

        assertFailure(await request.value, equals: .locationFailed)
    }

    func testInvalidCoordinateReturnsTypedError() async {
        let boundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let client = makeClient(
            factory: FakeMacLocationManagerFactory([boundary])
        )

        let request = requestTask(client)
        await waitUntil { boundary.requestLocationCallCount == 1 }
        boundary.sendLocation(latitude: 91, longitude: 121)

        assertFailure(await request.value, equals: .invalidCoordinate)
    }

    func testConcurrentRequestIsRejectedWithoutReplacingFirstContinuation() async throws {
        let boundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let factory = FakeMacLocationManagerFactory([boundary])
        let client = makeClient(factory: factory)

        let firstRequest = requestTask(client)
        await waitUntil { boundary.requestLocationCallCount == 1 }

        let secondResult = await client.requestCurrentLocationResult()
        assertFailure(secondResult, equals: .requestInProgress)
        XCTAssertEqual(factory.createdManagers.count, 1)

        boundary.sendLocation(latitude: 24, longitude: 120)
        let firstCoordinate = try await firstRequest.value.get()
        XCTAssertEqual(
            firstCoordinate,
            try MapCoordinate(latitude: 24, longitude: 120)
        )
    }

    func testTaskCancellationCompletesWithTypedErrorAndClearsOwnership() async {
        let firstBoundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let secondBoundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let factory = FakeMacLocationManagerFactory([
            firstBoundary,
            secondBoundary,
        ])
        let client = makeClient(factory: factory)

        let firstRequest = requestTask(client)
        await waitUntil { firstBoundary.requestLocationCallCount == 1 }
        firstRequest.cancel()
        assertFailure(await firstRequest.value, equals: .cancelled)

        let secondRequest = requestTask(client)
        await waitUntil { secondBoundary.requestLocationCallCount == 1 }
        secondBoundary.sendLocation(latitude: 23, longitude: 120)
        switch await secondRequest.value {
        case .success:
            break
        case let .failure(error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testAlreadyCancelledTaskReturnsTypedErrorWithoutCreatingManager() async {
        let factory = FakeMacLocationManagerFactory([])
        let client = makeClient(factory: factory)

        let result = await Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await client.requestCurrentLocationResult()
        }.value

        assertFailure(result, equals: .cancelled)
        XCTAssertTrue(factory.createdManagers.isEmpty)
    }

    func testCancellationDuringManagerCreationDoesNotInstallCallbacks() async {
        let boundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let client = LiveMacLocationClient(
            locationServicesEnabled: { true },
            managerFactory: {
                withUnsafeCurrentTask { task in
                    task?.cancel()
                }
                return boundary
            }
        )

        let result = await client.requestCurrentLocationResult()

        assertFailure(result, equals: .cancelled)
        XCTAssertNil(boundary.onAuthorizationChange)
        XCTAssertNil(boundary.onLocations)
        XCTAssertNil(boundary.onFailure)
        XCTAssertEqual(boundary.requestLocationCallCount, 0)
    }

    func testCancelledOldManagerLateCallbackCannotCompleteNewRequest() async throws {
        let oldBoundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let newBoundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let factory = FakeMacLocationManagerFactory([
            oldBoundary,
            newBoundary,
        ])
        let client = makeClient(factory: factory)

        let oldRequest = requestTask(client)
        await waitUntil { oldBoundary.requestLocationCallCount == 1 }
        let lateCallbacks = oldBoundary.snapshotCallbacks()
        oldRequest.cancel()
        _ = await oldRequest.value

        let newRequest = requestTask(client)
        await waitUntil { newBoundary.requestLocationCallCount == 1 }
        let completion = CompletionProbe()
        let observedNewRequest = Task { @MainActor in
            let result = await newRequest.value
            completion.record(result)
        }

        lateCallbacks.locations([
            CLLocation(latitude: 1, longitude: 1),
        ])
        await yieldExecution()
        XCTAssertEqual(completion.count, 0)

        newBoundary.sendLocation(latitude: 22.627_278, longitude: 120.301_435)
        _ = await observedNewRequest.value
        XCTAssertEqual(completion.count, 1)
        XCTAssertEqual(
            try completion.result?.get(),
            try MapCoordinate(latitude: 22.627_278, longitude: 120.301_435)
        )
    }

    func testTerminalCallbacksResumeContinuationExactlyOnce() async throws {
        let boundary = FakeMacLocationManagerBoundary(
            authorizationStatus: .authorizedAlways
        )
        let client = makeClient(
            factory: FakeMacLocationManagerFactory([boundary])
        )

        let request = requestTask(client)
        await waitUntil { boundary.requestLocationCallCount == 1 }
        let callbacks = boundary.snapshotCallbacks()
        let completion = CompletionProbe()
        let observer = Task { @MainActor in
            completion.record(await request.value)
        }

        callbacks.locations([CLLocation(latitude: 25, longitude: 121)])
        callbacks.failure(TestLocationError.expected)
        callbacks.authorizationChanged()
        await observer.value
        await yieldExecution()

        XCTAssertEqual(completion.count, 1)
        XCTAssertEqual(
            try completion.result?.get(),
            try MapCoordinate(latitude: 25, longitude: 121)
        )
    }
}

@MainActor
private extension MacLocationClientTests {
    func makeClient(
        locationServicesEnabled: @escaping @MainActor () -> Bool = { true },
        factory: FakeMacLocationManagerFactory
    ) -> LiveMacLocationClient {
        LiveMacLocationClient(
            locationServicesEnabled: locationServicesEnabled,
            managerFactory: factory.makeManager
        )
    }

    func requestTask(
        _ client: LiveMacLocationClient
    ) -> Task<Result<MapCoordinate, Error>, Never> {
        Task { @MainActor in
            await client.requestCurrentLocationResult()
        }
    }

    func assertFailure(
        _ result: Result<MapCoordinate, Error>,
        equals expected: MacLocationClientError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .failure(error) = result else {
            XCTFail("Expected failure, got \(result)", file: file, line: line)
            return
        }
        XCTAssertEqual(
            error as? MacLocationClientError,
            expected,
            file: file,
            line: line
        )
    }

    func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 100 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    func yieldExecution() async {
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }

}

private extension MacLocationProviding {
    func requestCurrentLocationResult() async -> Result<MapCoordinate, Error> {
        do {
            return .success(try await requestCurrentLocation())
        } catch {
            return .failure(error)
        }
    }
}

@MainActor
private final class FakeMacLocationManagerFactory {
    private var managers: [FakeMacLocationManagerBoundary]
    private(set) var createdManagers: [FakeMacLocationManagerBoundary] = []

    init(_ managers: [FakeMacLocationManagerBoundary]) {
        self.managers = managers
    }

    func makeManager() -> any MacLocationManagerBoundary {
        precondition(!managers.isEmpty, "Unexpected manager creation")
        let manager = managers.removeFirst()
        createdManagers.append(manager)
        return manager
    }
}

@MainActor
private final class FakeMacLocationManagerBoundary: MacLocationManagerBoundary {
    var authorizationStatus: CLAuthorizationStatus
    var onAuthorizationChange: (() -> Void)?
    var onLocations: (([CLLocation]) -> Void)?
    var onFailure: ((Error) -> Void)?

    private(set) var requestAuthorizationCallCount = 0
    private(set) var requestLocationCallCount = 0

    init(authorizationStatus: CLAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        requestAuthorizationCallCount += 1
    }

    func requestLocation() {
        requestLocationCallCount += 1
    }

    func sendAuthorization(_ authorizationStatus: CLAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
        onAuthorizationChange?()
    }

    func sendLocation(latitude: Double, longitude: Double) {
        onLocations?([
            CLLocation(latitude: latitude, longitude: longitude),
        ])
    }

    func sendFailure(_ error: Error) {
        onFailure?(error)
    }

    func snapshotCallbacks() -> CallbackSnapshot {
        CallbackSnapshot(
            authorizationChanged: onAuthorizationChange ?? {},
            locations: onLocations ?? { _ in },
            failure: onFailure ?? { _ in }
        )
    }
}

private struct CallbackSnapshot {
    let authorizationChanged: () -> Void
    let locations: ([CLLocation]) -> Void
    let failure: (Error) -> Void
}

@MainActor
private final class CompletionProbe {
    private(set) var count = 0
    private(set) var result: Result<MapCoordinate, Error>?

    func record(_ result: Result<MapCoordinate, Error>) {
        count += 1
        self.result = result
    }
}

private enum TestLocationError: Error {
    case expected
}
