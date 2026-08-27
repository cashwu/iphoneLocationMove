import AppKit
import Darwin
import SwiftUI

#if DEBUG
enum PrivilegedHelperAcceptanceCase: String, CaseIterable, Codable, Sendable {
    case positiveStart = "positive-start"
    case pendingDuplicate = "pending-duplicate"
    case lostReplyRetry = "lost-reply-retry"
    case endpointTimeout = "endpoint-timeout"
    case connectionInvalidation = "connection-invalidation"
    case appTermination = "app-termination"
    case startupReconcile = "startup-reconcile"
    case runtimeSealTamper = "runtime-seal-tamper"

    static func parse(_ arguments: [String]) -> Self? {
        guard arguments.count == 3,
              arguments[1] == "--privileged-helper-acceptance-case"
        else {
            return nil
        }
        return Self(rawValue: arguments[2])
    }

    func acceptsExpectedFailure(_ error: Error) -> Bool {
        guard let error = error as? DeviceLocationError else {
            return false
        }
        switch (self, error) {
        case (.endpointTimeout, .timeout):
            return true
        case let (.runtimeSealTamper, .tunnelFailure(detail)):
            let normalizedDetail = detail.lowercased()
            return normalizedDetail.contains("runtime")
                || normalizedDetail.contains("seal")
        default:
            return false
        }
    }
}

private struct PrivilegedHelperAcceptanceResult: Codable, Sendable {
    let acceptanceCase: PrivilegedHelperAcceptanceCase
    let passed: Bool
    let leaseID: String?
    let errorCode: String?
    let detail: String

    enum CodingKeys: String, CodingKey {
        case acceptanceCase = "case"
        case passed
        case leaseID
        case errorCode
        case detail
    }
}

private enum PrivilegedHelperAcceptanceRunner {
    static func run(
        _ acceptanceCase: PrivilegedHelperAcceptanceCase
    ) async -> PrivilegedHelperAcceptanceResult {
        do {
            let client = LiveTunnelClient()
            if acceptanceCase == .startupReconcile {
                try await client.reconcile()
                return success(acceptanceCase, detail: "reconcile completed")
            }

            let deviceID: DeviceID
            if acceptanceCase == .endpointTimeout || acceptanceCase == .runtimeSealTamper {
                deviceID = try DeviceID("00000000-0000000000000000")
            } else {
                let adapter = try PymobiledeviceAdapter.live()
                let devices = try await adapter.discoverUSBDevices()
                guard devices.count == 1, let device = devices.first else {
                    return failure(
                        acceptanceCase,
                        code: "device-selection",
                        detail: "Acceptance requires exactly one USB iPhone."
                    )
                }
                deviceID = device.id
            }

            switch acceptanceCase {
            case .positiveStart:
                try await client.reconcile()
                let lease = try await client.startTunnel(
                    deviceID: deviceID,
                    idempotencyKey: UUID()
                )
                let status = try await client.status(lease)
                try await client.stopTunnel(lease)
                return success(
                    acceptanceCase,
                    leaseID: lease.id.rawValue.uuidString,
                    detail: "start/status/stop completed with state \(status.state.rawValue)"
                )

            case .pendingDuplicate:
                try await client.reconcile()
                let key = UUID()
                async let first = client.startTunnel(
                    deviceID: deviceID,
                    idempotencyKey: key
                )
                async let second = client.startTunnel(
                    deviceID: deviceID,
                    idempotencyKey: key
                )
                let (firstLease, secondLease) = try await (first, second)
                guard firstLease == secondLease else {
                    try? await client.stopTunnel(firstLease)
                    try? await client.stopTunnel(secondLease)
                    return failure(
                        acceptanceCase,
                        code: "lease-mismatch",
                        detail: "Concurrent starts returned different leases."
                    )
                }
                try await client.stopTunnel(firstLease)
                return success(
                    acceptanceCase,
                    leaseID: firstLease.id.rawValue.uuidString,
                    detail: "concurrent starts shared one lease"
                )

            case .lostReplyRetry:
                try await client.reconcile()
                let key = UUID()
                let firstLease = try await client.startTunnel(
                    deviceID: deviceID,
                    idempotencyKey: key
                )
                let retryLease = try await client.startTunnel(
                    deviceID: deviceID,
                    idempotencyKey: key
                )
                guard firstLease == retryLease else {
                    try? await client.stopTunnel(firstLease)
                    try? await client.stopTunnel(retryLease)
                    return failure(
                        acceptanceCase,
                        code: "lease-mismatch",
                        detail: "Same-key retry returned a different lease."
                    )
                }
                try await client.stopTunnel(firstLease)
                return success(
                    acceptanceCase,
                    leaseID: firstLease.id.rawValue.uuidString,
                    detail: "same-key retry recovered the original lease"
                )

            case .connectionInvalidation:
                try await client.reconcile()
                let lease = try await client.startTunnel(
                    deviceID: deviceID,
                    idempotencyKey: UUID()
                )
                await client.invalidateConnectionForAcceptance()
                return success(
                    acceptanceCase,
                    leaseID: lease.id.rawValue.uuidString,
                    detail: "owning XPC connection invalidated; external fixture verifies cleanup"
                )

            case .appTermination:
                try await client.reconcile()
                let lease = try await client.startTunnel(
                    deviceID: deviceID,
                    idempotencyKey: UUID()
                )
                return success(
                    acceptanceCase,
                    leaseID: lease.id.rawValue.uuidString,
                    detail: "runner exits without stop; external fixture verifies owner-death cleanup"
                )

            case .endpointTimeout, .runtimeSealTamper:
                do {
                    let lease = try await client.startTunnel(
                        deviceID: deviceID,
                        idempotencyKey: UUID()
                    )
                    try? await client.stopTunnel(lease)
                    return failure(
                        acceptanceCase,
                        code: "unexpected-success",
                        detail: "The fixed negative fixture unexpectedly started a tunnel."
                    )
                } catch {
                    return expectedFailure(acceptanceCase, error: error)
                }

            case .startupReconcile:
                preconditionFailure("Handled before device discovery")
            }
        } catch {
            return failure(
                acceptanceCase,
                code: errorCode(error),
                detail: String(describing: error)
            )
        }
    }

