import Foundation

struct RuntimeProcessCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
}

struct RuntimeProcessOutput: Equatable, Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

protocol RuntimeProcessRunning: Sendable {
    func run(_ command: RuntimeProcessCommand) async throws -> RuntimeProcessOutput
}

struct FoundationRuntimeProcessRunner: RuntimeProcessRunning {
    func run(_ command: RuntimeProcessCommand) async throws -> RuntimeProcessOutput {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let outputCollector = RuntimeDataCollector()
        let errorCollector = RuntimeDataCollector()
        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }

        let launchControl = RuntimeProcessLaunchControl()
        let output = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { terminatedProcess in
                    standardOutput.fileHandleForReading.readabilityHandler = nil
                    standardError.fileHandleForReading.readabilityHandler = nil
                    outputCollector.append(standardOutput.fileHandleForReading.readDataToEndOfFile())
                    errorCollector.append(standardError.fileHandleForReading.readDataToEndOfFile())

                    continuation.resume(
                        returning: RuntimeProcessOutput(
                            exitCode: terminatedProcess.terminationStatus,
                            standardOutput: outputCollector.string,
                            standardError: errorCollector.string
                        )
                    )
                }

                do {
                    try launchControl.launch(process)
                } catch {
                    standardOutput.fileHandleForReading.readabilityHandler = nil
                    standardError.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            launchControl.cancel()
        }

        try Task.checkCancellation()
        return output
    }
}

