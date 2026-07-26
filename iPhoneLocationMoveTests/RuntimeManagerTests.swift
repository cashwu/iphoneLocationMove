import Foundation
import XCTest
@testable import iPhoneLocationMove

final class RuntimeManagerTests: XCTestCase {
    func testCompatibleExistingInstallationUsesCapabilityProbesWithoutCreatingVenv() async throws {
        let harness = try RuntimeHarness()
        let executable = URL(fileURLWithPath: "/tools/pymobiledevice3")
        let runner = FakeRuntimeProcessRunner(stubs: .compatibleRuntime)
        let manager = RuntimeManager(
            configuration: harness.configuration(existing: [executable]),
            processRunner: runner
        )

        let availability = await manager.inspect()

        XCTAssertEqual(
            availability,
            .ready(RuntimeInstallation(executableURL: executable, source: .existing))
        )
        let commands = await runner.commands
        XCTAssertEqual(commands.map(\.arguments), [
            ["usbmux", "list", "--help"],
            ["lockdown", "start-tunnel", "--help"],
            ["developer", "dvt", "simulate-location", "set", "--help"],
        ])
        XCTAssertFalse(commands.contains { $0.arguments.contains("venv") })
        XCTAssertFalse(commands.contains { $0.arguments.contains("--version") })
    }

    func testInstallCallAlsoReusesCompatibleExistingInstallation() async throws {
        let harness = try RuntimeHarness()
        let executable = URL(fileURLWithPath: "/tools/pymobiledevice3")
        let runner = FakeRuntimeProcessRunner(stubs: .compatibleRuntime)
        let manager = RuntimeManager(
            configuration: harness.configuration(existing: [executable]),
            processRunner: runner
        )

        let result = await manager.install()

        XCTAssertEqual(
            result,
            .ready(RuntimeInstallation(executableURL: executable, source: .existing))
        )
        let commands = await runner.commands
        XCTAssertFalse(commands.contains { $0.arguments.contains("venv") })
    }

    func testVersionPresenceDoesNotOverrideMissingScriptModeCapability() async throws {
        let harness = try RuntimeHarness()
        let executable = URL(fileURLWithPath: "/tools/pymobiledevice3")
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let runner = FakeRuntimeProcessRunner(stubs: [
            .success(),
            .success(stdout: "Usage: start-tunnel"),
            .success(stderr: "Python 3.11.9"),
        ])
        let manager = RuntimeManager(
            configuration: harness.configuration(existing: [executable], python: [python]),
            processRunner: runner
        )

        let availability = await manager.inspect()

        XCTAssertEqual(availability, .installationRequired(pythonURL: python))
        let commands = await runner.commands
        XCTAssertFalse(
            commands
                .filter { $0.executableURL == executable }
                .contains { $0.arguments.contains("--version") }
        )
        XCTAssertEqual(commands.last?.arguments, ["--version"])
    }

    func testDVTWithoutRSDCapabilityIsNotCompatible() async throws {
        let harness = try RuntimeHarness()
        let executable = URL(fileURLWithPath: "/tools/pymobiledevice3")
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let runner = FakeRuntimeProcessRunner(stubs: [
            .success(stdout: "[]"),
            .success(stdout: "Options: --script-mode"),
            .success(stdout: "Usage: simulate-location set"),
            .success(stderr: "Python 3.11.9"),
        ])
        let manager = RuntimeManager(
            configuration: harness.configuration(existing: [executable], python: [python]),
            processRunner: runner
        )

        let availability = await manager.inspect()

        XCTAssertEqual(availability, .installationRequired(pythonURL: python))
    }

    func testMissingCompatiblePythonIsActionableAndNotReady() async throws {
        let harness = try RuntimeHarness()
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let runner = FakeRuntimeProcessRunner(stubs: [
            .success(exitCode: 127, stderr: "python3: command not found"),
        ])
        let manager = RuntimeManager(
            configuration: harness.configuration(python: [python]),
            processRunner: runner
        )

        let availability = await manager.inspect()

        XCTAssertEqual(
            availability,
            .pythonUnavailable(minimumVersion: RuntimeManager.minimumPythonVersion)
        )
    }

    func testIncompleteManagedEnvironmentFailsClosedWithoutExecutingIt() async throws {
        let harness = try RuntimeHarness()
        try FileManager.default.createDirectory(
            at: harness.configuration().managedEnvironmentURL,
            withIntermediateDirectories: true
        )
        let runner = FakeRuntimeProcessRunner(stubs: [])
        let manager = RuntimeManager(
            configuration: harness.configuration(),
            processRunner: runner
        )

        let availability = await manager.inspect()

        XCTAssertEqual(availability, .incompleteManagedEnvironment)
        let commands = await runner.commands
        XCTAssertTrue(commands.isEmpty)
    }