    private static func success(
        _ acceptanceCase: PrivilegedHelperAcceptanceCase,
        leaseID: String? = nil,
        detail: String
    ) -> PrivilegedHelperAcceptanceResult {
        PrivilegedHelperAcceptanceResult(
            acceptanceCase: acceptanceCase,
            passed: true,
            leaseID: leaseID,
            errorCode: nil,
            detail: detail
        )
    }

    private static func expectedFailure(
        _ acceptanceCase: PrivilegedHelperAcceptanceCase,
        error: Error
    ) -> PrivilegedHelperAcceptanceResult {
        PrivilegedHelperAcceptanceResult(
            acceptanceCase: acceptanceCase,
            passed: acceptanceCase.acceptsExpectedFailure(error),
            leaseID: nil,
            errorCode: errorCode(error),
            detail: String(describing: error)
        )
    }

    private static func failure(
        _ acceptanceCase: PrivilegedHelperAcceptanceCase,
        code: String,
        detail: String
    ) -> PrivilegedHelperAcceptanceResult {
        PrivilegedHelperAcceptanceResult(
            acceptanceCase: acceptanceCase,
            passed: false,
            leaseID: nil,
            errorCode: code,
            detail: detail
        )
    }

    private static func errorCode(_ error: Error) -> String {
        guard let error = error as? DeviceLocationError else {
            return "unexpected-error"
        }
        switch error {
        case .authorizationDenied:
            return "authorization-denied"
        case .timeout:
            return "timeout"
        case .tunnelFailure:
            return "tunnel-failure"
        case .noUSBDevice:
            return "no-usb-device"
        case .selectionRequired:
            return "selection-required"
        default:
            return "device-location-error"
        }
    }
}
#endif

