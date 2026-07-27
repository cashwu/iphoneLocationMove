import CryptoKit
import Darwin
import Foundation
import Security

// MARK: - Typed contract

struct CallerAuditIdentity: Hashable, Codable {
    let processIdentifier: Int32
    let effectiveUserIdentifier: UInt32
    let auditSessionIdentifier: Int32
    let connectionID: UUID
}

struct CallerTrustPolicy: Equatable {
    let designatedRequirement: String
    let teamID: String

    init(designatedRequirement: String, teamID: String) {
        precondition(!designatedRequirement.isEmpty)
        precondition(!teamID.isEmpty)
        self.designatedRequirement = designatedRequirement
        self.teamID = teamID
    }
}

struct VerifiedCaller: Equatable {
    let identity: CallerAuditIdentity
    let bundleURL: URL
    let teamID: String
    let designatedRequirement: String
}

struct DeviceID: Hashable, Codable {
    let rawValue: String

    init(validating rawValue: String) throws {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        guard (16...64).contains(rawValue.utf8.count),
              rawValue.unicodeScalars.allSatisfy(allowed.contains),
              rawValue.first != "-",
              rawValue.last != "-",
              rawValue.contains(where: \.isNumber)
        else {
            throw TunnelHelperError.invalidDeviceID
        }
        self.rawValue = rawValue
    }
}

struct TunnelLeaseID: Hashable, Codable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    init(validating rawValue: String) throws {
        guard let value = UUID(uuidString: rawValue) else {
            throw TunnelHelperError.unknownLease
        }
        self.rawValue = value
    }

    var description: String {
        rawValue.uuidString
    }
}

struct TunnelEndpoint: Equatable, Codable {
    let address: String
    let port: UInt16

    init(address: String, port: Int) throws {
        guard Self.isIPAddress(address), (1...Int(UInt16.max)).contains(port) else {
            throw TunnelHelperError.invalidEndpoint
        }
        self.address = address
        self.port = UInt16(port)
    }

    private static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return value.withCString {
            inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1
        }
    }
}

struct TunnelProcessDiagnostics: Equatable, Codable {
    let terminationStatus: Int32?
    let stderrTail: String
    let stderrByteCount: Int
}

struct TunnelLeaseSnapshot: Equatable, Codable {
    enum State: String, Codable {
        case running
        case exited
    }

    let leaseID: TunnelLeaseID
    let deviceID: DeviceID
    let endpoint: TunnelEndpoint
    let state: State
    let diagnostics: TunnelProcessDiagnostics
}

struct ReconcileReport: Equatable, Codable {
    let reclaimedLeaseCount: Int
    let failures: [TunnelHelperError]
}

struct TunnelHelperError: Error, Equatable, Codable, LocalizedError {
    enum Code: String, Codable {
        case callerNotTrusted
        case invalidDeviceID
        case unknownLease
        case leaseNotOwned
        case invalidRequest
        case invalidEndpoint
        case processLaunchFailed
        case processExited
        case processStopFailed
        case runtimeUnavailable
        case runtimeIntegrity
        case runtimeInstallFailed
    }

    let code: Code
    let detail: String

    var errorDescription: String? {
        detail
    }

    static let callerNotTrusted = Self(
        code: .callerNotTrusted,
        detail: "Caller identity or code signature is not trusted."
    )
    static let invalidDeviceID = Self(
        code: .invalidDeviceID,
        detail: "The device identifier is invalid."
    )
    static let unknownLease = Self(
        code: .unknownLease,
        detail: "The tunnel lease does not exist."
    )
    static let leaseNotOwned = Self(
        code: .leaseNotOwned,
        detail: "The tunnel lease belongs to another caller session."
    )
    static let invalidRequest = Self(
        code: .invalidRequest,
        detail: "The request is outside the typed tunnel contract."
    )
    static let invalidEndpoint = Self(
        code: .invalidEndpoint,
        detail: "The tunnel process did not return a valid RSD endpoint."
    )
    static let processLaunchFailed = Self(
        code: .processLaunchFailed,
        detail: "The fixed tunnel process could not be launched."
    )
    static let processExited = Self(
        code: .processExited,
        detail: "The tunnel process exited before becoming ready."
    )
    static let processStopFailed = Self(
        code: .processStopFailed,
        detail: "The tunnel process could not be stopped."
    )
    static let runtimeUnavailable = Self(
        code: .runtimeUnavailable,
        detail: "No trusted pinned tunnel runtime is available."
    )
    static let runtimeIntegrity = Self(
        code: .runtimeIntegrity,
        detail: "The pinned tunnel runtime failed an integrity check."
    )
    static let runtimeInstallFailed = Self(
        code: .runtimeInstallFailed,
        detail: "The pinned tunnel runtime could not be atomically installed."
    )
}

// MARK: - Caller code trust

protocol CallerCodeVerifying {
    func verify(
        identity: CallerAuditIdentity,
        policy: CallerTrustPolicy
    ) throws -> VerifiedCaller
}

