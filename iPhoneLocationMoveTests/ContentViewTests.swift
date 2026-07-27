import AppKit
import MapKit
import SwiftUI
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class ContentViewTests: XCTestCase {
    func testResetConfirmationClearsSearchAndTurnsOffRoundTrip() async throws {
        let model = try configuredRouteModel()
        let (hostingView, window) = makeMapHostingView(
            model: model,
            initialQuery: "保留中的搜尋",
            initialRoundTrip: true
        )
        defer { removeFromWindow(window) }

        let queryField = try XCTUnwrap(
            findTextField(in: hostingView, placeholder: "搜尋地名或地址")
        )
        XCTAssertEqual(queryField.stringValue, "保留中的搜尋")

        let roundTrip = try XCTUnwrap(
            findButton(in: hostingView, identifier: "round-trip-state")
        )
        XCTAssertEqual(roundTrip.state, .on)

        try await confirmReset(in: hostingView) {
            XCTAssertEqual(queryField.stringValue, "保留中的搜尋")
            XCTAssertEqual(roundTrip.state, .on)
            XCTAssertNotNil(model.endpointA)
            XCTAssertNotNil(model.endpointB)
            XCTAssertEqual(model.routeStatus, .routeAvailable)
        }

        XCTAssertEqual(queryField.stringValue, "")
        XCTAssertEqual(roundTrip.state, .off)
        XCTAssertNil(model.endpointA)
        XCTAssertNil(model.endpointB)
        XCTAssertEqual(model.routeStatus, .idle)
    }

    func testResetIsDisabledForEveryBusySimulationState() async throws {
        let startingDevice = ResetTestSimulationDevice()
        await startingDevice.suspendNextSet()
        let startingStore = makeSimulationStore(device: startingDevice)
        let starting = Task {
            await startingStore.confirmPoint(
                try! DeviceCoordinate(latitude: 25, longitude: 121),
                riskAccepted: true
            )
        }
        await startingDevice.waitForSetCount(1)
        try assertResetDisabled(simulationStore: startingStore)
        await startingDevice.resumeSet()
        await starting.value

        let replacingDevice = ResetTestSimulationDevice()
        let replacingStore = makeSimulationStore(device: replacingDevice)
        try await replacingStore.startRoute(
            preview: routePreview(),
            speedKilometersPerHour: 7,
            roundTrip: false,
            riskAccepted: true
        )
        await replacingDevice.suspendNextSet()
        try replacingStore.tick(at: 1)
        await replacingDevice.waitForSetCount(2)
        let replacing = Task {
            await replacingStore.confirmPoint(
                try! DeviceCoordinate(latitude: 24, longitude: 120),
                riskAccepted: true
            )
        }
        await waitForState(replacingStore) {
            if case .replacing = $0 {
                return true
            }
            return false
        }
        try assertResetDisabled(simulationStore: replacingStore)
        await replacingDevice.resumeSet()
        await replacing.value

        let stoppingDevice = ResetTestSimulationDevice()
        let stoppingStore = makeSimulationStore(device: stoppingDevice)
        await stoppingStore.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        await stoppingDevice.suspendNextClear()
        let stopping = Task { await stoppingStore.stop() }
        await stoppingDevice.waitForClearCount(1)
        try assertResetDisabled(simulationStore: stoppingStore)
        await stoppingDevice.resumeClear()
        await stopping.value
    }

    func testResetStopsOnlyWhenSimulationOwnsCleanup() async throws {
        let idleDevice = ResetTestSimulationDevice()
        let idleStore = makeSimulationStore(device: idleDevice)
        let (idleView, idleWindow) = makeMapHostingView(
            simulationStore: idleStore
        )
        defer { removeFromWindow(idleWindow) }
        try await confirmReset(in: idleView)
        let idleClearCount = await idleDevice.recordedClearCallCount()
        XCTAssertEqual(idleClearCount, 0)

        let activeDevice = ResetTestSimulationDevice()
        let activeStore = makeSimulationStore(device: activeDevice)
        await activeStore.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        let (activeView, activeWindow) = makeMapHostingView(
            simulationStore: activeStore
        )
        defer { removeFromWindow(activeWindow) }
        try await confirmReset(in: activeView)
        await activeDevice.waitForClearCount(1)

        let activeClearCount = await activeDevice.recordedClearCallCount()
        XCTAssertEqual(activeClearCount, 1)
        XCTAssertEqual(activeStore.state, .idle)
    }

    func testResetClearFailureKeepsRetryAndResetWorkspace() async throws {
        let device = ResetTestSimulationDevice()
        let store = makeSimulationStore(device: device)
        await store.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        await device.failNextClear(.clearFailed("reset-test"))
        let model = try configuredRouteModel()
        let (hostingView, window) = makeMapHostingView(
            simulationStore: store,
            model: model
        )
        defer { removeFromWindow(window) }

        try await confirmReset(in: hostingView)
        await device.waitForClearCount(1)
        await waitForViewUpdate(hostingView)

        guard case .stopping(_, let failure?) = store.state else {
            return XCTFail("Expected cleanup failure ownership")
        }
        XCTAssertEqual(failure, .clearFailed("reset-test"))
        let showsFailure = await waitForIdentifier(
            "simulation-cleanup-failure",
            in: hostingView
        )
        let showsRetry = await waitForIdentifier(
            "simulation-cleanup-retry",
            in: hostingView
        )
        XCTAssertTrue(showsFailure)
        XCTAssertTrue(showsRetry)
        XCTAssertNil(model.endpointA)
        XCTAssertNil(model.endpointB)
        XCTAssertEqual(model.routeStatus, .idle)
    }

    func testConfirmedRouteMarkerUpdatesSameAnnotationInSameHostingView() async throws {
        let harness = try ContentViewSimulationHarness()
        let (hostingView, window) = makeMapHostingView(simulationStore: harness.store)
        defer { removeFromWindow(window) }

        try await harness.store.startRoute(
            preview: routePreview(),
            speedKilometersPerHour: 7,
            roundTrip: false,
            riskAccepted: true
        )

        let mapView = try XCTUnwrap(findMapView(in: hostingView))
        let initialAnnotation = try await waitForRouteMarker(in: mapView)
        XCTAssertEqual(initialAnnotation.coordinate.latitude, 25, accuracy: 0.000_001)
        XCTAssertEqual(initialAnnotation.coordinate.longitude, 121, accuracy: 0.000_001)
        let initialLongitude = initialAnnotation.coordinate.longitude

        try harness.store.tick(at: 1)
        await harness.device.waitForSetCount(2)
        let updatedAnnotation = try await waitForRouteMarker(
            in: mapView,
            longitudeDifferentFrom: initialLongitude
        )

        XCTAssertTrue(initialAnnotation === updatedAnnotation)
        XCTAssertEqual(updatedAnnotation.coordinate.latitude, 25, accuracy: 0.000_001)
        XCTAssertGreaterThan(updatedAnnotation.coordinate.longitude, 121)
        XCTAssertLessThan(updatedAnnotation.coordinate.longitude, 121.001)
    }

    func testPositionUnknownRemovesConfirmedRouteMarkerFromSameHostingView() async throws {
        let harness = try ContentViewSimulationHarness()
        let (hostingView, window) = makeMapHostingView(simulationStore: harness.store)
        defer { removeFromWindow(window) }

        try await harness.store.startRoute(
            preview: routePreview(),
            speedKilometersPerHour: 7,
            roundTrip: false,
            riskAccepted: true
        )

        let mapView = try XCTUnwrap(findMapView(in: hostingView))
        let initialAnnotation = try await waitForRouteMarker(in: mapView)

        harness.store.handleDeviceInterruption(
            DeviceInterruption(
                reason: .transportFailure,
                positionKnowledge: .unknown
            )
        )

        let markerWasRemoved = await waitForRouteMarkerRemoval(
            initialAnnotation,
            from: mapView
        )
        XCTAssertTrue(markerWasRemoved)
    }

    func testClearSuccessRemovesConfirmedRouteMarkerFromSameHostingView() async throws {
        let harness = try ContentViewSimulationHarness()
        let (hostingView, window) = makeMapHostingView(simulationStore: harness.store)
        defer { removeFromWindow(window) }

        try await harness.store.startRoute(
            preview: routePreview(),
            speedKilometersPerHour: 7,
            roundTrip: false,
            riskAccepted: true
        )

        let mapView = try XCTUnwrap(findMapView(in: hostingView))
        let initialAnnotation = try await waitForRouteMarker(in: mapView)

        await harness.store.stop()

        let markerWasRemoved = await waitForRouteMarkerRemoval(
            initialAnnotation,
            from: mapView
        )
        XCTAssertTrue(markerWasRemoved)
    }

    func testSetupReadyReplacesDisconnectedControlsInSameHostingView() async throws {
        let store = try makeStore()
        let hostingView = NSHostingView(
            rootView: LocationWorkspaceView(
                store: store,
                macLocationCoordinator: MacLocationCoordinator(
                    provider: ContentViewMacLocationProvider()
                )
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
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let initiallyDisconnected = await waitForIdentifier(
            "simulation-controls-disconnected",
            in: hostingView
        )
        XCTAssertTrue(initiallyDisconnected)
        XCTAssertFalse(
            hasIdentifier(
                "simulation-controls-connected",
                in: hostingView
            )
        )

        await store.start()

        let eventuallyConnected = await waitForIdentifier(
            "simulation-controls-connected",
            in: hostingView
        )
        XCTAssertTrue(eventuallyConnected)
        XCTAssertFalse(
            hasIdentifier(
                "simulation-controls-disconnected",
                in: hostingView
            )
        )
    }

    private func makeMapHostingView(
        simulationStore: SimulationStore? = nil,
        model: LocationMapModel = LocationMapModel(),
        initialQuery: String = "",
        initialRoundTrip: Bool = false
    ) -> (NSHostingView<LocationMapView>, NSWindow) {
        let hostingView = NSHostingView(
            rootView: LocationMapView(
                simulationStore: simulationStore,
                macLocationCoordinator: MacLocationCoordinator(
                    provider: ContentViewMacLocationProvider()
                ),
                model: model,
                initialQuery: initialQuery,
                initialRoundTrip: initialRoundTrip
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
        hostingView.layoutSubtreeIfNeeded()
        return (hostingView, window)
    }

    private func configuredRouteModel() throws -> LocationMapModel {
        let model = LocationMapModel()
        try model.selectMapCoordinate(
            MapCoordinate(latitude: 25.03, longitude: 121.56)
        )
        try model.assignPreview(to: .a)
        try model.selectMapCoordinate(
            MapCoordinate(latitude: 25.04, longitude: 121.57)
        )
        try model.assignPreview(to: .b)
        let request = try model.beginDirections()
        _ = try model.receiveDirections(
            .routeAvailable(
                [
                    try MapCoordinate(latitude: 25.03, longitude: 121.56),
                    try MapCoordinate(latitude: 25.04, longitude: 121.57),
                ],
                distance: 900
            ),
            for: request
        )
        return model
    }

    private func makeSimulationStore(
        device: ResetTestSimulationDevice
    ) -> SimulationStore {
        SimulationStore(
            device: device,
            generation: DeviceSessionGeneration(rawValue: 1),
            scheduler: ContentViewSimulationScheduler()
        )
    }

    private func assertResetDisabled(
        simulationStore: SimulationStore
    ) throws {
        let (hostingView, window) = makeMapHostingView(
            simulationStore: simulationStore
        )
        defer { removeFromWindow(window) }
        let reset = try XCTUnwrap(
            findButton(in: hostingView, identifier: "workspace-reset-button")
        )
        XCTAssertFalse(reset.isEnabled)
    }

    private func confirmReset(
        in hostingView: NSHostingView<LocationMapView>,
        beforeConfirmation: () throws -> Void = {}
    ) async throws {
        let reset = try XCTUnwrap(
            findButton(in: hostingView, identifier: "workspace-reset-button")
        )
        reset.performClick(nil)
        await waitForViewUpdate(hostingView)

        try beforeConfirmation()
        let confirm = try XCTUnwrap(
            findButton(
                in: hostingView,
                identifier: "workspace-reset-confirmation-action"
            )
        )
        XCTAssertTrue(confirm.isEnabled)
        confirm.performClick(nil)
        await waitForViewUpdate(hostingView)
    }

    private func waitForViewUpdate(_ hostingView: NSView) async {
        for _ in 0 ..< 10 {
            hostingView.window?.displayIfNeeded()
            await Task.yield()
        }
    }

    private func waitForState(
        _ store: SimulationStore,
        matching predicate: (SimulationStoreState) -> Bool
    ) async {
        while !predicate(store.state) {
            await Task.yield()
        }
    }

    private func findButton(
        in root: NSView,
        identifier: String
    ) -> NSButton? {
        if let button = root as? NSButton,
           button.accessibilityIdentifier() == identifier
        {
            return button
        }
        return root.subviews.lazy.compactMap {
            self.findButton(in: $0, identifier: identifier)
        }.first
    }

    private func findTextField(
        in root: NSView,
        placeholder: String
    ) -> NSTextField? {
        if let field = root as? NSTextField,
           field.placeholderString == placeholder
        {
            return field
        }
        return root.subviews.lazy.compactMap {
            self.findTextField(in: $0, placeholder: placeholder)
        }.first
    }

    private func removeFromWindow(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }

    private func routePreview() throws -> RoutePreview {
        try RoutePreview(points: [
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 25, longitude: 121),
                cumulativeDistance: 0
            ),
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 25, longitude: 121.001),
                cumulativeDistance: 100
            ),
        ])
    }

    private func findMapView(in root: NSView) -> MKMapView? {
        if let mapView = root as? MKMapView {
            return mapView
        }
        return root.subviews.lazy.compactMap(findMapView).first
    }

    private func waitForRouteMarker(
        in mapView: MKMapView,
        longitudeDifferentFrom previousLongitude: CLLocationDegrees? = nil
    ) async throws -> MKAnnotation {
        for _ in 0 ..< 100 {
            mapView.window?.displayIfNeeded()
            if let annotation = routeMarker(in: mapView),
               previousLongitude.map({
                   abs(annotation.coordinate.longitude - $0) > 0.000_000_1
               }) ?? true
            {
                return annotation
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ContentViewTestError.routeMarkerNotFound
    }

    private func waitForRouteMarkerRemoval(
        _ annotation: MKAnnotation,
        from mapView: MKMapView
    ) async -> Bool {
        for _ in 0 ..< 100 {
            mapView.window?.displayIfNeeded()
            if routeMarker(in: mapView) == nil,
               !mapView.annotations.contains(where: { $0 === annotation })
            {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func routeMarker(in mapView: MKMapView) -> MKAnnotation? {
        mapView.annotations.first { annotation in
            mapView.view(for: annotation)?
                .accessibilityIdentifier() == "iphone-route-marker"
        }
    }

    private func makeStore() throws -> DeviceSetupStore {
        let device = try USBDevice(
            id: DeviceID("content-view-device"),
            name: "iPhone",
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 17,
                minorVersion: 0,
                patchVersion: 0
            )
        )
        return DeviceSetupStore(
            runtimeManager: ContentViewRuntime(),
            device: ContentViewDevice(device: device),
            helperAuthorizer: ContentViewAuthorizer(),
            lifecycleCoordinator: AppLifecycleCoordinator(),
            sleepObserver: SystemSleepObserver(
                notificationCenter: NotificationCenter(),
                willSleepNotification: Notification.Name("unused-sleep"),
                didWakeNotification: Notification.Name("unused-wake")
            )
        )
    }

    private func waitForIdentifier(
        _ identifier: String,
        in root: NSView
    ) async -> Bool {
        for _ in 0 ..< 100 {
            if hasIdentifier(identifier, in: root) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func hasIdentifier(
        _ identifier: String,
        in root: NSView
    ) -> Bool {
        if containsViewIdentifier(identifier, in: root) {
            return true
        }
        return NSAccessibility.unignoredChildrenForOnlyChild(from: root).contains {
            containsIdentifier(identifier, in: $0)
        }
    }

    private func containsViewIdentifier(
        _ identifier: String,
        in view: NSView
    ) -> Bool {
        view.accessibilityIdentifier() == identifier
            || view.subviews.contains {
                containsViewIdentifier(identifier, in: $0)
            }
    }

    private func containsIdentifier(
        _ identifier: String,
        in element: Any
    ) -> Bool {
        if let view = element as? NSView {
            if view.accessibilityIdentifier() == identifier {
                return true
            }
            return (view.accessibilityChildren() ?? []).contains {
                containsIdentifier(identifier, in: $0)
            }
        }
        if let accessibilityElement = element as? NSAccessibilityElement {
            if accessibilityElement.accessibilityIdentifier() == identifier {
                return true
            }
            return (accessibilityElement.accessibilityChildren() ?? []).contains {
                containsIdentifier(identifier, in: $0)
            }
        }
        if let accessibilityElement =
            element as? NSAccessibilityElementProtocol,
           accessibilityElement.accessibilityIdentifier?() == identifier {
            return true
        }
        return false
    }
}

private enum ContentViewTestError: Error {
    case routeMarkerNotFound
}

@MainActor
private struct ContentViewMacLocationProvider: MacLocationProviding {
    func requestCurrentLocation() async throws -> MapCoordinate {
        throw MacLocationClientError.locationServicesDisabled
    }
}

private actor ContentViewRuntime: DeviceRuntimeManaging {
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

private actor ContentViewAuthorizer: TunnelHelperAuthorizing {
    func inspect() async -> TunnelHelperAuthorizationStatus {
        .enabled
    }

    func requestApproval() async -> TunnelHelperAuthorizationStatus {
        .enabled
    }
}

private actor ContentViewDevice: DeviceSessionPreparing {
    let device: USBDevice
    private var state: DeviceSessionState = .disconnected

    init(device: USBDevice) {
        self.device = device
    }

    func connect(
        selectedDeviceID: DeviceID?
    ) async throws -> PreparedDeviceSession {
        let session = PreparedDeviceSession(
            device: device,
            generation: DeviceSessionGeneration(rawValue: 1)
        )
        state = .ready(session)
        return session
    }

    func currentSessionState() async -> DeviceSessionState {
        state
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
    ) async throws {}

    func clearLocation(context: DeviceCleanupContext) async throws {}
    func shutdown(generation: DeviceSessionGeneration) async {}
    func teardownForQuit() async throws {}
}

@MainActor
private struct ContentViewSimulationHarness {
    let device = ContentViewSimulationDevice()
    let store: SimulationStore

    init() throws {
        store = SimulationStore(
            device: device,
            generation: DeviceSessionGeneration(rawValue: 1),
            scheduler: ContentViewSimulationScheduler()
        )
    }
}

private actor ContentViewSimulationDevice: DeviceLocationClient {
    private var setCallCount = 0

    func waitForSetCount(_ count: Int) async {
        while setCallCount < count {
            await Task.yield()
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
        setCallCount += 1
    }

    func clearLocation(context: DeviceCleanupContext) async throws {}
    func shutdown(generation: DeviceSessionGeneration) async {}
}

private actor ResetTestSimulationDevice: DeviceLocationClient {
    private var setCallCount = 0
    private var clearCallCount = 0
    private var shouldSuspendSet = false
    private var shouldSuspendClear = false
    private var pendingSet: CheckedContinuation<Void, Never>?
    private var pendingClear: CheckedContinuation<Void, Never>?
    private var nextClearFailure: DeviceLocationError?

    func suspendNextSet() {
        shouldSuspendSet = true
    }

    func suspendNextClear() {
        shouldSuspendClear = true
    }

    func failNextClear(_ failure: DeviceLocationError) {
        nextClearFailure = failure
    }

    func resumeSet() {
        pendingSet?.resume()
        pendingSet = nil
    }

    func resumeClear() {
        pendingClear?.resume()
        pendingClear = nil
    }

    func waitForSetCount(_ count: Int) async {
        while setCallCount < count {
            await Task.yield()
        }
    }

    func waitForClearCount(_ count: Int) async {
        while clearCallCount < count {
            await Task.yield()
        }
    }

    func recordedClearCallCount() -> Int {
        clearCallCount
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
        setCallCount += 1
        if shouldSuspendSet {
            shouldSuspendSet = false
            await withCheckedContinuation { continuation in
                pendingSet = continuation
            }
        }
    }

    func clearLocation(context: DeviceCleanupContext) async throws {
        clearCallCount += 1
        if shouldSuspendClear {
            shouldSuspendClear = false
            await withCheckedContinuation { continuation in
                pendingClear = continuation
            }
        }
        if let nextClearFailure {
            self.nextClearFailure = nil
            throw nextClearFailure
        }
    }

    func shutdown(generation: DeviceSessionGeneration) async {}
}

private actor ContentViewSimulationScheduler: SimulationScheduling {
    func now() -> TimeInterval {
        0
    }

    func waitForNextTick() async throws {
        try await Task.sleep(for: .seconds(60))
    }
}