actor RuntimeManager {
    static let minimumPythonVersion = "3.9"
    static let completionMarkerName = ".install-complete"

    struct Configuration: Equatable, Sendable {
        let applicationSupportDirectory: URL
        let existingExecutableURLs: [URL]
        let pythonExecutableURLs: [URL]
        let lockManifestURL: URL

        var managedEnvironmentURL: URL {
            applicationSupportDirectory.appendingPathComponent("pymobiledevice3-venv")
        }

        static func live(
            bundle: Bundle = .main,
            processInfo: ProcessInfo = .processInfo,
            fileManager: FileManager = .default
        ) throws -> Self {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw RuntimeManagerFailure.fileSystem(
                    message: "Application Support directory is unavailable"
                )
            }
            guard let lockManifestURL = bundle.url(
                forResource: "pymobiledevice3",
                withExtension: "lock"
            ) else {
                throw RuntimeManagerFailure.invalidLockManifest
            }

            return Self(
                applicationSupportDirectory: applicationSupport
                    .appendingPathComponent("iPhoneLocationMove", isDirectory: true)
                    .appendingPathComponent("DeviceRuntime", isDirectory: true),
                existingExecutableURLs: executableCandidates(
                    named: "pymobiledevice3",
                    environment: processInfo.environment
                ),
                pythonExecutableURLs: executableCandidates(
                    named: "python3",
                    environment: processInfo.environment,
                    additionalPaths: [
                        "/usr/bin/python3",
                        "/opt/homebrew/bin/python3",
                        "/usr/local/bin/python3",
                    ]
                ),
                lockManifestURL: lockManifestURL
            )
        }

        private static func executableCandidates(
            named name: String,
            environment: [String: String],
            additionalPaths: [String] = []
        ) -> [URL] {
            let pathCandidates = (environment["PATH"] ?? "")
                .split(separator: ":")
                .map {
                    URL(fileURLWithPath: String($0), isDirectory: true)
                        .appendingPathComponent(name)
                }
            let additionalCandidates = additionalPaths.map(URL.init(fileURLWithPath:))
            var seen = Set<String>()
            return (pathCandidates + additionalCandidates).filter {
                seen.insert($0.standardizedFileURL.path).inserted
            }
        }
    }

    private let configuration: Configuration
    private let processRunner: any RuntimeProcessRunning
    private var installationTask: Task<RuntimeInstallResult, Never>?

    init(
        configuration: Configuration,
        processRunner: any RuntimeProcessRunning = FoundationRuntimeProcessRunner()
    ) {
        self.configuration = configuration
        self.processRunner = processRunner
    }

    func inspect() async -> RuntimeAvailability {
        for executableURL in configuration.existingExecutableURLs {
            if await hasRequiredCapabilities(executableURL: executableURL) {
                return .ready(
                    RuntimeInstallation(executableURL: executableURL, source: .existing)
                )
            }
        }

        if FileManager.default.fileExists(atPath: configuration.managedEnvironmentURL.path) {
            guard
                let pinnedRequirement = try? Self.loadPinnedRequirement(
                    from: configuration.lockManifestURL
                ),
                Self.completionMarkerMatches(
                    requirement: pinnedRequirement,
                    environmentURL: configuration.managedEnvironmentURL
                )
            else {
                return .incompleteManagedEnvironment
            }

            let executableURL = Self.runtimeExecutableURL(
                environmentURL: configuration.managedEnvironmentURL
            )
            guard await hasRequiredCapabilities(executableURL: executableURL) else {
                return .incompleteManagedEnvironment
            }
            return .ready(
                RuntimeInstallation(executableURL: executableURL, source: .appManaged)
            )
        }

        guard (try? Self.loadPinnedRequirement(from: configuration.lockManifestURL)) != nil else {
            return .configurationFailure(.invalidLockManifest)
        }
        if let pythonURL = await compatiblePythonURL() {
            return .installationRequired(pythonURL: pythonURL)
        }
        return .pythonUnavailable(minimumVersion: Self.minimumPythonVersion)
    }

    func install(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void = { _ in }
    ) async -> RuntimeInstallResult {
        guard installationTask == nil else {
            return .failed(.installationInProgress)
        }

        let installer = RuntimeInstaller(
            configuration: configuration,
            processRunner: processRunner,
            progress: progress
        )
        let task = Task {
            await installer.install()
        }
        installationTask = task
        let result = await task.value
        installationTask = nil
        return result
    }

    func cancelInstallation() {
        installationTask?.cancel()
    }

    private func compatiblePythonURL() async -> URL? {
        for pythonURL in configuration.pythonExecutableURLs {
            guard
                let output = try? await processRunner.run(
                    RuntimeProcessCommand(
                        executableURL: pythonURL,
                        arguments: ["--version"]
                    )
                ),
                output.exitCode == 0,
                Self.isCompatiblePythonVersion(
                    output.standardOutput + "\n" + output.standardError
                )
            else {
                continue
            }
            return pythonURL
        }
        return nil
    }

    private func hasRequiredCapabilities(executableURL: URL) async -> Bool {
        await Self.hasRequiredCapabilities(
            executableURL: executableURL,
            processRunner: processRunner
        )
    }

    fileprivate static func hasRequiredCapabilities(
        executableURL: URL,
        processRunner: any RuntimeProcessRunning
    ) async -> Bool {
        do {
            let usbDiscovery = try await processRunner.run(
                RuntimeProcessCommand(
                    executableURL: executableURL,
                    arguments: ["usbmux", "list", "--help"]
                )
            )
            guard usbDiscovery.exitCode == 0 else {
                return false
            }

            let tunnelHelp = try await processRunner.run(
                RuntimeProcessCommand(
                    executableURL: executableURL,
                    arguments: ["lockdown", "start-tunnel", "--help"]
                )
            )
            guard
                tunnelHelp.exitCode == 0,
                tunnelHelp.combinedOutput.contains("--script-mode")
            else {
                return false
            }

            let simulateLocationHelp = try await processRunner.run(
                RuntimeProcessCommand(
                    executableURL: executableURL,
                    arguments: ["developer", "dvt", "simulate-location", "set", "--help"]
                )
            )
            return simulateLocationHelp.exitCode == 0
                && simulateLocationHelp.combinedOutput.contains("--rsd")
        } catch {
            return false
        }
    }

    fileprivate static func loadPinnedRequirement(from url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RuntimeManagerFailure.invalidLockManifest
        }

        guard
            let content = String(data: data, encoding: .utf8),
            let requirement = content
                .split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .filter({ !$0.isEmpty && !$0.hasPrefix("#") })
                .onlyElement,
            isPinnedPymobiledeviceRequirement(requirement)
        else {
            throw RuntimeManagerFailure.invalidLockManifest
        }
        return requirement
    }

    fileprivate static func runtimeExecutableURL(environmentURL: URL) -> URL {
        environmentURL
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("pymobiledevice3")
    }

    fileprivate static func completionMarkerMatches(
        requirement: String,
        environmentURL: URL
    ) -> Bool {
        let markerURL = environmentURL.appendingPathComponent(Self.completionMarkerName)
        guard
            let data = try? Data(contentsOf: markerURL),
            let marker = String(data: data, encoding: .utf8)
        else {
            return false
        }
        return marker.trimmingCharacters(in: .whitespacesAndNewlines) == requirement
    }

    fileprivate static func isCompatiblePythonVersion(_ output: String) -> Bool {
        let pattern = #"Python\s+([0-9]+)\.([0-9]+)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
            ),
            let majorRange = Range(match.range(at: 1), in: output),
            let minorRange = Range(match.range(at: 2), in: output),
            let major = Int(output[majorRange]),
            let minor = Int(output[minorRange])
        else {
            return false
        }
        return major > 3 || (major == 3 && minor >= 9)
    }

    private static func isPinnedPymobiledeviceRequirement(_ requirement: String) -> Bool {
        let pattern = #"^pymobiledevice3==[0-9]+(?:\.[0-9]+){1,3}(?:[A-Za-z0-9._-]+)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        return regex.firstMatch(
            in: requirement,
            range: NSRange(requirement.startIndex..., in: requirement)
        ) != nil
    }
}

