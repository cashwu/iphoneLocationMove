import Foundation

struct DeviceCoordinate: Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite,
              (-90 ... 90).contains(latitude),
              longitude.isFinite,
              (-180 ... 180).contains(longitude)
        else {
            throw DeviceLocationError.invalidCoordinate
        }
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct SimulationSessionID: RawRepresentable, Equatable, Hashable, Sendable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct DeviceSessionGeneration: RawRepresentable, Comparable, Hashable, Sendable {
    let rawValue: UInt64

    func advanced() throws -> Self {
        guard rawValue < UInt64.max else {
            throw DeviceLocationError.identityExhausted
        }
        return Self(rawValue: rawValue + 1)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct DeviceRequestID: RawRepresentable, Equatable, Hashable, Sendable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct DeviceID: Equatable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        let isValid = (1 ... 128).contains(rawValue.utf8.count)
            && rawValue.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-"
            }
        guard isValid else {
            throw DeviceLocationError.invalidDeviceID
        }
        self.rawValue = rawValue
    }
}

enum DeviceSupport: Equatable, Sendable {
    case supported
    case unsupported(minimumMajorVersion: Int)
}

struct USBDevice: Equatable, Sendable {
    static let minimumSupportedMajorVersion = 17

    let id: DeviceID
    let name: String
    let operatingSystemVersion: OperatingSystemVersion
    let support: DeviceSupport

    init(
        id: DeviceID,
        name: String,
        operatingSystemVersion: OperatingSystemVersion
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DeviceLocationError.invalidDeviceName
        }
        self.id = id
        self.name = trimmedName
        self.operatingSystemVersion = operatingSystemVersion
        support = operatingSystemVersion.majorVersion >= Self.minimumSupportedMajorVersion
            ? .supported
            : .unsupported(minimumMajorVersion: Self.minimumSupportedMajorVersion)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.operatingSystemVersion.majorVersion
                == rhs.operatingSystemVersion.majorVersion
            && lhs.operatingSystemVersion.minorVersion
                == rhs.operatingSystemVersion.minorVersion
            && lhs.operatingSystemVersion.patchVersion
                == rhs.operatingSystemVersion.patchVersion
            && lhs.support == rhs.support
    }
}

enum DevicePrerequisiteStage: String, CaseIterable, Equatable, Sendable {
    case runtime
    case usbSelection
    case trust
    case developerMode
    case developerDiskImage
    case tunnel
    case dvtHelper
}

enum PositionKnowledge: Equatable, Sendable {
    case known
    case unknown
}

enum InterruptionReason: Equatable, Sendable {
    case deviceMutationFailed
    case timeout
    case transportFailure
    case usbDisconnected
    case authorizationDenied
    case helperExited
    case tunnelEnded
}

struct DeviceInterruption: Equatable, Sendable {
    let reason: InterruptionReason
    let positionKnowledge: PositionKnowledge
}

struct PreparedDeviceSession: Equatable, Sendable {
    let device: USBDevice
    let generation: DeviceSessionGeneration
}

enum DeviceSessionState: Equatable, Sendable {
    case disconnected
    case discovering
    case selectionRequired([USBDevice])
    case preparing(device: USBDevice, stage: DevicePrerequisiteStage)
    case ready(PreparedDeviceSession)
    case interrupted(session: PreparedDeviceSession, interruption: DeviceInterruption)
    case cleanupPending(session: PreparedDeviceSession, failure: DeviceLocationError)
}

struct DeviceMutationContext: Equatable, Sendable {
    let requestID: DeviceRequestID
    let simulationSessionID: SimulationSessionID
    let generation: DeviceSessionGeneration

    init(
        requestID: DeviceRequestID = DeviceRequestID(),
        simulationSessionID: SimulationSessionID,
        generation: DeviceSessionGeneration
    ) {
        self.requestID = requestID
        self.simulationSessionID = simulationSessionID
        self.generation = generation
    }
}

struct DeviceCleanupContext: Equatable, Sendable {
    let requestID: DeviceRequestID
    let generation: DeviceSessionGeneration

    init(
        requestID: DeviceRequestID = DeviceRequestID(),
        generation: DeviceSessionGeneration
    ) {
        self.requestID = requestID
        self.generation = generation
    }
}

enum DeviceLocationError: Error, Equatable, Hashable, Sendable {
    case invalidCoordinate
    case invalidDeviceID
    case invalidDeviceName
    case identityExhausted
    case noUSBDevice
    case selectionRequired
    case deviceNotFound
    case unsupportedDevice
    case prerequisiteFailed(stage: DevicePrerequisiteStage, message: String)
    case timeout
    case usbDisconnected
    case authorizationDenied
    case transportFailure(String)
    case helperFailure(String)
    case tunnelFailure(String)
    case clearFailed(String)
    case positionUnknown
    case responseMismatch
    case staleGeneration
}

enum DeviceRecoveryAction: Equatable, Sendable {
    case retry
    case reconnectUSB
    case approveTrust
    case enableDeveloperMode
    case prepareDeveloperDiskImage
    case approveHelper
    case retryClear
}

struct DeviceFailurePresentation: Equatable, Sendable {
    let title: String
    let message: String
    let recoveryTitle: String
    let recoveryAction: DeviceRecoveryAction