final class SecurityCallerCodeVerifier: CallerCodeVerifying {
    func verify(
        identity: CallerAuditIdentity,
        policy: CallerTrustPolicy
    ) throws -> VerifiedCaller {
        var guestCode: SecCode?
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: identity.processIdentifier)
        ] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode) == errSecSuccess,
              let guestCode
        else {
            throw TunnelHelperError.callerNotTrusted
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            policy.designatedRequirement as CFString,
            [],
            &requirement
        ) == errSecSuccess,
            let requirement
        else {
            throw TunnelHelperError.callerNotTrusted
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(guestCode, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            throw TunnelHelperError.callerNotTrusted
        }

        let validationFlags = SecCSFlags(
            rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures
        )
        guard SecStaticCodeCheckValidity(
            staticCode,
            validationFlags,
            requirement
        ) == errSecSuccess else {
            throw TunnelHelperError.callerNotTrusted
        }

        var rawSigningInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation),
            &rawSigningInfo
        ) == errSecSuccess,
            let signingInfo = rawSigningInfo as? [String: Any],
            let teamID = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String,
            teamID == policy.teamID,
            let executableURL = signingInfo[kSecCodeInfoMainExecutable as String] as? URL,
            let bundleURL = Self.appBundleURL(containing: executableURL)
        else {
            throw TunnelHelperError.callerNotTrusted
        }

        return VerifiedCaller(
            identity: identity,
            bundleURL: bundleURL,
            teamID: teamID,
            designatedRequirement: policy.designatedRequirement
        )
    }

    private static func appBundleURL(containing executableURL: URL) -> URL? {
        var candidate = executableURL.deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}

// MARK: - Pinned runtime

struct EmbeddedPayloadFile: Codable, Equatable, Hashable {
    let relativePath: String
    let sha256: String
    let mode: UInt16

    init(relativePath: String, sha256: String, mode: UInt16) {
        self.relativePath = relativePath
        self.sha256 = sha256.lowercased()
        self.mode = mode
    }
}

struct TunnelRuntimeManifest: Codable, Equatable {
    let files: [EmbeddedPayloadFile]
}

struct OfflineRuntimeBuildPlan: Equatable {
    let requirement: String
    let executableRelativePath: String
}

protocol OfflineRuntimeBuilding {
    func buildRuntime(
        in stagingURL: URL,
        plan: OfflineRuntimeBuildPlan
    ) throws
}

struct FoundationOfflineRuntimeBuilder: OfflineRuntimeBuilding {
    private static let interpreterURL = URL(fileURLWithPath: "/usr/bin/python3")

    func buildRuntime(
        in stagingURL: URL,
        plan: OfflineRuntimeBuildPlan
    ) throws {
        try verifyInterpreter()
        let runtimeURL = stagingURL.appendingPathComponent("runtime", isDirectory: true)
        let sitePackagesURL = runtimeURL.appendingPathComponent(
            "site-packages",
            isDirectory: true
        )
        try run(
            executableURL: Self.interpreterURL,
            arguments: [
                "-m", "pip",
                "install",
                "--isolated",
                "--no-index",
                "--no-input",
                "--no-cache-dir",
                "--no-compile",
                "--find-links", stagingURL.path,
                "--target", sitePackagesURL.path,
                plan.requirement,
            ],
            currentDirectoryURL: stagingURL
        )

        let entrypointURL = stagingURL.appendingPathComponent(plan.executableRelativePath)
        let entrypoint = """
        #!/usr/bin/python3 -Es
        import os
        import sys
        site_packages = os.path.join(os.path.dirname(__file__), "site-packages")
        sys.path.insert(0, site_packages)
        from pymobiledevice3.__main__ import main
        raise SystemExit(main())

        """
        do {
            try Data(entrypoint.utf8).write(
                to: entrypointURL,
                options: .withoutOverwriting
            )
            guard chmod(entrypointURL.path, 0o700) == 0 else {
                throw TunnelHelperError.runtimeInstallFailed
            }
        } catch let error as TunnelHelperError {
            throw error
        } catch {
            throw TunnelHelperError.runtimeInstallFailed
        }
    }

    private func verifyInterpreter() throws {
        var info = stat()
        guard lstat(Self.interpreterURL.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == 0,
              info.st_mode & 0o022 == 0
        else {
            throw TunnelHelperError.runtimeUnavailable
        }
        try run(
            executableURL: Self.interpreterURL,
            arguments: [
                "-c",
                "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)",
            ],
            currentDirectoryURL: URL(fileURLWithPath: "/var/empty", isDirectory: true)
        )
    }

    private func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "PIP_CONFIG_FILE": "/dev/null",
            "PIP_DISABLE_PIP_VERSION_CHECK": "1",
            "PIP_NO_INDEX": "1",
            "PYTHONNOUSERSITE": "1",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw TunnelHelperError.runtimeInstallFailed
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TunnelHelperError.runtimeInstallFailed
        }
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

struct EmbeddedDigestTable: Equatable {
    let manifestSHA256: String
    let files: [EmbeddedPayloadFile]
    let prebuiltExecutableRelativePath: String?
    let buildPlan: OfflineRuntimeBuildPlan?

