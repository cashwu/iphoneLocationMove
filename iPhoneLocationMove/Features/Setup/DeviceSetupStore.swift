import Combine
import Foundation
import Security
import ServiceManagement

protocol DeviceRuntimeManaging: Sendable {
    func inspect() async -> RuntimeAvailability
    func install(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async -> RuntimeInstallResult
    func cancelRuntimeInstallation() async
}

protocol DeviceSessionPreparing:
    DeviceLocationClient,
    DeviceSessionQuitTeardown
{
    func connect(
        selectedDeviceID: DeviceID?
    ) async throws -> PreparedDeviceSession
    func currentSessionState() async -> DeviceSessionState
}

enum TunnelHelperAuthorizationStatus: Equatable, Sendable {
    case approvalRequired
    case requiresSystemApproval
    case enabled
    case unavailable(String)
}

protocol TunnelHelperAuthorizing: Sendable {
    func inspect() async -> TunnelHelperAuthorizationStatus
    func requestApproval() async -> TunnelHelperAuthorizationStatus
}

enum DeviceSetupState: Equatable, Sendable {
    case idle
    case checkingRuntime
    case runtimeInstallationRequired
    case pythonUnavailable(minimumVersion: String)
    case incompleteRuntime
    case installing(RuntimeInstallProgress)
    case helperApprovalRequired
    case helperRequiresSystemApproval
    case discoveringDevices
    case noUSBDevice
    case selectionRequired([USBDevice])
    case unsupported(USBDevice)
    case preparing(USBDevice?)
    case ready(PreparedDeviceSession)
    case failed(DeviceLocationError)
    case configurationFailure(String)
}

@MainActor
final class DeviceSetupStore: ObservableObject {
    @Published private(set) var state: DeviceSetupState = .idle
    @Published private(set) var simulationStore: SimulationStore?
    @Published private(set) var isInstalling = false

    private let runtimeManager: any DeviceRuntimeManaging
    private let device: any DeviceSessionPreparing
    private let helperAuthorizer: any TunnelHelperAuthorizing
    private let lifecycleCoordinator: AppLifecycleCoordinator
    private let sleepObserver: SystemSleepObserver

    init(
        runtimeManager: any DeviceRuntimeManaging,
        device: any DeviceSessionPreparing,
        helperAuthorizer: any TunnelHelperAuthorizing,
        lifecycleCoordinator: AppLifecycleCoordinator,
        sleepObserver: SystemSleepObserver
    ) {
        self.runtimeManager = runtimeManager
        self.device = device
        self.helperAuthorizer = helperAuthorizer
        self.lifecycleCoordinator = lifecycleCoordinator
        self.sleepObserver = sleepObserver
    }

    static func live(
        lifecycleCoordinator: AppLifecycleCoordinator,
        sleepObserver: SystemSleepObserver
    ) throws -> DeviceSetupStore {
        let configuration = try RuntimeManager.Configuration.live()
        let runtimeManager = RuntimeManager(configuration: configuration)
        let adapter = try PymobiledeviceAdapter.live()
        return DeviceSetupStore(
            runtimeManager: runtimeManager,
            device: adapter,
            helperAuthorizer: SMJobBlessTunnelHelperAuthorizer(),
            lifecycleCoordinator: lifecycleCoordinator,
            sleepObserver: sleepObserver
        )
    }

    func start() async {
        state = .checkingRuntime
        switch await runtimeManager.inspect() {
        case .ready:
            await continueAfterRuntime()
        case .installationRequired:
            state = .runtimeInstallationRequired
        case let .pythonUnavailable(minimumVersion):
            state = .pythonUnavailable(minimumVersion: minimumVersion)
        case .incompleteManagedEnvironment:
            state = .incompleteRuntime
        case let .configurationFailure(failure):
            state = .configurationFailure(String(describing: failure))
        }
    }

    func installRuntime() async {
        guard !isInstalling else {
            return
        }
        isInstalling = true
        state = .installing(.checkingPython)
        let result = await runtimeManager.install { [weak self] progress in
            Task { @MainActor in
                guard let self, self.isInstalling else {
                    return
                }
                self.state = .installing(progress)
            }
        }
        isInstalling = false

        switch result {
        case .ready:
            await continueAfterRuntime()
        case .cancelled:
            state = .runtimeInstallationRequired
        case let .pythonUnavailable(minimumVersion):
            state = .pythonUnavailable(minimumVersion: minimumVersion)
        case let .failed(failure):
            state = .configurationFailure(String(describing: failure))
        }
    }

    func cancelRuntimeInstallation() async {
        guard isInstalling else {
            return
        }
        await runtimeManager.cancelRuntimeInstallation()
    }

    func requestHelperApproval() async {
        switch await helperAuthorizer.requestApproval() {
        case .enabled:
            await connect()
        case .approvalRequired:
            state = .helperApprovalRequired
        case .requiresSystemApproval:
            state = .helperRequiresSystemApproval
        case let .unavailable(message):
            state = .configurationFailure(message)
        }
    }

    func retry() async {
        await start()
    }

    func selectDevice(_ deviceID: DeviceID) async {
        await connect(selectedDeviceID: deviceID)
    }

    private func continueAfterRuntime() async {
        switch await helperAuthorizer.inspect() {
        case .enabled:
            await connect()
        case .approvalRequired:
            state = .helperApprovalRequired
        case .requiresSystemApproval:
            state = .helperRequiresSystemApproval
        case let .unavailable(message):
            state = .configurationFailure(message)
        }
    }