    static func make(
        for failure: DeviceLocationError
    ) -> DeviceFailurePresentation {
        switch failure {
        case .timeout:
            Self(
                title: "裝置回覆逾時",
                message: "位置結果無法確認，已停止後續更新。請檢查 USB 連線後重試。",
                recoveryTitle: "重試",
                recoveryAction: .retry
            )
        case .usbDisconnected:
            Self(
                title: "USB 已中斷",
                message: "目前無法確認 iPhone 上的模擬位置。重新連接同一台 iPhone 後會先 clear。",
                recoveryTitle: "重新連接",
                recoveryAction: .reconnectUSB
            )
        case .authorizationDenied:
            Self(
                title: "授權被拒絕",
                message: "請解鎖 iPhone、信任這台 Mac，並核准需要的系統 helper。",
                recoveryTitle: "完成授權後重試",
                recoveryAction: .approveTrust
            )
        case let .prerequisiteFailed(stage, message):
            prerequisitePresentation(stage: stage, detail: message)
        case let .tunnelFailure(detail):
            Self(
                title: "USB tunnel 失敗",
                message: detail,
                recoveryTitle: "重新核准並重試",
                recoveryAction: .approveHelper
            )
        case let .helperFailure(detail):
            Self(
                title: "DVT helper 失敗",
                message: "\(detail)。已停止位置更新，請重新準備裝置。",
                recoveryTitle: "重新準備",
                recoveryAction: .retry
            )
        case let .clearFailed(detail):
            Self(
                title: "尚未清除模擬定位",
                message: "\(detail)。目前不能宣稱已恢復真實定位，請重試 clear。",
                recoveryTitle: "重試清除",
                recoveryAction: .retryClear
            )
        case let .transportFailure(detail):
            Self(
                title: "裝置連線失敗",
                message: detail,
                recoveryTitle: "重試",
                recoveryAction: .retry
            )
        default:
            Self(
                title: "裝置尚未就緒",
                message: String(describing: failure),
                recoveryTitle: "重試",
                recoveryAction: .retry
            )
        }
    }

    private static func prerequisitePresentation(
        stage: DevicePrerequisiteStage,
        detail: String
    ) -> Self {
        switch stage {
        case .trust:
            Self(
                title: "iPhone 尚未信任這台 Mac",
                message: "\(detail)。請解鎖 iPhone 並完成信任提示。",
                recoveryTitle: "完成信任後重試",
                recoveryAction: .approveTrust
            )
        case .developerMode:
            Self(
                title: "Developer Mode 未就緒",
                message: "\(detail)。請到 iPhone「設定 → 隱私權與安全性 → 開發者模式」開啟並重新啟動。",
                recoveryTitle: "完成設定後重試",
                recoveryAction: .enableDeveloperMode
            )
        case .developerDiskImage:
            Self(
                title: "Developer Disk Image 無法準備",
                message: "\(detail)。請確認 Xcode 支援此 iOS 版本後重試。",
                recoveryTitle: "重新準備 DDI",
                recoveryAction: .prepareDeveloperDiskImage
            )
        case .tunnel:
            Self(
                title: "USB tunnel prerequisite 未就緒",
                message: detail,
                recoveryTitle: "核准 Helper",
                recoveryAction: .approveHelper
            )
        default:
            Self(
                title: "裝置 prerequisite 失敗",
                message: "\(stage.rawValue)：\(detail)",
                recoveryTitle: "重試",
                recoveryAction: .retry
            )
        }
    }
}

extension DeviceLocationError: LocalizedError {
    var errorDescription: String? {
        DeviceFailurePresentation.make(for: self).message
    }
}

protocol DeviceLocationClient: Sendable {
    func discoverUSBDevices() async throws -> [USBDevice]
    func prepare(deviceID: DeviceID) async throws -> PreparedDeviceSession
    func setLocation(
        _ coordinate: DeviceCoordinate,
        context: DeviceMutationContext
    ) async throws
    func clearLocation(context: DeviceCleanupContext) async throws
    func shutdown(generation: DeviceSessionGeneration) async
}

struct RuntimeInstallation: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case existing
        case appManaged
    }

    let executableURL: URL
    let source: Source
}

enum RuntimeAvailability: Equatable, Sendable {
    case ready(RuntimeInstallation)
    case installationRequired(pythonURL: URL)
    case pythonUnavailable(minimumVersion: String)
    case incompleteManagedEnvironment
    case configurationFailure(RuntimeManagerFailure)
}

enum RuntimeInstallProgress: Equatable, Sendable {
    case checkingPython
    case creatingEnvironment
    case installingPinnedPackage
    case verifyingCapabilities
}

enum RuntimeInstallResult: Equatable, Sendable {
    case ready(RuntimeInstallation)
    case cancelled
    case pythonUnavailable(minimumVersion: String)
    case failed(RuntimeManagerFailure)
}

enum RuntimeInstallStep: String, Equatable, Hashable, Sendable {
    case createEnvironment
    case installPinnedPackage
    case verifyCapabilities
}

enum RuntimeManagerFailure: Error, Equatable, Hashable, Sendable {
    case installationInProgress
    case invalidLockManifest
    case unsafeApplicationSupportDirectory
    case commandFailed(step: RuntimeInstallStep, message: String)
    case processLaunchFailed(step: RuntimeInstallStep, message: String)
    case fileSystem(message: String)
}