    init(
        manifestSHA256: String,
        files: [EmbeddedPayloadFile],
        executableRelativePath: String
    ) {
        self.manifestSHA256 = manifestSHA256.lowercased()
        self.files = files
        prebuiltExecutableRelativePath = executableRelativePath
        buildPlan = nil
    }

    init(
        manifestSHA256: String,
        files: [EmbeddedPayloadFile],
        buildPlan: OfflineRuntimeBuildPlan
    ) {
        self.manifestSHA256 = manifestSHA256.lowercased()
        self.files = files
        prebuiltExecutableRelativePath = nil
        self.buildPlan = buildPlan
    }

    var executableRelativePath: String {
        prebuiltExecutableRelativePath ?? buildPlan?.executableRelativePath ?? ""
    }

    func validate() throws {
        guard Self.isDigest(manifestSHA256),
              !files.isEmpty,
              Set(files.map(\.relativePath)).count == files.count,
              Self.isSafeRelativePath(executableRelativePath),
              (buildPlan != nil
                  || files.contains(where: { $0.relativePath == executableRelativePath }))
        else {
            throw TunnelHelperError.runtimeUnavailable
        }
        if let buildPlan {
            guard buildPlan.requirement == "pymobiledevice3==9.36.3",
                  buildPlan.executableRelativePath == "runtime/pymobiledevice3"
            else {
                throw TunnelHelperError.runtimeUnavailable
            }
        }
        for file in files {
            guard Self.isSafeRelativePath(file.relativePath),
                  Self.isDigest(file.sha256),
                  file.mode & 0o022 == 0
            else {
                throw TunnelHelperError.runtimeUnavailable
            }
        }
    }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.unicodeScalars.allSatisfy(CharacterSet(charactersIn: "0123456789abcdef").contains)
    }

    fileprivate static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}

struct InstalledTunnelRuntime: Equatable {
    let rootURL: URL
    let executableURL: URL
}

protocol TunnelRuntimeProviding {
    func prepareRuntime(for caller: VerifiedCaller) throws -> InstalledTunnelRuntime
}

final class PinnedTunnelRuntimeInstaller: TunnelRuntimeProviding {
    static let payloadRelativePath = "Contents/Resources/tunnel-wheelhouse"
    static let manifestName = "runtime-manifest.json"

    private let digestTable: EmbeddedDigestTable
    private let destinationURL: URL
    private let requiredOwnerID: UInt32
    private let fileManager: FileManager
    private let runtimeBuilder: any OfflineRuntimeBuilding

    init(
        digestTable: EmbeddedDigestTable,
        destinationURL: URL,
        requiredOwnerID: UInt32 = 0,
        fileManager: FileManager = .default,
        runtimeBuilder: any OfflineRuntimeBuilding = FoundationOfflineRuntimeBuilder()
    ) {
        self.digestTable = digestTable
        self.destinationURL = destinationURL.standardizedFileURL
        self.requiredOwnerID = requiredOwnerID
        self.fileManager = fileManager
        self.runtimeBuilder = runtimeBuilder
    }

    func prepareRuntime(for caller: VerifiedCaller) throws -> InstalledTunnelRuntime {
        try digestTable.validate()
        if fileManager.fileExists(atPath: destinationURL.path) {
            return try validateInstalledRuntime()
        }

        let payloadRoot = caller.bundleURL
            .appendingPathComponent(Self.payloadRelativePath, isDirectory: true)
            .standardizedFileURL
        try ensureDirectoryTreeIsNotSymlink(
            root: caller.bundleURL,
            relativeDirectoryPath: Self.payloadRelativePath
        )

        let manifestURL = payloadRoot.appendingPathComponent(Self.manifestName)
        let manifestData = try secureRead(manifestURL)
        guard Self.digest(manifestData) == digestTable.manifestSHA256,
              let manifest = try? JSONDecoder().decode(TunnelRuntimeManifest.self, from: manifestData),
              manifest.files == digestTable.files
        else {
            throw integrityError("The signed payload manifest does not match the embedded trust anchor.")
        }

        var verifiedPayload: [(EmbeddedPayloadFile, Data)] = []
        for entry in digestTable.files {
            let parentPath = entry.relativePath
                .split(separator: "/")
                .dropLast()
                .joined(separator: "/")
            try ensureDirectoryTreeIsNotSymlink(
                root: payloadRoot,
                relativeDirectoryPath: parentPath
            )
            let sourceURL = try confinedURL(root: payloadRoot, relativePath: entry.relativePath)
            let data = try secureRead(sourceURL)
            guard Self.digest(data) == entry.sha256 else {
                throw integrityError("Payload digest mismatch: \(entry.relativePath)")
            }
            verifiedPayload.append((entry, data))
        }

        return try installAtomically(
            manifestData: manifestData,
            verifiedPayload: verifiedPayload
        )
    }

