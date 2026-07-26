import AppKit
import SwiftUI

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
    @Published private(set) var setupStore: DeviceSetupStore?
    @Published private(set) var configurationFailure: String?
    private var terminationRequestInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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
