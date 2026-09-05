import Foundation
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class DeviceSetupStoreTests: XCTestCase {
    func testCompatibleRuntimeAndEnabledHelperPrepareSingleDevice() async throws {
        let device = try setupDevice(id: "one-device")
        let harness = SetupHarness(
            runtimeAvailability: .ready(Self.runtime),
            devices: [device],
            helperStatus: .enabled
        )

        await harness.store.start()

        guard case let .ready(session) = harness.store.state else {
            return XCTFail("Expected ready setup")
        }
        XCTAssertEqual(session.device, device)
        XCTAssertNotNil(harness.store.simulationStore)
    }

    func testRuntimeInstallationReportsProgressAndCanContinueToDevice() async throws {
        let device = try setupDevice(id: "one-device")
        let harness = SetupHarness(
            runtimeAvailability: .installationRequired(
                pythonURL: URL(fileURLWithPath: "/usr/bin/python3")
            ),
            installResult: .ready(Self.runtime),
            installProgress: [
                .checkingPython,
                .creatingEnvironment,
                .installingPinnedPackage,
                .verifyingCapabilities,
            ],
            devices: [device],
            helperStatus: .enabled
        )
        await harness.store.start()
        XCTAssertEqual(harness.store.state, .runtimeInstallationRequired)

        await harness.store.installRuntime()

        guard case .ready = harness.store.state else {
            return XCTFail("Expected setup to continue after installation")
        }
        XCTAssertFalse(harness.store.isInstalling)
    }

    func testMissingPythonAndHelperApprovalRemainActionable() async {
        let missingPython = SetupHarness(
            runtimeAvailability: .pythonUnavailable(minimumVersion: "3.9"),
            devices: [],
            helperStatus: .enabled
        )
        await missingPython.store.start()
        XCTAssertEqual(
            missingPython.store.state,
            .pythonUnavailable(minimumVersion: "3.9")
        )

        let helperApproval = SetupHarness(
            runtimeAvailability: .ready(Self.runtime),
            devices: [],
            helperStatus: .approvalRequired,
            approvalResult: .requiresSystemApproval
        )
        await helperApproval.store.start()
        XCTAssertEqual(helperApproval.store.state, .helperApprovalRequired)
        await helperApproval.store.requestHelperApproval()
        XCTAssertEqual(
            helperApproval.store.state,
            .helperRequiresSystemApproval
        )
    }

    func testZeroAndMultipleDevicesHaveDistinctSelectionStates() async throws {
        let noDevice = SetupHarness(
            runtimeAvailability: .ready(Self.runtime),
            devices: [],
            helperStatus: .enabled
        )
        await noDevice.store.start()
        XCTAssertEqual(noDevice.store.state, .noUSBDevice)

        let first = try setupDevice(id: "first-device")
        let second = try setupDevice(id: "second-device")
        let multiple = SetupHarness(
            runtimeAvailability: .ready(Self.runtime),
            devices: [first, second],
            helperStatus: .enabled
        )
        await multiple.store.start()
        XCTAssertEqual(
            multiple.store.state,
            .selectionRequired([first, second])
        )

        await multiple.store.selectDevice(second.id)

        guard case let .ready(session) = multiple.store.state else {
            return XCTFail("Expected explicitly selected device to become ready")
        }
        XCTAssertEqual(session.device, second)
    }

    func testIOS16RemainsVisibleButUnsupported() async throws {
        let device = try setupDevice(id: "old-device", majorVersion: 16)
        let harness = SetupHarness(
            runtimeAvailability: .ready(Self.runtime),
            devices: [device],
            helperStatus: .enabled
        )

        await harness.store.start()

        XCTAssertEqual(harness.store.state, .unsupported(device))
        XCTAssertNil(harness.store.simulationStore)
    }

    func testSMJobBlessAuthorizerReportsInstalledAndMissingHelper() async {
        let installed = SMJobBlessTunnelHelperAuthorizer(
            installer: FakePrivilegedHelperInstaller(isInstalled: true)
        )
        let missing = SMJobBlessTunnelHelperAuthorizer(
            installer: FakePrivilegedHelperInstaller(isInstalled: false)
        )

        let installedStatus = await installed.inspect()
        let missingStatus = await missing.inspect()
        XCTAssertEqual(installedStatus, .enabled)
        XCTAssertEqual(missingStatus, .approvalRequired)
    }

    func testSMJobBlessAuthorizerKeepsAuthorizationDenialRetryable() async {
        let installer = FakePrivilegedHelperInstaller(
            isInstalled: false,
            installError: .authorizationDenied
        )
        let authorizer = SMJobBlessTunnelHelperAuthorizer(
            installer: installer
        )

        let result = await authorizer.requestApproval()
        XCTAssertEqual(result, .approvalRequired)
    }

    func testSMJobBlessAuthorizerSurfacesInstallFailure() async {
        let installer = FakePrivilegedHelperInstaller(
            isInstalled: false,
            installError: .installFailed("signature mismatch")
        )
        let authorizer = SMJobBlessTunnelHelperAuthorizer(
            installer: installer
        )

        let result = await authorizer.requestApproval()
        XCTAssertEqual(result, .unavailable("signature mismatch"))
    }

    func testInstalledHelperMustMatchBundledExecutableAndRejectSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HelperMatch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let bundled = root.appendingPathComponent("bundled-helper")
        let installed = root.appendingPathComponent("installed-helper")
        try Data("same helper".utf8).write(to: bundled)
        try Data("same helper".utf8).write(to: installed)

        XCTAssertTrue(
            SMJobBlessPrivilegedHelperInstaller.executablesMatch(
                bundledURL: bundled,
                installedURL: installed
            )
        )

        try Data("old helper".utf8).write(to: installed)
        XCTAssertFalse(
            SMJobBlessPrivilegedHelperInstaller.executablesMatch(
                bundledURL: bundled,
                installedURL: installed
            )
        )

        try FileManager.default.removeItem(at: installed)
        try FileManager.default.createSymbolicLink(
            at: installed,
            withDestinationURL: bundled
        )
        XCTAssertFalse(
            SMJobBlessPrivilegedHelperInstaller.executablesMatch(
                bundledURL: bundled,
                installedURL: installed
            )
        )
    }

    private func setupDevice(
        id: String,
        majorVersion: Int = 17
    ) throws -> USBDevice {
        try USBDevice(
            id: DeviceID(id),
            name: "iPhone",
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: majorVersion,
                minorVersion: 0,
                patchVersion: 0
            )
        )
    }

    private static let runtime = RuntimeInstallation(
        executableURL: URL(fileURLWithPath: "/runtime/pymobiledevice3"),
        source: .existing
    )
}