    private func installAtomically(
        manifestData: Data,
        verifiedPayload: [(EmbeddedPayloadFile, Data)]
    ) throws -> InstalledTunnelRuntime {
        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try verifySecureParent(parent)
        let staging = parent.appendingPathComponent(
            ".tunnel-runtime-staging-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            try setMode(0o700, at: staging)
            for (entry, data) in verifiedPayload {
                let target = try confinedURL(root: staging, relativePath: entry.relativePath)
                try createSecureDirectories(
                    from: staging,
                    through: target.deletingLastPathComponent()
                )
                try data.write(to: target, options: .withoutOverwriting)
                try setMode(mode_t(entry.mode), at: target)
            }
            let stagedManifest = staging.appendingPathComponent(Self.manifestName)
            try manifestData.write(to: stagedManifest, options: .withoutOverwriting)
            try setMode(0o600, at: stagedManifest)
            if let buildPlan = digestTable.buildPlan {
                try runtimeBuilder.buildRuntime(in: staging, plan: buildPlan)
            }
            _ = try validateRuntime(at: staging)

            guard rename(staging.path, destinationURL.path) == 0 else {
                if (errno == EEXIST || errno == ENOTEMPTY),
                   fileManager.fileExists(atPath: destinationURL.path)
                {
                    try? fileManager.removeItem(at: staging)
                    return try validateInstalledRuntime()
                }
                throw TunnelHelperError.runtimeInstallFailed
            }
            return try validateInstalledRuntime()
        } catch let error as TunnelHelperError {
            try? fileManager.removeItem(at: staging)
            throw error
        } catch {
            try? fileManager.removeItem(at: staging)
            throw TunnelHelperError.runtimeInstallFailed
        }
    }

    private func validateInstalledRuntime() throws -> InstalledTunnelRuntime {
        try validateRuntime(at: destinationURL)
    }

    @discardableResult
    private func validateRuntime(at root: URL) throws -> InstalledTunnelRuntime {
        try verifyDirectory(root, exactMode: 0o700)
        let manifestURL = root.appendingPathComponent(Self.manifestName)
        let manifestData = try secureRead(manifestURL)
        try verifyMetadata(manifestURL, exactMode: 0o600)
        guard Self.digest(manifestData) == digestTable.manifestSHA256,
              let manifest = try? JSONDecoder().decode(TunnelRuntimeManifest.self, from: manifestData),
              manifest.files == digestTable.files
        else {
            throw integrityError("Installed manifest does not match the embedded trust anchor.")
        }

        var expectedPaths = Set([Self.manifestName])
        for entry in digestTable.files {
            let fileURL = try confinedURL(root: root, relativePath: entry.relativePath)
            let data = try secureRead(fileURL)
            try verifyMetadata(fileURL, exactMode: mode_t(entry.mode))
            guard Self.digest(data) == entry.sha256 else {
                throw integrityError("Installed payload digest mismatch: \(entry.relativePath)")
            }
            expectedPaths.insert(entry.relativePath)
            let pathComponents = entry.relativePath.split(separator: "/").dropLast()
            for index in pathComponents.indices {
                expectedPaths.insert(
                    pathComponents[pathComponents.startIndex...index].joined(separator: "/")
                )
            }
        }

        guard let installedPaths = try? fileManager.subpathsOfDirectory(atPath: root.path) else {
            throw TunnelHelperError.runtimeIntegrity
        }
        for relativePath in installedPaths {
            let isGeneratedRuntime = digestTable.buildPlan != nil
                && (relativePath == "runtime" || relativePath.hasPrefix("runtime/"))
            guard expectedPaths.contains(relativePath) || isGeneratedRuntime else {
                throw integrityError("Unexpected installed runtime path: \(relativePath)")
            }
            let itemURL = try confinedURL(root: root, relativePath: relativePath)
            var info = stat()
            guard lstat(itemURL.path, &info) == 0,
                  info.st_mode & S_IFMT != S_IFLNK,
                  info.st_uid == requiredOwnerID,
                  info.st_mode & 0o022 == 0
            else {
                throw integrityError("Installed runtime contains a symlink: \(relativePath)")
            }
            if info.st_mode & S_IFMT == S_IFDIR, !isGeneratedRuntime {
                try verifyDirectory(itemURL, exactMode: 0o700)
            }
        }

        let executable = try confinedURL(
            root: root,
            relativePath: digestTable.executableRelativePath
        )
        if digestTable.buildPlan != nil {
            var info = stat()
            guard lstat(executable.path, &info) == 0,
                  info.st_mode & S_IFMT == S_IFREG,
                  info.st_uid == requiredOwnerID,
                  info.st_mode & 0o022 == 0,
                  info.st_mode & 0o111 != 0
            else {
                throw integrityError("Generated runtime executable is not secure.")
            }
        }
        return InstalledTunnelRuntime(rootURL: root, executableURL: executable)
    }