@main
struct iPhoneLocationMoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: AppWindow.mainID) {
            ContentView(appDelegate: appDelegate)
                .environmentObject(appDelegate.lifecycleCoordinator)
        }
        .commands {
            MainWindowCommands()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let lifecycleCoordinator = AppLifecycleCoordinator()
    let sleepObserver = SystemSleepObserver()
    let riskNoticeStore = RiskNoticeStore()
    let favoritesStore = FavoritesStore()
    let macLocationCoordinator = MacLocationCoordinator()
    @Published private(set) var setupStore: DeviceSetupStore?
    @Published private(set) var configurationFailure: String?
    private var terminationRequestInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if let acceptanceCase = PrivilegedHelperAcceptanceCase.parse(CommandLine.arguments) {
            Task {
                let result = await PrivilegedHelperAcceptanceRunner.run(acceptanceCase)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = (try? encoder.encode(result)) ?? Data()
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([0x0A]))
                fflush(stdout)
                exit(result.passed ? EXIT_SUCCESS : EXIT_FAILURE)
            }
            return
        }
#endif
        sleepObserver.start()
        do {
            let setupStore = try DeviceSetupStore.live(
                lifecycleCoordinator: lifecycleCoordinator,
                sleepObserver: sleepObserver
            )
            self.setupStore = setupStore
            Task {
                await setupStore.start()
            }
        } catch {
            configurationFailure = error.localizedDescription
        }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard !terminationRequestInProgress else {
            return .terminateLater
        }
        terminationRequestInProgress = true
        Task { @MainActor [weak self] in
            await self?.resolveTerminationRequest()
        }
        return .terminateLater
    }

    private func resolveTerminationRequest() async {
        var decision = await lifecycleCoordinator.requestQuit()
        if decision == .awaitingConfirmation {
            guard confirmActiveSimulationQuit() else {
                lifecycleCoordinator.cancelQuit()
                finishTerminationRequest(shouldTerminate: false)
                return
            }
            decision = await lifecycleCoordinator.confirmQuit()
        }

        while decision == .keepRunning {
            switch cleanupFailureAction() {
            case .retry:
                decision = await lifecycleCoordinator.confirmQuit()
            case .force:
                lifecycleCoordinator.requestForceQuit()
                guard confirmUnsafeForceQuit() else {
                    lifecycleCoordinator.cancelQuit()
                    finishTerminationRequest(shouldTerminate: false)
                    return
                }
                decision = lifecycleCoordinator.confirmForceQuit()
            case .cancel:
                lifecycleCoordinator.cancelQuit()
                finishTerminationRequest(shouldTerminate: false)
                return
            }
        }

        finishTerminationRequest(shouldTerminate: decision == .terminate)
    }

    private func confirmActiveSimulationQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = "停止模擬並退出？"
        alert.informativeText =
            "App 會先停止位置更新、清除模擬定位，再關閉 DVT 與 tunnel。"
        alert.addButton(withTitle: "停止並退出")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private enum CleanupFailureAction {
        case retry
        case force
        case cancel
    }

    private func cleanupFailureAction() -> CleanupFailureAction {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "無法安全完成退出清理"
        alert.informativeText =
            "手機可能仍維持模擬位置。你可以重試，或進一步選擇強制退出。"
        alert.addButton(withTitle: "重試")
        alert.addButton(withTitle: "強制退出…")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .retry
        case .alertSecondButtonReturn:
            return .force
        default:
            return .cancel
        }
    }

    private func confirmUnsafeForceQuit() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "確定強制退出？"
        alert.informativeText =
            "這不代表已恢復真實定位；iPhone 可能仍保留模擬座標。"
        alert.addButton(withTitle: "仍要強制退出")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func finishTerminationRequest(shouldTerminate: Bool) {
        terminationRequestInProgress = false
        NSApplication.shared.reply(toApplicationShouldTerminate: shouldTerminate)
    }
}

enum AppWindow {
    static let mainID = "main"
}

private struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("開啟定位控制") {
                openWindow(id: AppWindow.mainID)
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