@MainActor
private struct SetupHarness {
    let runtime: FakeSetupRuntime
    let device: FakeSetupDevice
    let authorizer: FakeSetupAuthorizer
    let store: DeviceSetupStore

    init(
        runtimeAvailability: RuntimeAvailability,
        installResult: RuntimeInstallResult = .cancelled,
        installProgress: [RuntimeInstallProgress] = [],
        devices: [USBDevice],
        helperStatus: TunnelHelperAuthorizationStatus,
        approvalResult: TunnelHelperAuthorizationStatus? = nil
    ) {
        runtime = FakeSetupRuntime(
            availability: runtimeAvailability,
            installResult: installResult,
            progress: installProgress
        )
        device = FakeSetupDevice(devices: devices)
        authorizer = FakeSetupAuthorizer(
            status: helperStatus,
            approvalResult: approvalResult ?? helperStatus
        )
        store = DeviceSetupStore(
            runtimeManager: runtime,
            device: device,
            helperAuthorizer: authorizer,
            lifecycleCoordinator: AppLifecycleCoordinator(),
            sleepObserver: SystemSleepObserver(
                notificationCenter: NotificationCenter(),
                willSleepNotification: Notification.Name("unused-sleep"),
                didWakeNotification: Notification.Name("unused-wake")
            )
        )
    }
}