    private func secureRead(_ url: URL) throws -> Data {
        var info = stat()
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw TunnelHelperError.runtimeIntegrity
        }
        defer { close(descriptor) }
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG
        else {
            throw TunnelHelperError.runtimeIntegrity
        }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 {
                return output
            }
            guard count > 0 else {
                throw TunnelHelperError.runtimeIntegrity
            }
            output.append(buffer, count: count)
        }
    }

    private func ensureDirectoryTreeIsNotSymlink(
        root: URL,
        relativeDirectoryPath: String
    ) throws {
        var current = root
        var info = stat()
        guard lstat(current.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR
        else {
            throw TunnelHelperError.runtimeIntegrity
        }
        guard !relativeDirectoryPath.isEmpty else {
            return
        }
        for component in relativeDirectoryPath.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            guard lstat(current.path, &info) == 0,
                  info.st_mode & S_IFMT == S_IFDIR
            else {
                throw integrityError("Payload path contains a symlink: \(current.path)")
            }
        }
    }

    private func confinedURL(root: URL, relativePath: String) throws -> URL {
        guard EmbeddedDigestTable.isSafeRelativePath(relativePath) else {
            throw integrityError("Unsafe embedded runtime path: \(relativePath)")
        }
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw integrityError("Embedded runtime path escaped its root: \(relativePath)")
        }
        return candidate
    }

    private func createSecureDirectories(from root: URL, through target: URL) throws {
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else {
            throw TunnelHelperError.runtimeInstallFailed
        }
        let relative = target.path.dropFirst(root.path.count)
        var current = root
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            if !fileManager.fileExists(atPath: current.path) {
                try fileManager.createDirectory(at: current, withIntermediateDirectories: false)
                try setMode(0o700, at: current)
            }
            try verifyDirectory(current, exactMode: 0o700)
        }
    }

    private func verifyDirectory(_ url: URL, exactMode: mode_t) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == requiredOwnerID,
              info.st_mode & 0o777 == exactMode
        else {
            throw integrityError("Runtime directory owner or mode mismatch: \(url.path)")
        }
    }

    private func verifySecureParent(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == requiredOwnerID,
              info.st_mode & 0o022 == 0
        else {
            throw integrityError("Runtime install parent is not securely owned: \(url.path)")
        }
    }

    private func verifyMetadata(_ url: URL, exactMode: mode_t) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == requiredOwnerID,
              info.st_mode & 0o777 == exactMode,
              info.st_mode & 0o022 == 0
        else {
            throw integrityError("Runtime file owner or mode mismatch: \(url.path)")
        }
    }

    private func setMode(_ mode: mode_t, at url: URL) throws {
        guard chmod(url.path, mode) == 0 else {
            throw TunnelHelperError.runtimeInstallFailed
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func integrityError(_ detail: String) -> TunnelHelperError {
        TunnelHelperError(code: .runtimeIntegrity, detail: detail)
    }
}

// MARK: - Process boundary and leases

protocol TunnelProcessControlling: AnyObject {
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    var terminationStatus: Int32? { get }
    var diagnostics: TunnelProcessDiagnostics { get }
    func readEndpointLine() throws -> String
    func stop() throws
}

protocol TunnelProcessLaunching {
    func launch(
        runtime: InstalledTunnelRuntime,
        deviceID: DeviceID
    ) throws -> TunnelProcessControlling
}

private final class StderrCollector: @unchecked Sendable {
    private static let tailLimit = 4_096

    private let input: FileHandle
    private let lock = NSLock()
    private let drainGroup = DispatchGroup()
    private var tail = Data()
    private var byteCount = 0

    init(input: FileHandle) {
        self.input = input
    }

    func start() {
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { drainGroup.leave() }
            while true {
                do {
                    guard let data = try input.read(upToCount: 16_384), !data.isEmpty else {
                        return
                    }
                    append(data)
                } catch {
                    return
                }
            }
        }
    }

    func snapshot(waitForEOF: Bool) -> (tail: String, byteCount: Int) {
        if waitForEOF {
            _ = drainGroup.wait(timeout: .now() + 1)
        }
        return lock.withLock {
            (Self.safeUTF8String(from: tail), byteCount)
        }
    }

    private func append(_ data: Data) {
        lock.withLock {
            if byteCount > Int.max - data.count {
                byteCount = Int.max
            } else {
                byteCount += data.count
            }
            tail.append(data)
            if tail.count > Self.tailLimit {
                tail.removeFirst(tail.count - Self.tailLimit)
            }
        }
    }

    private static func safeUTF8String(from data: Data) -> String {
        var value = String(decoding: data, as: UTF8.self)
        while value.utf8.count > tailLimit {
            value.removeFirst()
        }
        return value
    }
}

final class FoundationTunnelProcess: TunnelProcessControlling {
    private let process: Process
    private let output: FileHandle
    private let stderrCollector: StderrCollector

    init(process: Process, output: FileHandle, errorOutput: FileHandle) {
        self.process = process
        self.output = output
        stderrCollector = StderrCollector(input: errorOutput)
        stderrCollector.start()
    }

    var processIdentifier: Int32 {
        process.processIdentifier
    }

    var isRunning: Bool {
        process.isRunning
    }

    var terminationStatus: Int32? {
        process.isRunning ? nil : process.terminationStatus
    }

    var diagnostics: TunnelProcessDiagnostics {
        let running = process.isRunning
        let stderr = stderrCollector.snapshot(waitForEOF: !running)
        return TunnelProcessDiagnostics(
            terminationStatus: running ? nil : process.terminationStatus,
            stderrTail: stderr.tail,
            stderrByteCount: stderr.byteCount
        )
    }