private struct RuntimeInstaller: Sendable {
    let configuration: RuntimeManager.Configuration
    let processRunner: any RuntimeProcessRunning
    let progress: @Sendable (RuntimeInstallProgress) -> Void

    func install() async -> RuntimeInstallResult {
        do {
            if let existingRuntime = await compatibleInstalledRuntime() {
                return .ready(existingRuntime)
            }

            progress(.checkingPython)
            guard let pythonURL = await compatiblePythonURL() else {
                if Task.isCancelled {
                    return .cancelled
                }
                return .pythonUnavailable(minimumVersion: RuntimeManager.minimumPythonVersion)
            }
            let pinnedRequirement = try RuntimeManager.loadPinnedRequirement(
                from: configuration.lockManifestURL
            )
            try validateApplicationSupportDirectory()
            try Task.checkCancellation()

            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(
                    at: configuration.applicationSupportDirectory,
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: configuration.managedEnvironmentURL.path) {
                    try fileManager.removeItem(at: configuration.managedEnvironmentURL)
                }
            } catch {
                throw RuntimeManagerFailure.fileSystem(message: error.localizedDescription)
            }

            let stagingURL = configuration.applicationSupportDirectory
                .appendingPathComponent(".pymobiledevice3-install-\(UUID().uuidString)")
            var didPublish = false
            defer {
                if !didPublish {
                    try? fileManager.removeItem(at: stagingURL)
                }
            }

            do {
                try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
            } catch {
                throw RuntimeManagerFailure.fileSystem(message: error.localizedDescription)
            }

            progress(.creatingEnvironment)
            try await runRequired(
                RuntimeProcessCommand(
                    executableURL: pythonURL,
                    arguments: ["-m", "venv", stagingURL.path]
                ),
                step: .createEnvironment
            )
            try Task.checkCancellation()

            let stagingPythonURL = stagingURL
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("python")
            progress(.installingPinnedPackage)
            try await runRequired(
                RuntimeProcessCommand(
                    executableURL: stagingPythonURL,
                    arguments: [
                        "-m",
                        "pip",
                        "install",
                        "--isolated",
                        "--disable-pip-version-check",
                        "--no-input",
                        pinnedRequirement,
                    ]
                ),
                step: .installPinnedPackage
            )
            try Task.checkCancellation()
            try writeRelocatablePymobiledeviceLauncher(
                environmentURL: stagingURL
            )

            let stagingRuntimeURL = RuntimeManager.runtimeExecutableURL(
                environmentURL: stagingURL
            )
            progress(.verifyingCapabilities)
            guard await RuntimeManager.hasRequiredCapabilities(
                executableURL: stagingRuntimeURL,
                processRunner: processRunner
            ) else {
                try Task.checkCancellation()
                throw RuntimeManagerFailure.commandFailed(
                    step: .verifyCapabilities,
                    message: "Installed runtime failed a required capability probe"
                )
            }
            try Task.checkCancellation()

            do {
                try Data(pinnedRequirement.utf8).write(
                    to: stagingURL.appendingPathComponent(RuntimeManager.completionMarkerName),
                    options: .atomic
                )
                try fileManager.moveItem(
                    at: stagingURL,
                    to: configuration.managedEnvironmentURL
                )
            } catch {
                throw RuntimeManagerFailure.fileSystem(message: error.localizedDescription)
            }
            didPublish = true

            return .ready(
                RuntimeInstallation(
                    executableURL: RuntimeManager.runtimeExecutableURL(
                        environmentURL: configuration.managedEnvironmentURL
                    ),
                    source: .appManaged
                )
            )
        } catch is CancellationError {
            return .cancelled
        } catch let failure as RuntimeManagerFailure {
            return .failed(failure)
        } catch {
            return .failed(.fileSystem(message: error.localizedDescription))
        }
    }

    private func writeRelocatablePymobiledeviceLauncher(
        environmentURL: URL
    ) throws {
        let launcherURL = RuntimeManager.runtimeExecutableURL(
            environmentURL: environmentURL
        )
        let launcher = """
        #!/bin/sh
        script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
        exec "$script_dir/python" -m pymobiledevice3 "$@"
        """

        do {
            try Data(launcher.utf8).write(to: launcherURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: launcherURL.path
            )
        } catch {
            throw RuntimeManagerFailure.fileSystem(
                message: error.localizedDescription
            )
        }
    }

    private func compatibleInstalledRuntime() async -> RuntimeInstallation? {
        for executableURL in configuration.existingExecutableURLs {
            if await RuntimeManager.hasRequiredCapabilities(
                executableURL: executableURL,
                processRunner: processRunner
            ) {
                return RuntimeInstallation(executableURL: executableURL, source: .existing)
            }
        }

        guard
            FileManager.default.fileExists(atPath: configuration.managedEnvironmentURL.path),
            let pinnedRequirement = try? RuntimeManager.loadPinnedRequirement(
                from: configuration.lockManifestURL
            ),
            RuntimeManager.completionMarkerMatches(
                requirement: pinnedRequirement,
                environmentURL: configuration.managedEnvironmentURL
            )
        else {
            return nil
        }
        let executableURL = RuntimeManager.runtimeExecutableURL(
            environmentURL: configuration.managedEnvironmentURL
        )
        guard await RuntimeManager.hasRequiredCapabilities(
            executableURL: executableURL,
            processRunner: processRunner
        ) else {
            return nil
        }
        return RuntimeInstallation(executableURL: executableURL, source: .appManaged)
    }

    private func compatiblePythonURL() async -> URL? {
        for pythonURL in configuration.pythonExecutableURLs {
            do {
                try Task.checkCancellation()
                let output = try await processRunner.run(
                    RuntimeProcessCommand(
                        executableURL: pythonURL,
                        arguments: ["--version"]
                    )
                )
                guard
                    output.exitCode == 0,
                    RuntimeManager.isCompatiblePythonVersion(
                        output.standardOutput + "\n" + output.standardError
                    )
                else {
                    continue
                }
                return pythonURL
            } catch is CancellationError {
                return nil
            } catch {
                continue
            }
        }
        return nil
    }

    private func runRequired(
        _ command: RuntimeProcessCommand,
        step: RuntimeInstallStep
    ) async throws {
        let output: RuntimeProcessOutput
        do {
            output = try await processRunner.run(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RuntimeManagerFailure.processLaunchFailed(
                step: step,
                message: error.localizedDescription
            )
        }
        guard output.exitCode == 0 else {
            let diagnostic = output.standardError
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = output.standardOutput
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RuntimeManagerFailure.commandFailed(
                step: step,
                message: !diagnostic.isEmpty
                    ? diagnostic
                    : (!fallback.isEmpty ? fallback : "Process exited with \(output.exitCode)")
            )
        }
    }

    private func validateApplicationSupportDirectory() throws {
        let url = configuration.applicationSupportDirectory.standardizedFileURL
        guard
            url.isFileURL,
            !url.path.isEmpty,
            url.path != "/",
            configuration.managedEnvironmentURL.standardizedFileURL.path
                .hasPrefix(url.path + "/")
        else {
            throw RuntimeManagerFailure.unsafeApplicationSupportDirectory
        }
    }
}

private final class RuntimeDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var string: String {
        lock.withLock {
            String(decoding: data, as: UTF8.self)
        }
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else {
            return
        }
        lock.withLock {
            data.append(newData)
        }
    }
}

private final class RuntimeProcessLaunchControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func launch(_ process: Process) throws {
        try lock.withLock {
            guard !cancelled else {
                throw CancellationError()
            }
            try process.run()
            self.process = process
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            guard let process, process.isRunning else {
                return
            }
            process.terminate()
        }
    }
}

private extension RuntimeProcessOutput {
    var combinedOutput: String {
        standardOutput + "\n" + standardError
    }
}

private extension Array {
    var onlyElement: Element? {
        count == 1 ? self[0] : nil
    }
}
