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
        case handshakeTimeout
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
    static let handshakeTimeout = Self(
        code: .handshakeTimeout,
        detail: "The tunnel process did not return an RSD endpoint within 15 seconds."
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

struct RuntimeSealFile: Codable, Equatable {
    let relativePath: String
    let sha256: String
    let ownerID: UInt32
    let mode: UInt16
}

struct RuntimeSealManifest: Codable, Equatable {
    let files: [RuntimeSealFile]
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
    static let sealName = "runtime-seal.json"

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
                try writeRuntimeSeal(at: staging)
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

        if digestTable.buildPlan != nil {
            try validateRuntimeSeal(at: root)
        }

        guard let installedPaths = try? fileManager.subpathsOfDirectory(atPath: root.path) else {
            throw TunnelHelperError.runtimeIntegrity
        }
        for relativePath in installedPaths {
            let isSealedPath = digestTable.buildPlan != nil
                && relativePath == Self.sealName
            let isGeneratedRuntime = digestTable.buildPlan != nil
                && (relativePath == "runtime" || relativePath.hasPrefix("runtime/"))
            guard expectedPaths.contains(relativePath) || isGeneratedRuntime || isSealedPath else {
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

    private func writeRuntimeSeal(at root: URL) throws {
        let files = try runtimeSealFiles(at: root)
        let seal = RuntimeSealManifest(files: files)
        let data = try JSONEncoder.sorted.encode(seal)
        let sealURL = root.appendingPathComponent(Self.sealName)
        try data.write(to: sealURL, options: .withoutOverwriting)
        try setMode(0o600, at: sealURL)
    }

    private func validateRuntimeSeal(at root: URL) throws {
        let sealURL = root.appendingPathComponent(Self.sealName)
        try verifyMetadata(sealURL, exactMode: 0o600)
        let sealData = try secureRead(sealURL)
        guard let seal = try? JSONDecoder().decode(RuntimeSealManifest.self, from: sealData),
              !seal.files.isEmpty,
              seal.files.map(\.relativePath) == seal.files.map(\.relativePath).sorted(),
              Set(seal.files.map(\.relativePath)).count == seal.files.count
        else {
            throw integrityError("Generated runtime seal is malformed.")
        }

        let actualFiles = try runtimeSealFiles(at: root)
        guard actualFiles == seal.files else {
            throw integrityError("Generated runtime file set does not match its seal.")
        }

        var expectedPaths = Set([Self.sealName])
        for file in seal.files {
            expectedPaths.insert(file.relativePath)
            let parentComponents = file.relativePath.split(separator: "/").dropLast()
            for index in parentComponents.indices {
                expectedPaths.insert(
                    parentComponents[parentComponents.startIndex...index].joined(separator: "/")
                )
            }
        }
        guard let installedPaths = try? fileManager.subpathsOfDirectory(atPath: root.path),
              Set(installedPaths) == expectedPaths
        else {
            throw integrityError("Generated runtime contains missing or extra paths.")
        }
    }

    private func runtimeSealFiles(at root: URL) throws -> [RuntimeSealFile] {
        guard let relativePaths = try? fileManager.subpathsOfDirectory(atPath: root.path) else {
            throw TunnelHelperError.runtimeIntegrity
        }
        var files: [RuntimeSealFile] = []
        for relativePath in relativePaths.sorted() where relativePath != Self.sealName {
            let url = try confinedURL(root: root, relativePath: relativePath)
            var info = stat()
            guard lstat(url.path, &info) == 0,
                  info.st_mode & S_IFMT != S_IFLNK,
                  info.st_uid == requiredOwnerID,
                  info.st_mode & 0o022 == 0
            else {
                throw integrityError("Generated runtime metadata mismatch: \(relativePath)")
            }
            if info.st_mode & S_IFMT == S_IFDIR {
                continue
            }
            guard info.st_mode & S_IFMT == S_IFREG else {
                throw integrityError("Generated runtime contains a non-regular file: \(relativePath)")
            }
            let data = try secureRead(url)
            files.append(
                RuntimeSealFile(
                    relativePath: relativePath,
                    sha256: Self.digest(data),
                    ownerID: info.st_uid,
                    mode: UInt16(info.st_mode & 0o777)
                )
            )
        }
        return files
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
    func readEndpointLine(deadline: DispatchTime) throws -> String
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

    func readEndpointLine(deadline: DispatchTime) throws -> String {
        var data = Data()
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline.uptimeNanoseconds else {
                throw TunnelHelperError.handshakeTimeout
            }
            let remainingNanoseconds = deadline.uptimeNanoseconds - now
            let remainingMilliseconds = max(
                1,
                min(Int32.max, Int32(remainingNanoseconds / 1_000_000))
            )
            var descriptor = pollfd(
                fd: output.fileDescriptor,
                events: Int16(POLLIN | POLLHUP),
                revents: 0
            )
            let pollResult = Darwin.poll(&descriptor, 1, remainingMilliseconds)
            if pollResult == 0 {
                throw TunnelHelperError.handshakeTimeout
            }
            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                throw TunnelHelperError.processExited
            }
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
        "PYTHONDONTWRITEBYTECODE": "1",
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

struct TunnelStartKey: Hashable {
    let connectionID: UUID
    let deviceID: DeviceID
    let idempotencyKey: UUID
}

private final class PendingTunnelStart {
    let key: TunnelStartKey
    let owner: CallerAuditIdentity
    var process: TunnelProcessControlling?
    var cancelled = false
    var terminalResult: Result<TunnelLeaseSnapshot, TunnelHelperError>?

    init(key: TunnelStartKey, owner: CallerAuditIdentity) {
        self.key = key
        self.owner = owner
    }
}

private final class TunnelLease {
    let key: TunnelStartKey
    let owner: CallerAuditIdentity
    let snapshot: TunnelLeaseSnapshot
    let process: TunnelProcessControlling

    init(
        key: TunnelStartKey,
        owner: CallerAuditIdentity,
        snapshot: TunnelLeaseSnapshot,
        process: TunnelProcessControlling
    ) {
        self.key = key
        self.owner = owner
        self.snapshot = snapshot
        self.process = process
    }
}

final class TunnelLeaseManager: @unchecked Sendable {
    private let trustPolicy: CallerTrustPolicy
    private let callerVerifier: CallerCodeVerifying
    private let runtimeProvider: TunnelRuntimeProviding
    private let processLauncher: TunnelProcessLaunching
    private let endpointTimeout: TimeInterval
    private let condition = NSCondition()
    private var verifiedConnections: [UUID: VerifiedCaller] = [:]
    private var invalidatedConnectionIDs: Set<UUID> = []
    private var pendingStarts: [TunnelStartKey: PendingTunnelStart] = [:]
    private var leasesByID: [TunnelLeaseID: TunnelLease] = [:]
    private var leaseIDsByKey: [TunnelStartKey: TunnelLeaseID] = [:]

    init(
        trustPolicy: CallerTrustPolicy,
        callerVerifier: CallerCodeVerifying,
        runtimeProvider: TunnelRuntimeProviding,
        processLauncher: TunnelProcessLaunching,
        endpointTimeout: TimeInterval = 15
    ) {
        self.trustPolicy = trustPolicy
        self.callerVerifier = callerVerifier
        self.runtimeProvider = runtimeProvider
        self.processLauncher = processLauncher
        self.endpointTimeout = endpointTimeout
    }

    func startTunnel(
        caller identity: CallerAuditIdentity,
        deviceID rawDeviceID: String,
        idempotencyKey: UUID
    ) throws -> TunnelLeaseSnapshot {
        let caller = try verifyCaller(identity)
        let deviceID = try DeviceID(validating: rawDeviceID)
        let key = TunnelStartKey(
            connectionID: caller.identity.connectionID,
            deviceID: deviceID,
            idempotencyKey: idempotencyKey
        )

        condition.lock()
        if let leaseID = leaseIDsByKey[key], let lease = leasesByID[leaseID] {
            condition.unlock()
            guard lease.process.isRunning else {
                condition.lock()
                if leasesByID[leaseID] === lease {
                    removeLease(leaseID)
                }
                condition.unlock()
                throw TunnelHelperError.processExited
            }
            return lease.snapshot
        }
        if let pending = pendingStarts[key] {
            while pending.terminalResult == nil {
                condition.wait()
            }
            let result = pending.terminalResult!
            condition.unlock()
            return try result.get()
        }
        let pending = PendingTunnelStart(key: key, owner: caller.identity)
        pendingStarts[key] = pending
        condition.unlock()

        let process: TunnelProcessControlling
        do {
            let runtime = try runtimeProvider.prepareRuntime(for: caller)
            process = try processLauncher.launch(runtime: runtime, deviceID: deviceID)
        } catch let error as TunnelHelperError {
            return try finishPendingFailure(pending, error: error)
        } catch {
            return try finishPendingFailure(pending, error: .processLaunchFailed)
        }

        condition.lock()
        let wasCancelled = pending.cancelled || pendingStarts[key] !== pending
        if !wasCancelled {
            pending.process = process
        }
        let cancelledResult = pending.terminalResult
        condition.unlock()
        if wasCancelled {
            try? process.stop()
            if let cancelledResult {
                return try cancelledResult.get()
            }
            return try finishPendingFailure(pending, error: ownerInvalidatedError)
        }

        do {
            let deadline = DispatchTime.now() + endpointTimeout
            let endpoint = try parseEndpoint(process.readEndpointLine(deadline: deadline))
            guard process.isRunning else {
                throw TunnelHelperError(
                    code: .processExited,
                    detail: "The tunnel process exited with status \(process.terminationStatus ?? -1)."
                )
            }
            let snapshot = TunnelLeaseSnapshot(
                leaseID: TunnelLeaseID(),
                deviceID: deviceID,
                endpoint: endpoint,
                state: .running,
                diagnostics: process.diagnostics
            )
            condition.lock()
            guard !pending.cancelled, pendingStarts[key] === pending else {
                let result = pending.terminalResult
                condition.unlock()
                try? process.stop()
                if let result {
                    return try result.get()
                }
                return try finishPendingFailure(pending, error: ownerInvalidatedError)
            }
            let lease = TunnelLease(
                key: key,
                owner: caller.identity,
                snapshot: snapshot,
                process: process
            )
            leasesByID[snapshot.leaseID] = lease
            leaseIDsByKey[key] = snapshot.leaseID
            pending.process = nil
            pending.terminalResult = .success(snapshot)
            pendingStarts.removeValue(forKey: key)
            condition.broadcast()
            condition.unlock()
            return snapshot
        } catch let error as TunnelHelperError {
            return try finishPendingFailure(pending, error: error)
        } catch {
            return try finishPendingFailure(pending, error: .processExited)
        }
    }

    @discardableResult
    func establishConnection(_ identity: CallerAuditIdentity) throws -> VerifiedCaller {
        try verifyCaller(identity)
    }

    func stopTunnel(
        caller identity: CallerAuditIdentity,
        leaseID: TunnelLeaseID
    ) throws {
        let caller = try verifyCaller(identity)
        condition.lock()
        let lease: TunnelLease
        do {
            lease = try ownedLease(leaseID, caller: caller.identity)
        } catch {
            condition.unlock()
            throw error
        }
        condition.unlock()
        do {
            try lease.process.stop()
        } catch {
            throw TunnelHelperError.processStopFailed
        }
        condition.lock()
        removeLease(leaseID)
        condition.unlock()
    }

    func status(
        caller identity: CallerAuditIdentity,
        leaseID: TunnelLeaseID
    ) throws -> TunnelLeaseSnapshot {
        let caller = try verifyCaller(identity)
        condition.lock()
        let lease: TunnelLease
        do {
            lease = try ownedLease(leaseID, caller: caller.identity)
        } catch {
            condition.unlock()
            throw error
        }
        condition.unlock()
        let snapshot = makeSnapshot(for: lease)
        if snapshot.state == .exited {
            condition.lock()
            removeLease(leaseID)
            condition.unlock()
        }
        return snapshot
    }

    func reconcile(caller identity: CallerAuditIdentity) throws -> ReconcileReport {
        let caller = try verifyCaller(identity)
        condition.lock()
        let staleLeases = leasesByID.compactMap { leaseID, lease in
            lease.owner == caller.identity ? nil : (leaseID, lease)
        }
        condition.unlock()
        var reclaimed = 0
        var failures: [TunnelHelperError] = []
        for (leaseID, lease) in staleLeases {
            do {
                try lease.process.stop()
                condition.lock()
                removeLease(leaseID)
                condition.unlock()
                reclaimed += 1
            } catch {
                failures.append(.processStopFailed)
            }
        }
        return ReconcileReport(reclaimedLeaseCount: reclaimed, failures: failures)
    }

    @discardableResult
    func invalidateOwner(_ identity: CallerAuditIdentity) -> [TunnelHelperError] {
        condition.lock()
        verifiedConnections.removeValue(forKey: identity.connectionID)
        invalidatedConnectionIDs.insert(identity.connectionID)
        let ownedPending = pendingStarts.values.filter { $0.owner == identity }
        let pendingProcesses = ownedPending.compactMap { pending -> TunnelProcessControlling? in
            pending.cancelled = true
            defer { pending.process = nil }
            return pending.process
        }
        let ownedLeases = leasesByID.compactMap { leaseID, lease in
            lease.owner == identity ? (leaseID, lease) : nil
        }
        condition.unlock()

        var failures: [TunnelHelperError] = []
        for process in pendingProcesses {
            do {
                try process.stop()
            } catch {
                failures.append(.processStopFailed)
            }
        }
        for (leaseID, lease) in ownedLeases {
            do {
                try lease.process.stop()
                condition.lock()
                removeLease(leaseID)
                condition.unlock()
            } catch {
                failures.append(.processStopFailed)
            }
        }

        condition.lock()
        for pending in ownedPending where pending.terminalResult == nil {
            pending.terminalResult = .failure(ownerInvalidatedError)
            if pendingStarts[pending.key] === pending {
                pendingStarts.removeValue(forKey: pending.key)
            }
        }
        condition.broadcast()
        condition.unlock()
        return failures
    }

    private func verifyCaller(_ identity: CallerAuditIdentity) throws -> VerifiedCaller {
        guard identity.processIdentifier > 1,
              identity.effectiveUserIdentifier > 0,
              identity.auditSessionIdentifier >= 0
        else {
            throw TunnelHelperError.callerNotTrusted
        }

        condition.lock()
        if invalidatedConnectionIDs.contains(identity.connectionID) {
            condition.unlock()
            throw TunnelHelperError.callerNotTrusted
        }
        if let caller = verifiedConnections[identity.connectionID] {
            condition.unlock()
            guard caller.identity == identity else {
                throw TunnelHelperError.callerNotTrusted
            }
            return caller
        }
        condition.unlock()

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

        condition.lock()
        defer { condition.unlock() }
        guard !invalidatedConnectionIDs.contains(identity.connectionID) else {
            throw TunnelHelperError.callerNotTrusted
        }
        if let existing = verifiedConnections[identity.connectionID] {
            guard existing == caller else {
                throw TunnelHelperError.callerNotTrusted
            }
            return existing
        }
        verifiedConnections[identity.connectionID] = caller
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
        guard lease.owner == caller else {
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

    private var ownerInvalidatedError: TunnelHelperError {
        TunnelHelperError(
            code: .processExited,
            detail: "The owning caller connection was invalidated."
        )
    }

    private func finishPendingFailure(
        _ pending: PendingTunnelStart,
        error: TunnelHelperError
    ) throws -> TunnelLeaseSnapshot {
        condition.lock()
        if let terminal = pending.terminalResult {
            condition.unlock()
            return try terminal.get()
        }
        let process = pending.process
        pending.process = nil
        condition.unlock()
        try? process?.stop()

        condition.lock()
        if pending.terminalResult == nil {
            pending.terminalResult = .failure(error)
        }
        if pendingStarts[pending.key] === pending {
            pendingStarts.removeValue(forKey: pending.key)
        }
        let terminal = pending.terminalResult!
        condition.broadcast()
        condition.unlock()
        return try terminal.get()
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
    private let manager: TunnelLeaseManager
    private let lock = NSLock()
    private var services: [ObjectIdentifier: TunnelHelperXPCService] = [:]

    init(manager: TunnelLeaseManager) {
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
        guard (try? manager.establishConnection(caller)) != nil else {
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
    manager: productionManager
)
private let productionListener = NSXPCListener(
    machServiceName: "com.cash.iPhoneLocationMoveTunnelHelper"
)
productionListener.delegate = productionDelegate
productionListener.resume()
RunLoop.main.run()
// END PRODUCTION ENTRY