    func readEndpointLine() throws -> String {
        var data = Data()
        while true {
            guard let byte = try output.read(upToCount: 1), !byte.isEmpty else {
                throw TunnelHelperError.processExited
            }
            if byte[0] == 0x0A {
                break
            }
            guard data.count < 16_384 else {
                throw TunnelHelperError.invalidEndpoint
            }
            data.append(byte)
        }
        guard let line = String(data: data, encoding: .utf8) else {
            throw TunnelHelperError.invalidEndpoint
        }
        return line
    }

    func stop() throws {
        guard process.isRunning else {
            return
        }
        process.terminate()
        for _ in 0..<50 where process.isRunning {
            usleep(20_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            for _ in 0..<50 where process.isRunning {
                usleep(20_000)
            }
        }
        guard !process.isRunning else {
            throw TunnelHelperError.processStopFailed
        }
    }
}

final class FoundationTunnelProcessLauncher: TunnelProcessLaunching {
    static let processEnvironment = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "PYTHONNOUSERSITE": "1",
    ]

    func launch(
        runtime: InstalledTunnelRuntime,
        deviceID: DeviceID
    ) throws -> TunnelProcessControlling {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = runtime.executableURL
        process.arguments = [
            "lockdown",
            "start-tunnel",
            "--script-mode",
            "--udid",
            deviceID.rawValue
        ]
        process.standardOutput = output
        process.standardError = errorOutput
        process.environment = Self.processEnvironment
        do {
            try process.run()
        } catch {
            throw TunnelHelperError.processLaunchFailed
        }
        return FoundationTunnelProcess(
            process: process,
            output: output.fileHandleForReading,
            errorOutput: errorOutput.fileHandleForReading
        )
    }
}

private struct LeaseKey: Hashable {
    let caller: CallerAuditIdentity
    let deviceID: DeviceID
    let idempotencyKey: UUID
}

private final class TunnelLease {
    let key: LeaseKey
    let snapshot: TunnelLeaseSnapshot
    let process: TunnelProcessControlling

    init(
        key: LeaseKey,
        snapshot: TunnelLeaseSnapshot,
        process: TunnelProcessControlling
    ) {
        self.key = key
        self.snapshot = snapshot
        self.process = process
    }
}

final class TunnelLeaseManager: @unchecked Sendable {
    private let trustPolicy: CallerTrustPolicy
    private let callerVerifier: CallerCodeVerifying
    private let runtimeProvider: TunnelRuntimeProviding
    private let processLauncher: TunnelProcessLaunching
    private let lock = NSLock()
    private var leasesByID: [TunnelLeaseID: TunnelLease] = [:]
    private var leaseIDsByKey: [LeaseKey: TunnelLeaseID] = [:]

    init(
        trustPolicy: CallerTrustPolicy,
        callerVerifier: CallerCodeVerifying,
        runtimeProvider: TunnelRuntimeProviding,
        processLauncher: TunnelProcessLaunching
    ) {
        self.trustPolicy = trustPolicy
        self.callerVerifier = callerVerifier
        self.runtimeProvider = runtimeProvider
        self.processLauncher = processLauncher
    }

    func startTunnel(
        caller identity: CallerAuditIdentity,
        deviceID rawDeviceID: String,
        idempotencyKey: UUID
    ) throws -> TunnelLeaseSnapshot {
        try lock.withLock {
            let caller = try verifyCaller(identity)
            let deviceID = try DeviceID(validating: rawDeviceID)
            let key = LeaseKey(
                caller: caller.identity,
                deviceID: deviceID,
                idempotencyKey: idempotencyKey
            )
            if let leaseID = leaseIDsByKey[key], let lease = leasesByID[leaseID] {
                guard lease.process.isRunning else {
                    removeLease(leaseID)
                    throw TunnelHelperError.processExited
                }
                return lease.snapshot
            }

            let runtime = try runtimeProvider.prepareRuntime(for: caller)
            let process = try processLauncher.launch(runtime: runtime, deviceID: deviceID)
            let endpoint: TunnelEndpoint
            do {
                endpoint = try parseEndpoint(process.readEndpointLine())
            } catch {
                try? process.stop()
                throw error
            }
            guard process.isRunning else {
                throw TunnelHelperError(
                    code: .processExited,
                    detail: "The tunnel process exited with status \(process.terminationStatus ?? -1)."
                )
            }

            let leaseID = TunnelLeaseID()
            let snapshot = TunnelLeaseSnapshot(
                leaseID: leaseID,
                deviceID: deviceID,
                endpoint: endpoint,
                state: .running,
                diagnostics: process.diagnostics
            )
            leasesByID[leaseID] = TunnelLease(
                key: key,
                snapshot: snapshot,
                process: process
            )
            leaseIDsByKey[key] = leaseID
            return snapshot
        }
    }

    func stopTunnel(
        caller identity: CallerAuditIdentity,
        leaseID: TunnelLeaseID
    ) throws {
        try lock.withLock {
            let caller = try verifyCaller(identity)
            let lease = try ownedLease(leaseID, caller: caller.identity)
            do {
                try lease.process.stop()
            } catch {
                throw TunnelHelperError.processStopFailed
            }
            removeLease(leaseID)
        }
    }

