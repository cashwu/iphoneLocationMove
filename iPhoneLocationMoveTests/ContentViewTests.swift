import AppKit
import MapKit
import SwiftUI
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class ContentViewTests: XCTestCase {
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
        simulationStore: SimulationStore
    ) -> (NSHostingView<LocationMapView>, NSWindow) {
        let hostingView = NSHostingView(
            rootView: LocationMapView(
                simulationStore: simulationStore,
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
        hostingView.layoutSubtreeIfNeeded()
        return (hostingView, window)
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

private actor ContentViewSimulationScheduler: SimulationScheduling {
    func now() -> TimeInterval {
        0
    }

    func waitForNextTick() async throws {
        try await Task.sleep(for: .seconds(60))
    }
}