    private func connect(selectedDeviceID: DeviceID? = nil) async {
        state = selectedDeviceID == nil
            ? .discoveringDevices
            : .preparing(nil)
        do {
            let session = try await device.connect(
                selectedDeviceID: selectedDeviceID
            )
            let simulation = SimulationStore(
                device: device,
                generation: session.generation
            )
            simulationStore = simulation
            lifecycleCoordinator.configure(
                simulation: simulation,
                device: device
            )
            sleepObserver.setHandler(simulation)
            state = .ready(session)
        } catch let failure as DeviceLocationError {
            await publishDeviceFailure(failure)
        } catch {
            state = .failed(.transportFailure(error.localizedDescription))
        }
    }

    private func publishDeviceFailure(
        _ failure: DeviceLocationError
    ) async {
        switch failure {
        case .noUSBDevice:
            state = .noUSBDevice
        case .selectionRequired:
            if case let .selectionRequired(devices) =
                await device.currentSessionState() {
                state = .selectionRequired(devices)
            } else {
                state = .failed(failure)
            }
        case .unsupportedDevice:
            if case let .selectionRequired(devices) =
                await device.currentSessionState(),
               let unsupported = devices.first(where: {
                   $0.support != .supported
               }) {
                state = .unsupported(unsupported)
            } else {
                state = .failed(failure)
            }
        default:
            state = .failed(failure)
        }
    }

}

extension RuntimeManager: DeviceRuntimeManaging {
    func cancelRuntimeInstallation() async {
        cancelInstallation()
    }
}

extension PymobiledeviceAdapter: DeviceSessionPreparing {
    func currentSessionState() -> DeviceSessionState {
        state
    }
}

protocol PrivilegedHelperInstalling: Sendable {
    func installed() -> Bool
    func install() throws
}

enum PrivilegedHelperInstallError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case authorizationDenied
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "使用者未核准 privileged helper。"
        case let .installFailed(message):
            message
        }
    }
}

struct SMJobBlessTunnelHelperAuthorizer: TunnelHelperAuthorizing {
    private let installer: any PrivilegedHelperInstalling

    init(
        installer: any PrivilegedHelperInstalling =
            SMJobBlessPrivilegedHelperInstaller()
    ) {
        self.installer = installer
    }

    func inspect() async -> TunnelHelperAuthorizationStatus {
        installer.installed() ? .enabled : .approvalRequired
    }

    func requestApproval() async -> TunnelHelperAuthorizationStatus {
        do {
            try installer.install()
            guard installer.installed() else {
                return .unavailable(
                    "privileged helper 安裝完成，但 launchd 尚未註冊 service。"
                )
            }
            return .enabled
        } catch PrivilegedHelperInstallError.authorizationDenied {
            return .approvalRequired
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }
}

struct SMJobBlessPrivilegedHelperInstaller: PrivilegedHelperInstalling {
    static let label = "com.cash.iPhoneLocationMoveTunnelHelper"
    static let installedHelperURL = URL(
        fileURLWithPath:
            "/Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper"
    )

    func installed() -> Bool {
        guard let job = SMJobCopyDictionary(
            kSMDomainSystemLaunchd,
            Self.label as CFString
        ) else {
            return false
        }
        _ = job.takeRetainedValue()
        let bundledHelperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchServices", isDirectory: true)
            .appendingPathComponent(Self.label)
        return Self.executablesMatch(
            bundledURL: bundledHelperURL,
            installedURL: Self.installedHelperURL
        )
    }

    static func executablesMatch(
        bundledURL: URL,
        installedURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: bundledURL.path),
              fileManager.fileExists(atPath: installedURL.path),
              (try? fileManager.destinationOfSymbolicLink(
                atPath: bundledURL.path
              )) == nil,
              (try? fileManager.destinationOfSymbolicLink(
                atPath: installedURL.path
              )) == nil
        else {
            return false
        }
        return fileManager.contentsEqual(
            atPath: bundledURL.path,
            andPath: installedURL.path
        )
    }

    func install() throws {
        var authorization: AuthorizationRef?
        let createStatus = AuthorizationCreate(
            nil,
            nil,
            [],
            &authorization
        )
        guard createStatus == errAuthorizationSuccess,
              let authorization
        else {
            throw PrivilegedHelperInstallError.installFailed(
                "無法建立管理員授權 session（\(createStatus)）。"
            )
        }
        defer {
            AuthorizationFree(authorization, [])
        }

        let rightName = kSMRightBlessPrivilegedHelper as String
        let authorizationStatus = rightName.withCString { pointer in
            var item = AuthorizationItem(
                name: pointer,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(
                    count: 1,
                    items: itemPointer
                )
                return AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    [
                        .interactionAllowed,
                        .extendRights,
                        .preAuthorize,
                    ],
                    nil
                )
            }
        }
        guard authorizationStatus == errAuthorizationSuccess else {
            if authorizationStatus == errAuthorizationCanceled ||
                authorizationStatus == errAuthorizationDenied
            {
                throw PrivilegedHelperInstallError.authorizationDenied
            }
            throw PrivilegedHelperInstallError.installFailed(
                "管理員授權失敗（\(authorizationStatus)）。"
            )
        }

        var rawError: Unmanaged<CFError>?
        guard SMJobBless(
            kSMDomainSystemLaunchd,
            Self.label as CFString,
            authorization,
            &rawError
        ) else {
            let message = rawError
                .map { CFErrorCopyDescription($0.takeRetainedValue()) as String }
                ?? "SMJobBless 未提供錯誤資訊。"
            throw PrivilegedHelperInstallError.installFailed(message)
        }
    }
}