    func status(
        caller identity: CallerAuditIdentity,
        leaseID: TunnelLeaseID
    ) throws -> TunnelLeaseSnapshot {
        try lock.withLock {
            let caller = try verifyCaller(identity)
            let lease = try ownedLease(leaseID, caller: caller.identity)
            let snapshot = makeSnapshot(for: lease)
            if snapshot.state == .exited {
                removeLease(leaseID)
            }
            return snapshot
        }
    }

    func reconcile(caller identity: CallerAuditIdentity) throws -> ReconcileReport {
        try lock.withLock {
            let caller = try verifyCaller(identity)
            let staleLeaseIDs = leasesByID.compactMap { leaseID, lease in
                lease.key.caller == caller.identity ? nil : leaseID
            }
            var reclaimed = 0
            var failures: [TunnelHelperError] = []
            for leaseID in staleLeaseIDs {
                guard let lease = leasesByID[leaseID] else {
                    continue
                }
                do {
                    try lease.process.stop()
                    removeLease(leaseID)
                    reclaimed += 1
                } catch {
                    failures.append(.processStopFailed)
                }
            }
            return ReconcileReport(reclaimedLeaseCount: reclaimed, failures: failures)
        }
    }

    @discardableResult
    func invalidateOwner(_ identity: CallerAuditIdentity) -> [TunnelHelperError] {
        lock.withLock {
            let ownedLeaseIDs = leasesByID.compactMap { leaseID, lease in
                lease.key.caller == identity ? leaseID : nil
            }
            var failures: [TunnelHelperError] = []
            for leaseID in ownedLeaseIDs {
                guard let lease = leasesByID[leaseID] else {
                    continue
                }
                do {
                    try lease.process.stop()
                    removeLease(leaseID)
                } catch {
                    failures.append(.processStopFailed)
                }
            }
            return failures
        }
    }

    private func verifyCaller(_ identity: CallerAuditIdentity) throws -> VerifiedCaller {
        let caller: VerifiedCaller
        do {
            caller = try callerVerifier.verify(identity: identity, policy: trustPolicy)
        } catch {
            throw TunnelHelperError.callerNotTrusted
        }
        guard caller.identity == identity,
              caller.teamID == trustPolicy.teamID,
              caller.designatedRequirement == trustPolicy.designatedRequirement
        else {
            throw TunnelHelperError.callerNotTrusted
        }
        return caller
    }

    private func parseEndpoint(_ line: String) throws -> TunnelEndpoint {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count == 2,
              let port = Int(fields[1])
        else {
            throw TunnelHelperError.invalidEndpoint
        }
        return try TunnelEndpoint(address: String(fields[0]), port: port)
    }

    private func ownedLease(
        _ leaseID: TunnelLeaseID,
        caller: CallerAuditIdentity
    ) throws -> TunnelLease {
        guard let lease = leasesByID[leaseID] else {
            throw TunnelHelperError.unknownLease
        }
        guard lease.key.caller == caller else {
            throw TunnelHelperError.leaseNotOwned
        }
        return lease
    }

    private func removeLease(_ leaseID: TunnelLeaseID) {
        guard let lease = leasesByID.removeValue(forKey: leaseID) else {
            return
        }
        leaseIDsByKey.removeValue(forKey: lease.key)
    }