    func testInstallCreatesOnlyAppManagedVenvFromPinnedManifestAndReportsProgress() async throws {
        let harness = try RuntimeHarness()
        let python = URL(fileURLWithPath: "/usr/local/bin/python3")
        let runner = FakeRuntimeProcessRunner(stubs: [
            .success(stderr: "Python 3.12.2"),
            .success(),
            .success(),
        ] + .compatibleRuntime + .compatibleRuntime)
        let recorder = InstallProgressRecorder()
        let configuration = harness.configuration(python: [python])
        let manager = RuntimeManager(configuration: configuration, processRunner: runner)

        let result = await manager.install { recorder.append($0) }

        guard case let .ready(runtime) = result else {
            return XCTFail("Expected ready runtime, got \(result)")
        }
        XCTAssertEqual(runtime.source, .appManaged)
        XCTAssertEqual(
            runtime.executableURL,
            configuration.managedEnvironmentURL
                .appendingPathComponent("bin")
                .appendingPathComponent("pymobiledevice3")
        )
        XCTAssertEqual(
            recorder.values,
            [.checkingPython, .creatingEnvironment, .installingPinnedPackage, .verifyingCapabilities]
        )

        let commands = await runner.commands
        let venvCommand = try XCTUnwrap(commands.first { $0.arguments.first == "-m" })
        XCTAssertEqual(venvCommand.executableURL, python)
        XCTAssertEqual(Array(venvCommand.arguments.prefix(2)), ["-m", "venv"])

        let pipCommand = try XCTUnwrap(commands.first { $0.arguments.contains("pip") })
        XCTAssertTrue(pipCommand.executableURL.path.contains(configuration.applicationSupportDirectory.path))
        XCTAssertEqual(
            Array(pipCommand.arguments.suffix(1)),
            [RuntimeHarness.pinnedRequirement]
        )
        XCTAssertFalse(commands.contains { $0.executableURL.path == "/usr/local/bin/pip" })
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: configuration.managedEnvironmentURL
                    .appendingPathComponent(RuntimeManager.completionMarkerName)
                    .path
            )
        )
        let installedAvailability = await manager.inspect()
        XCTAssertEqual(
            installedAvailability,
            .ready(RuntimeInstallation(executableURL: runtime.executableURL, source: .appManaged))
        )
    }

    func testAtomicPublishLeavesPymobiledeviceLauncherRelocatable() async throws {
        let harness = try RuntimeHarness()
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let configuration = harness.configuration(python: [python])
        let runner = FakeRuntimeProcessRunner(stubs: [
            .success(stderr: "Python 3.11.9"),
            .success(),
            .success(),
        ] + .compatibleRuntime)
        let manager = RuntimeManager(
            configuration: configuration,
            processRunner: runner
        )

        guard case .ready = await manager.install() else {
            return XCTFail("Expected installation to succeed")
        }

        let launcherURL = configuration.managedEnvironmentURL
            .appendingPathComponent("bin")
            .appendingPathComponent("pymobiledevice3")
        let launcher = try String(contentsOf: launcherURL, encoding: .utf8)
        XCTAssertFalse(launcher.contains(".pymobiledevice3-install-"))
        XCTAssertTrue(launcher.contains(#""$script_dir/python" -m pymobiledevice3"#))
    }

    func testCancelledInstallStaysRetryableAndNeverPublishesIncompleteVenv() async throws {
        let harness = try RuntimeHarness()
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let runner = FakeRuntimeProcessRunner(stubs: [
            .success(stderr: "Python 3.11.9"),
            .waitForCancellation,
        ])
        let configuration = harness.configuration(python: [python])
        let manager = RuntimeManager(configuration: configuration, processRunner: runner)

        let installation = Task { await manager.install() }
        await runner.waitForCommandCount(2)
        await manager.cancelInstallation()

        let cancelledResult = await installation.value
        XCTAssertEqual(cancelledResult, .cancelled)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: configuration.managedEnvironmentURL.path)
        )

        await runner.append(stubs: [
            .success(stderr: "Python 3.11.9"),
            .success(),
            .success(),
        ] + .compatibleRuntime)

        guard case .ready = await manager.install() else {
            return XCTFail("A cancelled installation must be retryable")
        }
    }

    func testFailedInstallReturnsTypedErrorAndDoesNotPublishVenv() async throws {
        let harness = try RuntimeHarness()
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let runner = FakeRuntimeProcessRunner(stubs: [
            .success(stderr: "Python 3.11.9"),
            .success(),
            .success(exitCode: 1, stderr: "network unavailable"),
        ])
        let configuration = harness.configuration(python: [python])
        let manager = RuntimeManager(configuration: configuration, processRunner: runner)

        let result = await manager.install()

        XCTAssertEqual(
            result,
            .failed(
                .commandFailed(
                    step: .installPinnedPackage,
                    message: "network unavailable"
                )
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: configuration.managedEnvironmentURL.path)
        )
    }

    func testRetryReplacesAnIncompleteManagedEnvironment() async throws {
        let harness = try RuntimeHarness()
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let configuration = harness.configuration(python: [python])
        try FileManager.default.createDirectory(
            at: configuration.managedEnvironmentURL,
            withIntermediateDirectories: true
        )
        try Data("partial".utf8).write(
            to: configuration.managedEnvironmentURL.appendingPathComponent("partial-install")
        )
        let runner = FakeRuntimeProcessRunner(stubs: [
            .success(stderr: "Python 3.11.9"),
            .success(),
            .success(),
        ] + .compatibleRuntime)
        let manager = RuntimeManager(configuration: configuration, processRunner: runner)

        guard case .ready = await manager.install() else {
            return XCTFail("Expected retry to replace incomplete environment")
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: configuration.managedEnvironmentURL
                    .appendingPathComponent("partial-install")
                    .path
            )
        )
    }
}

