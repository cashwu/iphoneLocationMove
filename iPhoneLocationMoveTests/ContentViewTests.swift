import AppKit
import SwiftUI
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class ContentViewTests: XCTestCase {
    func testSetupReadyReplacesDisconnectedControlsInSameHostingView() async throws {
        let store = try makeStore()
        let hostingView = NSHostingView(
            rootView: DeviceSetupContentView(store: store)
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
