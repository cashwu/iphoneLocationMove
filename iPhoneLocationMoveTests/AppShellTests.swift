import AppKit
import SwiftUI
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class AppShellTests: XCTestCase {
    func testMainWindowHasStableIdentifierForReopening() {
        XCTAssertEqual(AppWindow.mainID, "main")
    }

    func testCoordinatorDoesNotRequestLocationUntilDeviceIsReady() async {
        let provider = ControllableMacLocationProvider()
        let coordinator = MacLocationCoordinator(provider: provider)

        coordinator.updateReadyGeneration(nil)
        await drainMainActor()

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertNil(coordinator.coordinate)
        XCTAssertNil(coordinator.message)
    }

    func testReadyGenerationRequestsAtMostOnceAcrossRepeatedUpdatesAndShellRebuild()
        async throws
    {
        let harness = try AppShellHarness(
            outcomes: [.ready(generation: 1)]
        )
        let provider = ControllableMacLocationProvider()
        let coordinator = MacLocationCoordinator(provider: provider)
        var window: NSWindow? = hostWorkspace(
            store: harness.store,
            coordinator: coordinator
        )

        await harness.store.start()
        require(await provider.waitForRequestCount(1))
        provider.succeedRequest(
            at: 0,
            with: coordinate(latitude: 25.04, longitude: 121.52)
        )
        require(await waitUntil { coordinator.coordinate != nil })

        coordinator.updateReadyGeneration(
            DeviceSessionGeneration(rawValue: 1)
        )
        coordinator.updateReadyGeneration(
            DeviceSessionGeneration(rawValue: 1)
        )
        await drainMainActor()

        window?.orderOut(nil)
        window?.contentView = nil
        window = hostWorkspace(
            store: harness.store,
            coordinator: coordinator
        )
        defer {
            window?.orderOut(nil)
            window?.contentView = nil
        }
        await drainMainActor()

        XCTAssertEqual(provider.requestCount, 1)
    }

    func testReplacementCancelsAndCompletesPendingGenerationBeforeStartingLatest()
        async throws
    {
        let provider = ControllableMacLocationProvider()
        let coordinator = MacLocationCoordinator(provider: provider)
        let generationA = DeviceSessionGeneration(rawValue: 10)
        let generationB = DeviceSessionGeneration(rawValue: 11)
        let staleCoordinate = coordinate(latitude: 25.03, longitude: 121.56)
        let currentCoordinate = coordinate(latitude: 24.14, longitude: 120.68)

        coordinator.updateReadyGeneration(generationA)
        require(await provider.waitForRequestCount(1))

        coordinator.updateReadyGeneration(generationB)
        require(await provider.waitForCancellationCount(1))
        XCTAssertEqual(provider.requestCount, 1)

        provider.succeedRequest(at: 0, with: staleCoordinate)
        require(await provider.waitForRequestCount(2))
        XCTAssertNil(coordinator.coordinate)
        XCTAssertNil(coordinator.message)

        provider.succeedRequest(at: 1, with: currentCoordinate)
        require(
            await waitUntil { coordinator.coordinate == currentCoordinate }
        )
        XCTAssertNotEqual(coordinator.coordinate, staleCoordinate)
    }

    func testLateFailureFromReplacedGenerationDoesNotPublishPresentation()
        async
    {
        let provider = ControllableMacLocationProvider()
        let coordinator = MacLocationCoordinator(provider: provider)

        coordinator.updateReadyGeneration(
            DeviceSessionGeneration(rawValue: 20)
        )
        require(await provider.waitForRequestCount(1))

        coordinator.updateReadyGeneration(
            DeviceSessionGeneration(rawValue: 21)
        )
        require(await provider.waitForCancellationCount(1))
        provider.failRequest(at: 0, with: TestMacLocationError.unavailable)
        require(await provider.waitForRequestCount(2))

        XCTAssertNil(coordinator.coordinate)
        XCTAssertNil(coordinator.message)

        let currentCoordinate = coordinate(
            latitude: 23.48,
            longitude: 120.45
        )
        provider.succeedRequest(at: 1, with: currentCoordinate)
        require(
            await waitUntil { coordinator.coordinate == currentCoordinate }
        )
    }

    func testSameStorePublicationsDriveReadyGenerationsWithoutDeviceMutation()
        async throws
    {
        let harness = try AppShellHarness(
            outcomes: [
                .ready(generation: 30),
                .failure(.noUSBDevice),
                .ready(generation: 31),
                .ready(generation: 32)
            ]
        )
        let provider = ControllableMacLocationProvider()
        let coordinator = MacLocationCoordinator(provider: provider)
        let window = hostWorkspace(
            store: harness.store,
            coordinator: coordinator
        )
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        await drainMainActor()
        XCTAssertEqual(provider.requestCount, 0)

        await harness.store.start()
        require(await provider.waitForRequestCount(1))
        provider.succeedRequest(
            at: 0,
            with: coordinate(latitude: 25.04, longitude: 121.56)
        )
        require(await waitUntil { coordinator.coordinate != nil })

        await harness.store.retry()
        XCTAssertEqual(harness.store.state, .noUSBDevice)
        await drainMainActor()

        await harness.store.retry()
        require(await provider.waitForRequestCount(2))
        provider.failRequest(at: 1, with: TestMacLocationError.unavailable)
        require(await waitUntil { coordinator.message != nil })

        await harness.store.retry()
        require(await provider.waitForRequestCount(3))
        provider.succeedRequest(
            at: 2,
            with: coordinate(latitude: 22.63, longitude: 120.30)
        )
        require(await waitUntil {
            coordinator.coordinate
                == self.coordinate(latitude: 22.63, longitude: 120.30)
        })

        let setLocationCallCount =
            await harness.device.setLocationCallCount()
        XCTAssertEqual(setLocationCallCount, 0)
    }

    private func require(
        _ condition: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(condition, file: file, line: line)
    }

    private func hostWorkspace(
        store: DeviceSetupStore,
        coordinator: MacLocationCoordinator
    ) -> NSWindow {
        let hostingView = NSHostingView(
            rootView: LocationWorkspaceView(
                store: store,
                macLocationCoordinator: coordinator
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        return window
    }

    private func coordinate(
        latitude: Double,
        longitude: Double
    ) -> MapCoordinate {
        try! MapCoordinate(latitude: latitude, longitude: longitude)
    }

    private func drainMainActor() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0 ..< 200 {
            if predicate() {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

@MainActor
private final class ControllableMacLocationProvider: MacLocationProviding {
    private(set) var requestCount = 0
    private(set) var cancelledRequestIDs: [Int] = []
    private var continuations: [
        Int: CheckedContinuation<MapCoordinate, Error>
    ] = [:]

    func requestCurrentLocation() async throws -> MapCoordinate {
        let requestID = requestCount
        requestCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[requestID] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelledRequestIDs.append(requestID)
            }
        }
    }

    func succeedRequest(
        at requestID: Int,
        with coordinate: MapCoordinate
    ) {
        continuations.removeValue(forKey: requestID)?.resume(
            returning: coordinate
        )
    }

    func failRequest(
        at requestID: Int,
        with error: Error
    ) {
        continuations.removeValue(forKey: requestID)?.resume(
            throwing: error
        )
    }

    func waitForRequestCount(_ expectedCount: Int) async -> Bool {
        await waitUntil { requestCount == expectedCount }
    }

    func waitForCancellationCount(_ expectedCount: Int) async -> Bool {
        await waitUntil {
            cancelledRequestIDs.count == expectedCount
        }
    }

    private func waitUntil(
        _ predicate: () -> Bool
    ) async -> Bool {
        for _ in 0 ..< 200 {
            if predicate() {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

private enum TestMacLocationError: Error {
    case unavailable
}

private enum AppShellConnectionOutcome: Sendable {
    case ready(generation: UInt64)
    case failure(DeviceLocationError)
}

@MainActor
private struct AppShellHarness {
    let device: AppShellDevice
    let store: DeviceSetupStore

    init(outcomes: [AppShellConnectionOutcome]) throws {
        let device = try USBDevice(
            id: DeviceID("app-shell-device"),
            name: "iPhone",
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 17,
                minorVersion: 0,
                patchVersion: 0
            )
        )
        let setupDevice = AppShellDevice(
            device: device,
            outcomes: outcomes
        )
        self.device = setupDevice
        store = DeviceSetupStore(
            runtimeManager: AppShellRuntime(),
            device: setupDevice,
            helperAuthorizer: AppShellAuthorizer(),
            lifecycleCoordinator: AppLifecycleCoordinator(),
            sleepObserver: SystemSleepObserver(
                notificationCenter: NotificationCenter(),
                willSleepNotification: Notification.Name("unused-sleep"),
                didWakeNotification: Notification.Name("unused-wake")
            )
        )
    }
}

private actor AppShellRuntime: DeviceRuntimeManaging {
    func inspect() async -> RuntimeAvailability {
        .ready(
            RuntimeInstallation(
                executableURL: URL(fileURLWithPath: "/runtime/pymobiledevice3"),
                source: .existing
            )
        )
    }

    func install(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async -> RuntimeInstallResult {
        .cancelled
    }

    func cancelRuntimeInstallation() async {}
}

private actor AppShellAuthorizer: TunnelHelperAuthorizing {
    func inspect() async -> TunnelHelperAuthorizationStatus {
        .enabled
    }

    func requestApproval() async -> TunnelHelperAuthorizationStatus {
        .enabled
    }
}

private actor AppShellDevice: DeviceSessionPreparing {
    let device: USBDevice
    private var outcomes: [AppShellConnectionOutcome]
    private var sessionState: DeviceSessionState = .disconnected
    private var setLocationCalls = 0

    init(
        device: USBDevice,
        outcomes: [AppShellConnectionOutcome]
    ) {
        self.device = device
        self.outcomes = outcomes
    }

    func connect(
        selectedDeviceID: DeviceID?
    ) async throws -> PreparedDeviceSession {
        guard !outcomes.isEmpty else {
            sessionState = .disconnected
            throw DeviceLocationError.noUSBDevice
        }
        switch outcomes.removeFirst() {
        case .ready(let rawGeneration):
            let session = PreparedDeviceSession(
                device: device,
                generation: DeviceSessionGeneration(
                    rawValue: rawGeneration
                )
            )
            sessionState = .ready(session)
            return session
        case .failure(let failure):
            sessionState = .disconnected
            throw failure
        }
    }

    func currentSessionState() async -> DeviceSessionState {
        sessionState
    }

    func discoverUSBDevices() async throws -> [USBDevice] {
        [device]
    }

    func prepare(deviceID: DeviceID) async throws -> PreparedDeviceSession {
        try await connect(selectedDeviceID: deviceID)
    }

    func setLocation(
        _ coordinate: DeviceCoordinate,
        context: DeviceMutationContext
    ) async throws {
        setLocationCalls += 1
    }

    func clearLocation(context: DeviceCleanupContext) async throws {}
    func shutdown(generation: DeviceSessionGeneration) async {}
    func teardownForQuit() async throws {}

    func setLocationCallCount() -> Int {
        setLocationCalls
    }
}