private struct RuntimeHarness {
    static let pinnedRequirement = "pymobiledevice3==9.36.3"

    let root: URL
    let manifestURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        manifestURL = root.appendingPathComponent("pymobiledevice3.lock")
        try Data("\(Self.pinnedRequirement)\n".utf8).write(to: manifestURL)
    }

    func configuration(
        existing: [URL] = [],
        python: [URL] = []
    ) -> RuntimeManager.Configuration {
        RuntimeManager.Configuration(
            applicationSupportDirectory: root.appendingPathComponent("Application Support"),
            existingExecutableURLs: existing,
            pythonExecutableURLs: python,
            lockManifestURL: manifestURL
        )
    }
}

private actor FakeRuntimeProcessRunner: RuntimeProcessRunning {
    enum Stub: Sendable {
        case output(RuntimeProcessOutput)
        case failure(String)
        case waitForCancellation

        static func success(
            exitCode: Int32 = 0,
            stdout: String = "",
            stderr: String = ""
        ) -> Self {
            .output(
                RuntimeProcessOutput(exitCode: exitCode, standardOutput: stdout, standardError: stderr)
            )
        }
    }

    private var stubs: [Stub]
    private(set) var commands: [RuntimeProcessCommand] = []

    init(stubs: [Stub]) {
        self.stubs = stubs
    }

    func run(_ command: RuntimeProcessCommand) async throws -> RuntimeProcessOutput {
        commands.append(command)
        guard !stubs.isEmpty else {
            throw FakeRuntimeError(message: "Unexpected command: \(command)")
        }
        let stub = stubs.removeFirst()
        switch stub {
        case let .output(output):
            if output.exitCode == 0, command.arguments.contains("pip") {
                try writeStagingPymobiledeviceLauncher(for: command)
            }
            return output
        case let .failure(message):
            throw FakeRuntimeError(message: message)
        case .waitForCancellation:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw FakeRuntimeError(message: "Cancellation was not propagated")
        }
    }

    private func writeStagingPymobiledeviceLauncher(
        for command: RuntimeProcessCommand
    ) throws {
        let environmentURL = command.executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let launcherURL = environmentURL
            .appendingPathComponent("bin")
            .appendingPathComponent("pymobiledevice3")
        try FileManager.default.createDirectory(
            at: launcherURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let launcher = """
        #!/bin/sh
        exec "\(environmentURL.path)/bin/python" "$0" "$@"
        """
        try Data(launcher.utf8).write(to: launcherURL)
    }

    func append(stubs newStubs: [Stub]) {
        stubs.append(contentsOf: newStubs)
    }

    func waitForCommandCount(_ expectedCount: Int) async {
        while commands.count < expectedCount {
            await Task.yield()
        }
    }
}

private extension Array where Element == FakeRuntimeProcessRunner.Stub {
    static var compatibleRuntime: Self {
        [
            .success(stdout: "[]"),
            .success(stdout: "Options: --script-mode"),
            .success(stdout: "Usage: simulate-location set; Options: --rsd"),
        ]
    }
}

private struct FakeRuntimeError: Error, Sendable {
    let message: String
}

private final class InstallProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RuntimeInstallProgress] = []

    var values: [RuntimeInstallProgress] {
        lock.withLock { storage }
    }

    func append(_ value: RuntimeInstallProgress) {
        lock.withLock {
            storage.append(value)
        }
    }
}