private actor FakeSetupRuntime: DeviceRuntimeManaging {
    let availability: RuntimeAvailability
    let installResult: RuntimeInstallResult
    let progress: [RuntimeInstallProgress]

    init(
        availability: RuntimeAvailability,
        installResult: RuntimeInstallResult,
        progress: [RuntimeInstallProgress]
    ) {
        self.availability = availability
        self.installResult = installResult
        self.progress = progress
    }

    func inspect() async -> RuntimeAvailability {
        availability
    }

    func install(
        progress callback: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async -> RuntimeInstallResult {
        progress.forEach(callback)
        return installResult
    }

    func cancelRuntimeInstallation() async {}
}

private actor FakeSetupAuthorizer: TunnelHelperAuthorizing {
    let status: TunnelHelperAuthorizationStatus
    let approvalResult: TunnelHelperAuthorizationStatus

    init(
        status: TunnelHelperAuthorizationStatus,
        approvalResult: TunnelHelperAuthorizationStatus
    ) {
        self.status = status
        self.approvalResult = approvalResult
    }

    func inspect() async -> TunnelHelperAuthorizationStatus {
        status
    }

    func requestApproval() async -> TunnelHelperAuthorizationStatus {
        approvalResult
    }
}

private struct FakePrivilegedHelperInstaller:
    PrivilegedHelperInstalling,
    @unchecked Sendable
{
    let isInstalled: Bool
    let installError: PrivilegedHelperInstallError?

    init(
        isInstalled: Bool,
        installError: PrivilegedHelperInstallError? = nil
    ) {
        self.isInstalled = isInstalled
        self.installError = installError
    }

    func installed() -> Bool {
        isInstalled
    }

    func install() throws {
        if let installError {
            throw installError
        }
    }
}

private actor FakeSetupDevice: DeviceSessionPreparing {
    let devices: [USBDevice]
    private var sessionState: DeviceSessionState = .disconnected
    private var generation = DeviceSessionGeneration(rawValue: 0)

    init(devices: [USBDevice]) {
        self.devices = devices
    }

    func connect(
        selectedDeviceID: DeviceID?
    ) async throws -> PreparedDeviceSession {
        guard !devices.isEmpty else {
            sessionState = .disconnected
            throw DeviceLocationError.noUSBDevice
        }
        let device: USBDevice
        if let selectedDeviceID {
            guard let selected = devices.first(where: {
                $0.id == selectedDeviceID
            }) else {
                throw DeviceLocationError.deviceNotFound
            }
            device = selected
        } else {
            guard devices.count == 1, let only = devices.first else {
                sessionState = .selectionRequired(devices)
                throw DeviceLocationError.selectionRequired
            }
            device = only
        }
        guard device.support == .supported else {
            sessionState = .selectionRequired(devices)
            throw DeviceLocationError.unsupportedDevice
        }
        generation = try generation.advanced()
        let session = PreparedDeviceSession(
            device: device,
            generation: generation
        )
        sessionState = .ready(session)
        return session
    }

    func currentSessionState() async -> DeviceSessionState {
        sessionState
    }

    func discoverUSBDevices() async throws -> [USBDevice] {
        devices
    }

    func prepare(deviceID: DeviceID) async throws -> PreparedDeviceSession {
        try await connect(selectedDeviceID: deviceID)
    }

    func setLocation(
        _ coordinate: DeviceCoordinate,
        context: DeviceMutationContext
    ) async throws {}

    func reconnect() async throws -> PreparedDeviceSession {
        throw DeviceLocationError.usbDisconnected
    }

    func clearLocation(context: DeviceCleanupContext) async throws {}
    func shutdown(generation: DeviceSessionGeneration) async {}
    func teardownForQuit() async throws {}
}
