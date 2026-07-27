import SwiftUI

struct ContentView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        VStack(spacing: 0) {
            if let setupStore = appDelegate.setupStore {
                DeviceSetupContentView(store: setupStore)
            } else if let configurationFailure = appDelegate.configurationFailure {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                    Text("無法建立裝置支援環境")
                        .font(.title2)
                    Text(configurationFailure)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("正在檢查裝置支援環境…")
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .alert(
            appDelegate.riskNoticeStore.firstUseNotice.title,
            isPresented: Binding(
                get: {
                    appDelegate.riskNoticeStore
                        .needsFirstUseAcknowledgement
                },
                set: { _ in }
            )
        ) {
            Button(
                appDelegate.riskNoticeStore
                    .firstUseNotice.confirmationTitle
            ) {
                appDelegate.riskNoticeStore.acknowledgeFirstUse()
            }
        } message: {
            Text(appDelegate.riskNoticeStore.firstUseNotice.message)
        }
    }
}

struct DeviceSetupContentView: View {
    @ObservedObject var store: DeviceSetupStore

    var body: some View {
        VStack(spacing: 0) {
            DeviceSetupView(store: store)
            Divider()
            LocationMapView(
                simulationStore: store.simulationStore
            )
        }
    }
}

private struct DeviceSetupView: View {
    @ObservedObject var store: DeviceSetupStore

    var body: some View {
        HStack(spacing: 12) {
            status
            Spacer()
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var status: some View {
        switch store.state {
        case .idle, .checkingRuntime:
            ProgressView("正在檢查 pymobiledevice3…")
        case .runtimeInstallationRequired:
            Label("需要安裝 App 專用裝置支援", systemImage: "shippingbox")
        case .pythonUnavailable(let version):
            Label(
                "找不到 Python \(version)+；請先從 python.org 或 Homebrew 安裝 Python。",
                systemImage: "exclamationmark.triangle"
            )
        case .incompleteRuntime:
            Label("App 專用環境不完整，可安全重試安裝。", systemImage: "arrow.clockwise")
        case .installing(let progress):
            ProgressView(installProgressText(progress))
        case .helperApprovalRequired:
            Label("需要管理員核准 USB tunnel helper", systemImage: "lock.shield")
        case .helperRequiresSystemApproval:
            Label(
                "請到「系統設定 → 一般 → 登入項目與延伸功能」允許 helper。",
                systemImage: "gearshape"
            )
        case .discoveringDevices:
            ProgressView("正在偵測 USB iPhone…")
        case .noUSBDevice:
            Label(
                "找不到 USB iPhone；請解鎖手機、確認資料線並信任這台 Mac。",
                systemImage: "cable.connector"
            )
        case .selectionRequired(let devices):
            Label("偵測到 \(devices.count) 台 iPhone，請選擇一台。", systemImage: "iphone.gen3")
        case .unsupported(let device):
            Label(
                "\(device.name)・iOS \(versionText(device)) 不支援；需要 iOS 17+。",
                systemImage: "iphone.slash"
            )
        case .preparing(let device):
            ProgressView(
                device.map { "正在準備 \($0.name)…" } ?? "正在準備裝置…"
            )
        case .ready(let session):
            Label(
                "\(session.device.name)・iOS \(versionText(session.device)) 已就緒",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .failed(let failure):
            Label(failureText(failure), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .configurationFailure(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch store.state {
        case .runtimeInstallationRequired, .incompleteRuntime:
            Button("安裝裝置支援") {
                Task { await store.installRuntime() }
            }
        case .installing:
            Button("取消") {
                Task { await store.cancelRuntimeInstallation() }
            }
        case .helperApprovalRequired:
            Button("核准 Helper") {
                Task { await store.requestHelperApproval() }
            }
        case .helperRequiresSystemApproval, .noUSBDevice,
             .failed, .configurationFailure:
            Button("重試") {
                Task { await store.retry() }
            }
        case .selectionRequired(let devices):
            Menu("選擇 iPhone") {
                ForEach(devices, id: \.id) { device in
                    Button(
                        "\(device.name)・iOS \(versionText(device))"
                    ) {
                        Task { await store.selectDevice(device.id) }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private func installProgressText(
        _ progress: RuntimeInstallProgress
    ) -> String {
        switch progress {
        case .checkingPython:
            "正在檢查 Python…"
        case .creatingEnvironment:
            "正在建立 App 專用環境…"
        case .installingPinnedPackage:
            "正在安裝固定版本 pymobiledevice3…"
        case .verifyingCapabilities:
            "正在驗證裝置功能…"
        }
    }

    private func versionText(_ device: USBDevice) -> String {
        let version = device.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private func failureText(_ failure: DeviceLocationError) -> String {
        let presentation = DeviceFailurePresentation.make(for: failure)
        return "\(presentation.title)：\(presentation.message)"
    }
}