    private func makeSnapshot(for lease: TunnelLease) -> TunnelLeaseSnapshot {
        let diagnostics = lease.process.diagnostics
        let state: TunnelLeaseSnapshot.State
        if diagnostics.terminationStatus != nil || !lease.process.isRunning {
            state = .exited
        } else {
            state = .running
        }
        return TunnelLeaseSnapshot(
            leaseID: lease.snapshot.leaseID,
            deviceID: lease.snapshot.deviceID,
            endpoint: lease.snapshot.endpoint,
            state: state,
            diagnostics: diagnostics
        )
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

// MARK: - Fixed XPC surface

private struct TunnelReply<Value: Codable>: Codable {
    let value: Value?
    let error: TunnelHelperError?

    static func success(_ value: Value) -> Self {
        Self(value: value, error: nil)
    }

    static func failure(_ error: TunnelHelperError) -> Self {
        Self(value: nil, error: error)
    }
}

private struct EmptyReply: Codable {}

#if !TUNNEL_HELPER_HARNESS
final class TunnelHelperXPCService: NSObject, TunnelHelperXPCProtocol {
    private let caller: CallerAuditIdentity
    private let manager: TunnelLeaseManager

    init(caller: CallerAuditIdentity, manager: TunnelLeaseManager) {
        self.caller = caller
        self.manager = manager
    }

    func startTunnel(
        deviceID: String,
        idempotencyKey: UUID,
        withReply reply: @escaping (Data) -> Void
    ) {
        respond(reply) {
            try manager.startTunnel(
                caller: caller,
                deviceID: deviceID,
                idempotencyKey: idempotencyKey
            )
        }
    }

    func stopTunnel(
        leaseID: UUID,
        withReply reply: @escaping (Data) -> Void
    ) {
        respond(reply) {
            try manager.stopTunnel(
                caller: caller,
                leaseID: TunnelLeaseID(leaseID)
            )
            return EmptyReply()
        }
    }

    func status(
        leaseID: UUID,
        withReply reply: @escaping (Data) -> Void
    ) {
        respond(reply) {
            try manager.status(
                caller: caller,
                leaseID: TunnelLeaseID(leaseID)
            )
        }
    }

    func reconcile(
        withReply reply: @escaping (Data) -> Void
    ) {
        respond(reply) {
            try manager.reconcile(caller: caller)
        }
    }

    private func respond<Value: Codable>(
        _ reply: @escaping (Data) -> Void,
        operation: () throws -> Value
    ) {
        let envelope: TunnelReply<Value>
        do {
            envelope = .success(try operation())
        } catch let error as TunnelHelperError {
            envelope = .failure(error)
        } catch {
            envelope = .failure(.invalidRequest)
        }
        reply((try? JSONEncoder.sorted.encode(envelope)) ?? Data())
    }
}

final class TunnelHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let trustPolicy: CallerTrustPolicy
    private let callerVerifier: CallerCodeVerifying
    private let manager: TunnelLeaseManager
    private let lock = NSLock()
    private var services: [ObjectIdentifier: TunnelHelperXPCService] = [:]

    init(
        trustPolicy: CallerTrustPolicy,
        callerVerifier: CallerCodeVerifying,
        manager: TunnelLeaseManager
    ) {
        self.trustPolicy = trustPolicy
        self.callerVerifier = callerVerifier
        self.manager = manager
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        let caller = CallerAuditIdentity(
            processIdentifier: connection.processIdentifier,
            effectiveUserIdentifier: connection.effectiveUserIdentifier,
            auditSessionIdentifier: Int32(connection.auditSessionIdentifier),
            connectionID: UUID()
        )
        guard (try? callerVerifier.verify(identity: caller, policy: trustPolicy)) != nil else {
            return false
        }

        let service = TunnelHelperXPCService(caller: caller, manager: manager)
        let identifier = ObjectIdentifier(connection)
        lock.withLock { services[identifier] = service }
        connection.exportedInterface = NSXPCInterface(with: TunnelHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak self, weak connection] in
            self?.manager.invalidateOwner(caller)
            guard let self, let connection else {
                return
            }
            _ = self.lock.withLock {
                self.services.removeValue(forKey: ObjectIdentifier(connection))
            }
        }
        connection.interruptionHandler = { [weak manager] in
            manager?.invalidateOwner(caller)
        }
        connection.resume()
        return true
    }
}
#endif

// The release digest table is generated from the signed wheelhouse during packaging.
// An absent generated table is deliberately unusable instead of falling back to
// caller-supplied manifests or paths.
private enum ProductionTrustAnchor {
#if TUNNEL_HELPER_CONTRACT_TESTING
    static let digestTable = EmbeddedDigestTable(
        manifestSHA256: "",
        files: [],
        executableRelativePath: ""
    )
#else
    static let digestTable = GeneratedTunnelTrustAnchor.digestTable
#endif

    static func callerPolicy() throws -> CallerTrustPolicy {
        var ownCode: SecCode?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess,
              let ownCode
        else {
            throw TunnelHelperError.callerNotTrusted
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            throw TunnelHelperError.callerNotTrusted
        }
        var rawSigningInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &rawSigningInfo
        ) == errSecSuccess,
            let signingInfo = rawSigningInfo as? [String: Any],
            let teamID = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String,
            teamID.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil
        else {
            throw TunnelHelperError.callerNotTrusted
        }
        let requirement = #"identifier "com.cash.iPhoneLocationMove" and anchor apple generic and certificate leaf[subject.OU] = "\#(teamID)""#
        return CallerTrustPolicy(designatedRequirement: requirement, teamID: teamID)
    }
}

// BEGIN PRODUCTION ENTRY
private let productionCallerVerifier = SecurityCallerCodeVerifier()
private let productionCallerPolicy: CallerTrustPolicy = {
    guard let policy = try? ProductionTrustAnchor.callerPolicy() else {
        exit(EXIT_FAILURE)
    }
    return policy
}()
private let productionInstaller = PinnedTunnelRuntimeInstaller(
    digestTable: ProductionTrustAnchor.digestTable,
    destinationURL: URL(
        fileURLWithPath: "/Library/Application Support/iPhoneLocationMove/TunnelRuntime/current",
        isDirectory: true
    )
)
private let productionManager = TunnelLeaseManager(
    trustPolicy: productionCallerPolicy,
    callerVerifier: productionCallerVerifier,
    runtimeProvider: productionInstaller,
    processLauncher: FoundationTunnelProcessLauncher()
)
private let productionDelegate = TunnelHelperListenerDelegate(
    trustPolicy: productionCallerPolicy,
    callerVerifier: productionCallerVerifier,
    manager: productionManager
)
private let productionListener = NSXPCListener(
    machServiceName: "com.cash.iPhoneLocationMoveTunnelHelper"
)
productionListener.delegate = productionDelegate
productionListener.resume()
RunLoop.main.run()
// END PRODUCTION ENTRY
