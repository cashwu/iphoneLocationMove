#if TUNNEL_HELPER_HARNESS
import CryptoKit
import Darwin
import Foundation

private enum HarnessFailure: Error {
    case assertion(String)
}

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else {
        throw HarnessFailure.assertion(message)
    }
}

private final class FakeCallerVerifier: CallerCodeVerifying {
    var result: Result<VerifiedCaller, TunnelHelperError>
    private(set) var verificationCount = 0

    init(result: Result<VerifiedCaller, TunnelHelperError>) {
        self.result = result
    }

    func verify(
        identity: CallerAuditIdentity,
        policy: CallerTrustPolicy
    ) throws -> VerifiedCaller {
        verificationCount += 1
        return try result.get()
    }
}

private final class FakeRuntimeProvider: TunnelRuntimeProviding {
    var result: Result<InstalledTunnelRuntime, TunnelHelperError>

    init(result: Result<InstalledTunnelRuntime, TunnelHelperError>) {
        self.result = result
    }

    func prepareRuntime(for caller: VerifiedCaller) throws -> InstalledTunnelRuntime {
        try result.get()
    }
}

private final class FakeOfflineRuntimeBuilder: OfflineRuntimeBuilding {
    private(set) var plans: [OfflineRuntimeBuildPlan] = []

    func buildRuntime(
        in stagingURL: URL,
        plan: OfflineRuntimeBuildPlan
    ) throws {
        plans.append(plan)
        let executableURL = stagingURL.appendingPathComponent(plan.executableRelativePath)
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/false\n".utf8).write(to: executableURL)
        guard chmod(executableURL.path, 0o700) == 0 else {
            throw TunnelHelperError.runtimeInstallFailed
        }
    }
}

private final class FakeTunnelProcess: TunnelProcessControlling {
    let processIdentifier: Int32
    var isRunning: Bool
    var terminationStatus: Int32?
    var stderrTail: String
    var stderrByteCount: Int
    var endpointLine: String
    var stopError: TunnelHelperError?
    private(set) var stopCount = 0

    init(
        processIdentifier: Int32,
        isRunning: Bool = true,
        terminationStatus: Int32? = nil,
        stderrTail: String = "",
        stderrByteCount: Int = 0,
        endpointLine: String = "fd00::1 62078"
    ) {
        self.processIdentifier = processIdentifier
        self.isRunning = isRunning
        self.terminationStatus = terminationStatus
        self.stderrTail = stderrTail
        self.stderrByteCount = stderrByteCount
        self.endpointLine = endpointLine
    }

    var diagnostics: TunnelProcessDiagnostics {
        TunnelProcessDiagnostics(
            terminationStatus: terminationStatus,
            stderrTail: stderrTail,
            stderrByteCount: stderrByteCount
        )
    }

    func readEndpointLine(deadline: DispatchTime) throws -> String {
        endpointLine
    }

    func stop() throws {
        stopCount += 1
        if let stopError {
            throw stopError
        }
        isRunning = false
        terminationStatus = 0
    }
}

private final class FakeTunnelLauncher: TunnelProcessLaunching {
    var processFactory: () -> FakeTunnelProcess
    private(set) var launches: [(URL, DeviceID)] = []
    private(set) var processes: [FakeTunnelProcess] = []

    init(processFactory: @escaping () -> FakeTunnelProcess = { FakeTunnelProcess(processIdentifier: 42) }) {
        self.processFactory = processFactory
    }

    func launch(
        runtime: InstalledTunnelRuntime,
        deviceID: DeviceID
    ) throws -> TunnelProcessControlling {
        launches.append((runtime.executableURL, deviceID))
        let process = processFactory()
        processes.append(process)
        return process
    }
}

private final class ControlledTunnelProcess: TunnelProcessControlling {
    let processIdentifier: Int32 = 77
    let readStarted = DispatchSemaphore(value: 0)
    let releaseRead = DispatchSemaphore(value: 0)
    let stopped = DispatchSemaphore(value: 0)

    private let stateLock = NSLock()
    private var running = true
    private var stops = 0
    private(set) var observedDeadline: DispatchTime?

    var isRunning: Bool {
        stateLock.withLock { running }
    }

    var terminationStatus: Int32? {
        stateLock.withLock { running ? nil : 0 }
    }

    var diagnostics: TunnelProcessDiagnostics {
        TunnelProcessDiagnostics(
            terminationStatus: terminationStatus,
            stderrTail: "",
            stderrByteCount: 0
        )
    }

    var stopCount: Int {
        stateLock.withLock { stops }
    }

    func readEndpointLine(deadline: DispatchTime) throws -> String {
        observedDeadline = deadline
        readStarted.signal()
        guard releaseRead.wait(timeout: deadline) == .success else {
            throw TunnelHelperError.handshakeTimeout
        }
        return "fd00::1 62078"
    }

    func stop() throws {
        stateLock.withLock {
            stops += 1
            running = false
        }
        releaseRead.signal()
        stopped.signal()
    }
}

private final class ControlledTunnelLauncher: TunnelProcessLaunching {
    let process: ControlledTunnelProcess
    let launchStarted = DispatchSemaphore(value: 0)
    let releaseLaunch = DispatchSemaphore(value: 0)

    private let stateLock = NSLock()
    private var launchCountStorage = 0
    var blockLaunch = false

    init(process: ControlledTunnelProcess = ControlledTunnelProcess()) {
        self.process = process
    }

    var launchCount: Int {
        stateLock.withLock { launchCountStorage }
    }

    func launch(
        runtime: InstalledTunnelRuntime,
        deviceID: DeviceID
    ) throws -> TunnelProcessControlling {
        stateLock.withLock {
            launchCountStorage += 1
        }
        launchStarted.signal()
        if blockLaunch {
            _ = releaseLaunch.wait(timeout: .now() + 5)
        }
        return process
    }
}

private struct Fixture {
    let root: URL
    let caller: VerifiedCaller
    let identity: CallerAuditIdentity
    let runtime: InstalledTunnelRuntime

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TunnelHelperHarness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        identity = CallerAuditIdentity(
            processIdentifier: 123,
            effectiveUserIdentifier: UInt32(geteuid()),
            auditSessionIdentifier: 456,
            connectionID: UUID()
        )
        caller = VerifiedCaller(
            identity: identity,
            bundleURL: root.appendingPathComponent("Signed.app", isDirectory: true),
            teamID: "TEAM123456",
            designatedRequirement: #"identifier "com.cash.iPhoneLocationMove" and anchor apple generic"#
        )
        runtime = InstalledTunnelRuntime(
            rootURL: root.appendingPathComponent("runtime", isDirectory: true),
            executableURL: root.appendingPathComponent("runtime/bin/pymobiledevice3")
        )
    }
}

private func makeManager(
    fixture: Fixture,
    verifier: FakeCallerVerifier? = nil,
    launcher: FakeTunnelLauncher? = nil
) -> (TunnelLeaseManager, FakeCallerVerifier, FakeTunnelLauncher) {
    let verifier = verifier ?? FakeCallerVerifier(result: .success(fixture.caller))
    let launcher = launcher ?? FakeTunnelLauncher()
    let manager = TunnelLeaseManager(
        trustPolicy: CallerTrustPolicy(
            designatedRequirement: fixture.caller.designatedRequirement,
            teamID: fixture.caller.teamID
        ),
        callerVerifier: verifier,
        runtimeProvider: FakeRuntimeProvider(result: .success(fixture.runtime)),
        processLauncher: launcher
    )
    return (manager, verifier, launcher)
}

private func expectError(
    _ expected: TunnelHelperError.Code,
    operation: () throws -> Void
) throws {
    do {
        try operation()
        throw HarnessFailure.assertion("Expected \(expected.rawValue)")
    } catch let error as TunnelHelperError {
        try require(error.code == expected, "Expected \(expected.rawValue), got \(error.code.rawValue)")
    }
}

private func testCallerTrust() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let verifier = FakeCallerVerifier(result: .failure(.callerNotTrusted))
    let (manager, _, launcher) = makeManager(fixture: fixture, verifier: verifier)

    try expectError(.callerNotTrusted) {
        _ = try manager.startTunnel(
            caller: fixture.identity,
            deviceID: "00008110-001234567890001E",
            idempotencyKey: UUID()
        )
    }
    try require(launcher.launches.isEmpty, "Untrusted caller launched a process")

    verifier.result = .success(
        VerifiedCaller(
            identity: fixture.identity,
            bundleURL: fixture.caller.bundleURL,
            teamID: "OTHERTEAM",
            designatedRequirement: fixture.caller.designatedRequirement
        )
    )
    try expectError(.callerNotTrusted) {
        _ = try manager.reconcile(caller: fixture.identity)
    }

    verifier.result = .success(
        VerifiedCaller(
            identity: fixture.identity,
            bundleURL: fixture.caller.bundleURL,
            teamID: fixture.caller.teamID,
            designatedRequirement: #"identifier "com.attacker.ReSignedApp""#
        )
    )
    try expectError(.callerNotTrusted) {
        _ = try manager.reconcile(caller: fixture.identity)
    }
}

private func testDeviceIdentityOwnershipAndIdempotency() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let (manager, verifier, launcher) = makeManager(fixture: fixture)
    let key = UUID()

    try expectError(.invalidDeviceID) {
        _ = try manager.startTunnel(caller: fixture.identity, deviceID: "--script-mode", idempotencyKey: key)
    }

    let first = try manager.startTunnel(
        caller: fixture.identity,
        deviceID: "00008110-001234567890001E",
        idempotencyKey: key
    )
    let duplicate = try manager.startTunnel(
        caller: fixture.identity,
        deviceID: "00008110-001234567890001E",
        idempotencyKey: key
    )
    try require(first == duplicate, "Idempotent start returned a different lease")
    try require(launcher.launches.count == 1, "Idempotent start launched more than one process")
    try require(verifier.verificationCount == 1, "Connection identity was reverified after accept")
    try expectError(.unknownLease) {
        _ = try manager.status(caller: fixture.identity, leaseID: TunnelLeaseID())
    }

    let intruder = CallerAuditIdentity(
        processIdentifier: 999,
        effectiveUserIdentifier: UInt32(geteuid()),
        auditSessionIdentifier: 999,
        connectionID: UUID()
    )
    verifier.result = .success(
        VerifiedCaller(
            identity: intruder,
            bundleURL: fixture.caller.bundleURL,
            teamID: fixture.caller.teamID,
            designatedRequirement: fixture.caller.designatedRequirement
        )
    )
    try expectError(.leaseNotOwned) {
        _ = try manager.status(caller: intruder, leaseID: first.leaseID)
    }
    try require(launcher.processes[0].isRunning, "Unauthorized status changed process state")

    launcher.processes[0].isRunning = false
    launcher.processes[0].terminationStatus = 9
    try expectError(.processExited) {
        _ = try manager.startTunnel(
            caller: fixture.identity,
            deviceID: "00008110-001234567890001E",
            idempotencyKey: key
        )
    }
    try require(
        launcher.launches.count == 1,
        "Exited active retry unexpectedly launched a replacement process"
    )
}

private func testConnectionIdentityBinding() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let verifier = FakeCallerVerifier(result: .success(fixture.caller))
    let (manager, _, launcher) = makeManager(fixture: fixture, verifier: verifier)

    let invalidIdentities = [
        CallerAuditIdentity(
            processIdentifier: 0,
            effectiveUserIdentifier: fixture.identity.effectiveUserIdentifier,
            auditSessionIdentifier: fixture.identity.auditSessionIdentifier,
            connectionID: UUID()
        ),
        CallerAuditIdentity(
            processIdentifier: fixture.identity.processIdentifier,
            effectiveUserIdentifier: 0,
            auditSessionIdentifier: fixture.identity.auditSessionIdentifier,
            connectionID: UUID()
        ),
        CallerAuditIdentity(
            processIdentifier: fixture.identity.processIdentifier,
            effectiveUserIdentifier: fixture.identity.effectiveUserIdentifier,
            auditSessionIdentifier: -1,
            connectionID: UUID()
        ),
    ]
    for identity in invalidIdentities {
        verifier.result = .success(
            VerifiedCaller(
                identity: identity,
                bundleURL: fixture.caller.bundleURL,
                teamID: fixture.caller.teamID,
                designatedRequirement: fixture.caller.designatedRequirement
            )
        )
        try expectError(.callerNotTrusted) {
            _ = try manager.establishConnection(identity)
        }
    }
    try require(launcher.launches.isEmpty, "Invalid connection identity launched a process")

    verifier.result = .success(fixture.caller)
    _ = try manager.establishConnection(fixture.identity)
    let lease = try manager.startTunnel(
        caller: fixture.identity,
        deviceID: "00008110-001234567890001E",
        idempotencyKey: UUID()
    )
    try require(verifier.verificationCount == 1, "Accepted connection was verified more than once")
    _ = manager.invalidateOwner(fixture.identity)
    try expectError(.callerNotTrusted) {
        _ = try manager.status(caller: fixture.identity, leaseID: lease.leaseID)
    }
    try require(
        verifier.verificationCount == 1,
        "Invalidated connection identity reached PID verification again"
    )

    let nextIdentity = CallerAuditIdentity(
        processIdentifier: fixture.identity.processIdentifier,
        effectiveUserIdentifier: fixture.identity.effectiveUserIdentifier,
        auditSessionIdentifier: fixture.identity.auditSessionIdentifier,
        connectionID: UUID()
    )
    verifier.result = .success(
        VerifiedCaller(
            identity: nextIdentity,
            bundleURL: fixture.caller.bundleURL,
            teamID: fixture.caller.teamID,
            designatedRequirement: fixture.caller.designatedRequirement
        )
    )
    _ = try manager.establishConnection(nextIdentity)
    try require(verifier.verificationCount == 2, "Fresh connectionID was not independently verified")
}

private func testEndpointAndProcessFailures() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var nextProcess = FakeTunnelProcess(processIdentifier: 7, endpointLine: #"{"address":"not an ip","port":0}"#)
    let launcher = FakeTunnelLauncher { nextProcess }
    let (manager, _, _) = makeManager(fixture: fixture, launcher: launcher)

    try expectError(.invalidEndpoint) {
        _ = try manager.startTunnel(
            caller: fixture.identity,
            deviceID: "00008110-001234567890001E",
            idempotencyKey: UUID()
        )
    }
    try require(nextProcess.stopCount == 1, "Invalid endpoint did not stop process")

    nextProcess = FakeTunnelProcess(
        processIdentifier: 8,
        isRunning: false,
        terminationStatus: 12
    )
    try expectError(.processExited) {
        _ = try manager.startTunnel(
            caller: fixture.identity,
            deviceID: "00008110-001234567890001E",
            idempotencyKey: UUID()
        )
    }

    nextProcess = FakeTunnelProcess(processIdentifier: 9)
    nextProcess.stopError = .processStopFailed
    let recoveryKey = UUID()
    let lease = try manager.startTunnel(
        caller: fixture.identity,
        deviceID: "00008110-001234567890001E",
        idempotencyKey: recoveryKey
    )
    try expectError(.processStopFailed) {
        try manager.stopTunnel(caller: fixture.identity, leaseID: lease.leaseID)
    }
    let status = try manager.status(caller: fixture.identity, leaseID: lease.leaseID)
    try require(status.state == .running, "Failed stop discarded cleanup ownership")
    let duplicate = try manager.startTunnel(
        caller: fixture.identity,
        deviceID: "00008110-001234567890001E",
        idempotencyKey: recoveryKey
    )
    try require(duplicate.leaseID == lease.leaseID, "Failed stop replaced the existing tunnel lease")
    try require(launcher.launches.count == 3, "Failed stop launched a second tunnel process")
}

private func testTunnelStatusSnapshotsAndExitedLeaseRemoval() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let process = FakeTunnelProcess(processIdentifier: 10)
    let launcher = FakeTunnelLauncher { process }
    let (manager, _, _) = makeManager(fixture: fixture, launcher: launcher)
    let lease = try manager.startTunnel(
        caller: fixture.identity,
        deviceID: "00008110-001234567890001E",
        idempotencyKey: UUID()
    )

    try require(lease.state == .running, "Start did not return a running snapshot")
    try require(lease.diagnostics.terminationStatus == nil, "Running snapshot has a termination status")
    try require(lease.diagnostics.stderrTail.isEmpty, "Running snapshot has unexpected stderr")
    try require(lease.diagnostics.stderrByteCount == 0, "Running snapshot has unexpected stderr bytes")

    process.stderrTail = "tunnel route vanished"
    process.stderrByteCount = process.stderrTail.utf8.count
    let running = try manager.status(caller: fixture.identity, leaseID: lease.leaseID)
    try require(running.state == .running, "Live process did not return a running snapshot")
    try require(
        running.diagnostics.stderrTail == process.stderrTail,
        "Running snapshot omitted current stderr diagnostics"
    )
    try require(
        running.diagnostics.stderrByteCount == process.stderrByteCount,
        "Running snapshot omitted stderr byte count"
    )

    process.isRunning = false
    process.terminationStatus = 65
    let exited = try manager.status(caller: fixture.identity, leaseID: lease.leaseID)
    try require(exited.state == .exited, "Exited process did not return an exited snapshot")
    try require(exited.diagnostics.terminationStatus == 65, "Exited snapshot omitted termination status")
    try require(
        exited.diagnostics.stderrTail == process.stderrTail,
        "Exited snapshot omitted stderr tail"
    )
    try require(
        exited.diagnostics.stderrByteCount == process.stderrByteCount,
        "Exited snapshot omitted stderr byte count"
    )
    try expectError(.unknownLease) {
        _ = try manager.status(caller: fixture.identity, leaseID: lease.leaseID)
    }
}

private func testFoundationProcessContinuouslyDrainsAndBoundsStderr() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let executableURL = fixture.root.appendingPathComponent("stderr-tunnel")
    let prefix = "stderr-prefix-"
    let bodyByteCount = 100_000
    let suffix = "-LATEST-TAIL-MARKER"
    let script = """
    #!/usr/bin/python3 -Es
    import sys
    sys.stdout.write("fd00::1 62078\\n")
    sys.stdout.flush()
    payload = b"\(prefix)" + (b"x" * \(bodyByteCount)) + b"\(suffix)"
    sys.stderr.buffer.write(payload)
    sys.stderr.buffer.flush()
    raise SystemExit(23)

    """
    try Data(script.utf8).write(to: executableURL)
    guard chmod(executableURL.path, 0o700) == 0 else {
        throw HarnessFailure.assertion("Unable to make stderr fixture executable")
    }

    let process = try FoundationTunnelProcessLauncher().launch(
        runtime: InstalledTunnelRuntime(rootURL: fixture.root, executableURL: executableURL),
        deviceID: try DeviceID(validating: "00008110-001234567890001E")
    )
    _ = try process.readEndpointLine(deadline: .now() + 5)

    let deadline = Date().addingTimeInterval(5)
    while process.isRunning, Date() < deadline {
        usleep(10_000)
    }
    defer { try? process.stop() }
    try require(
        !process.isRunning,
        "Tunnel process remained blocked after writing stderr; stderr was not continuously drained"
    )

    let diagnostics = process.diagnostics
    let expectedByteCount = prefix.utf8.count + bodyByteCount + suffix.utf8.count
    try require(
        diagnostics.stderrByteCount == expectedByteCount,
        "stderr byte count was \(diagnostics.stderrByteCount), expected \(expectedByteCount)"
    )
    try require(
        diagnostics.stderrTail.utf8.count <= 4_096,
        "stderr tail exceeded the 4 KiB contract"
    )
    try require(
        diagnostics.stderrTail.hasSuffix(suffix),
        "stderr tail did not retain the newest process output"
    )
    try require(diagnostics.terminationStatus == 23, "Process termination status was not captured")
}

private func testLaunchEnvironmentProvidesRequiredSystemTools() throws {
    let path = FoundationTunnelProcessLauncher.processEnvironment["PATH"] ?? ""
    let directories = Set(path.split(separator: ":").map(String.init))

    try require(directories.contains("/sbin"), "Tunnel PATH cannot resolve macOS ifconfig")
    try require(directories.contains("/usr/sbin"), "Tunnel PATH omits system administration tools")
    try require(
        FoundationTunnelProcessLauncher.processEnvironment["PYTHONDONTWRITEBYTECODE"] == "1",
        "Tunnel process must not mutate the sealed runtime with Python bytecode caches"
    )
}

private func testInvalidationAndReconcile() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let (manager, verifier, launcher) = makeManager(fixture: fixture)
    _ = try manager.startTunnel(
        caller: fixture.identity,
        deviceID: "00008110-001234567890001E",
        idempotencyKey: UUID()
    )
    let invalidationFailures = manager.invalidateOwner(fixture.identity)
    try require(invalidationFailures.isEmpty, "Owner invalidation failed")
    try require(launcher.processes[0].stopCount == 1, "Owner invalidation did not stop process")

    let oldIdentity = CallerAuditIdentity(
        processIdentifier: 321,
        effectiveUserIdentifier: UInt32(geteuid()),
        auditSessionIdentifier: 654,
        connectionID: UUID()
    )
    verifier.result = .success(
        VerifiedCaller(
            identity: oldIdentity,
            bundleURL: fixture.caller.bundleURL,
            teamID: fixture.caller.teamID,
            designatedRequirement: fixture.caller.designatedRequirement
        )
    )
    _ = try manager.startTunnel(
        caller: oldIdentity,
        deviceID: "00008110-001234567890001E",
        idempotencyKey: UUID()
    )
    let currentIdentity = CallerAuditIdentity(
        processIdentifier: fixture.identity.processIdentifier,
        effectiveUserIdentifier: fixture.identity.effectiveUserIdentifier,
        auditSessionIdentifier: fixture.identity.auditSessionIdentifier,
        connectionID: UUID()
    )
    verifier.result = .success(
        VerifiedCaller(
            identity: currentIdentity,
            bundleURL: fixture.caller.bundleURL,
            teamID: fixture.caller.teamID,
            designatedRequirement: fixture.caller.designatedRequirement
        )
    )
    let report = try manager.reconcile(caller: currentIdentity)
    try require(report.reclaimedLeaseCount == 1, "Reconcile did not reclaim stale owner")
    try require(launcher.processes[1].stopCount == 1, "Reconcile did not stop stale process")
}

private func testPendingStartOwnershipAndDeadline() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let process = ControlledTunnelProcess()
    let launcher = ControlledTunnelLauncher(process: process)
    let manager = TunnelLeaseManager(
        trustPolicy: CallerTrustPolicy(
            designatedRequirement: fixture.caller.designatedRequirement,
            teamID: fixture.caller.teamID
        ),
        callerVerifier: FakeCallerVerifier(result: .success(fixture.caller)),
        runtimeProvider: FakeRuntimeProvider(result: .success(fixture.runtime)),
        processLauncher: launcher,
        endpointTimeout: 0.1
    )
    let key = UUID()
    let resultsLock = NSLock()
    var results: [Result<TunnelLeaseSnapshot, TunnelHelperError>] = []
    let starts = DispatchGroup()

    for _ in 0..<2 {
        starts.enter()
        DispatchQueue.global().async {
            let result: Result<TunnelLeaseSnapshot, TunnelHelperError>
            do {
                result = .success(
                    try manager.startTunnel(
                        caller: fixture.identity,
                        deviceID: "00008110-001234567890001E",
                        idempotencyKey: key
                    )
                )
            } catch let error as TunnelHelperError {
                result = .failure(error)
            } catch {
                result = .failure(.processLaunchFailed)
            }
            resultsLock.withLock {
                results.append(result)
            }
            starts.leave()
        }
    }

    try require(
        process.readStarted.wait(timeout: .now() + 2) == .success,
        "Pending leader never began endpoint I/O"
    )
    usleep(20_000)
    try require(launcher.launchCount == 1, "Same-key pending starts launched more than once")
    process.releaseRead.signal()
    try require(starts.wait(timeout: .now() + 2) == .success, "Pending starts did not finish")
    let snapshots = try results.map { try $0.get() }
    try require(snapshots.count == 2, "Pending start lost a terminal result")
    try require(snapshots[0] == snapshots[1], "Same-key waiters received different results")

    let timeoutProcess = ControlledTunnelProcess()
    let timeoutLauncher = ControlledTunnelLauncher(process: timeoutProcess)
    let timeoutManager = TunnelLeaseManager(
        trustPolicy: CallerTrustPolicy(
            designatedRequirement: fixture.caller.designatedRequirement,
            teamID: fixture.caller.teamID
        ),
        callerVerifier: FakeCallerVerifier(result: .success(fixture.caller)),
        runtimeProvider: FakeRuntimeProvider(result: .success(fixture.runtime)),
        processLauncher: timeoutLauncher,
        endpointTimeout: 0.02
    )
    try expectError(.handshakeTimeout) {
        _ = try timeoutManager.startTunnel(
            caller: fixture.identity,
            deviceID: "00008110-001234567890001E",
            idempotencyKey: UUID()
        )
    }
    try require(timeoutProcess.stopCount == 1, "Endpoint deadline did not stop its process")
    try require(timeoutProcess.observedDeadline != nil, "Endpoint reader did not receive a deadline")
}

private func testPendingInvalidationRacesDoNotHoldConditionDuringIO() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let beforeAttachProcess = ControlledTunnelProcess()
    let beforeAttachLauncher = ControlledTunnelLauncher(process: beforeAttachProcess)
    beforeAttachLauncher.blockLaunch = true
    let beforeAttachManager = TunnelLeaseManager(
        trustPolicy: CallerTrustPolicy(
            designatedRequirement: fixture.caller.designatedRequirement,
            teamID: fixture.caller.teamID
        ),
        callerVerifier: FakeCallerVerifier(result: .success(fixture.caller)),
        runtimeProvider: FakeRuntimeProvider(result: .success(fixture.runtime)),
        processLauncher: beforeAttachLauncher,
        endpointTimeout: 1
    )
    let beforeAttachStart = DispatchGroup()
    beforeAttachStart.enter()
    DispatchQueue.global().async {
        _ = try? beforeAttachManager.startTunnel(
            caller: fixture.identity,
            deviceID: "00008110-001234567890001E",
            idempotencyKey: UUID()
        )
        beforeAttachStart.leave()
    }
    try require(
        beforeAttachLauncher.launchStarted.wait(timeout: .now() + 2) == .success,
        "Launch race fixture did not start"
    )
    _ = beforeAttachManager.invalidateOwner(fixture.identity)
    beforeAttachLauncher.releaseLaunch.signal()
    try require(
        beforeAttachStart.wait(timeout: .now() + 2) == .success,
        "Invalidation before attach left start blocked"
    )
    try require(beforeAttachProcess.stopCount == 1, "Invalidation before attach leaked process")

    let pendingProcess = ControlledTunnelProcess()
    let pendingLauncher = ControlledTunnelLauncher(process: pendingProcess)
    let pendingManager = TunnelLeaseManager(
        trustPolicy: CallerTrustPolicy(
            designatedRequirement: fixture.caller.designatedRequirement,
            teamID: fixture.caller.teamID
        ),
        callerVerifier: FakeCallerVerifier(result: .success(fixture.caller)),
        runtimeProvider: FakeRuntimeProvider(result: .success(fixture.runtime)),
        processLauncher: pendingLauncher,
        endpointTimeout: 5
    )
    let pendingStart = DispatchGroup()
    pendingStart.enter()
    DispatchQueue.global().async {
        _ = try? pendingManager.startTunnel(
            caller: fixture.identity,
            deviceID: "00008110-001234567890001E",
            idempotencyKey: UUID()
        )
        pendingStart.leave()
    }
    try require(
        pendingProcess.readStarted.wait(timeout: .now() + 2) == .success,
        "Endpoint pending race fixture did not start"
    )
    let invalidationBegan = DispatchTime.now()
    _ = pendingManager.invalidateOwner(fixture.identity)
    let invalidationElapsed = Double(
        DispatchTime.now().uptimeNanoseconds - invalidationBegan.uptimeNanoseconds
    ) / 1_000_000_000
    try require(invalidationElapsed < 0.5, "Invalidation waited for endpoint external I/O")
    try require(
        pendingStart.wait(timeout: .now() + 2) == .success,
        "Endpoint-pending invalidation left start blocked"
    )
    try require(pendingProcess.stopCount == 1, "Endpoint-pending invalidation leaked process")

    let activeProcess = ControlledTunnelProcess()
    activeProcess.releaseRead.signal()
    let activeLauncher = ControlledTunnelLauncher(process: activeProcess)
    let activeManager = TunnelLeaseManager(
        trustPolicy: CallerTrustPolicy(
            designatedRequirement: fixture.caller.designatedRequirement,
            teamID: fixture.caller.teamID
        ),
        callerVerifier: FakeCallerVerifier(result: .success(fixture.caller)),
        runtimeProvider: FakeRuntimeProvider(result: .success(fixture.runtime)),
        processLauncher: activeLauncher,
        endpointTimeout: 1
    )
    _ = try activeManager.startTunnel(
        caller: fixture.identity,
        deviceID: "00008110-001234567890001E",
        idempotencyKey: UUID()
    )
    _ = activeManager.invalidateOwner(fixture.identity)
    try require(activeProcess.stopCount == 1, "Invalidation after active transition leaked process")
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func write(_ data: Data, to url: URL, mode: mode_t) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .withoutOverwriting)
    guard chmod(url.path, mode) == 0 else {
        throw HarnessFailure.assertion("chmod failed: \(url.path)")
    }
}

private func testInstallerAndTamperChecks() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let payloadRoot = fixture.caller.bundleURL
        .appendingPathComponent(PinnedTunnelRuntimeInstaller.payloadRelativePath, isDirectory: true)
    let executableData = Data("fixed executable".utf8)
    let entry = EmbeddedPayloadFile(
        relativePath: "bin/pymobiledevice3",
        sha256: sha256(executableData),
        mode: 0o755
    )
    let manifest = TunnelRuntimeManifest(files: [entry])
    let manifestData = try JSONEncoder.sorted.encode(manifest)
    try write(executableData, to: payloadRoot.appendingPathComponent(entry.relativePath), mode: 0o755)
    try write(
        manifestData,
        to: payloadRoot.appendingPathComponent(PinnedTunnelRuntimeInstaller.manifestName),
        mode: 0o644
    )

    let destination = fixture.root.appendingPathComponent("installed", isDirectory: true)
    let installer = PinnedTunnelRuntimeInstaller(
        digestTable: EmbeddedDigestTable(
            manifestSHA256: sha256(manifestData),
            files: [entry],
            executableRelativePath: entry.relativePath
        ),
        destinationURL: destination,
        requiredOwnerID: UInt32(geteuid())
    )
    let runtime = try installer.prepareRuntime(for: fixture.caller)
    try require(runtime.rootURL == destination, "Installer returned wrong runtime root")
    try require(
        FileManager.default.fileExists(atPath: runtime.executableURL.path),
        "Atomic install did not publish executable"
    )
    let leftovers = try FileManager.default.contentsOfDirectory(
        at: destination.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix(".tunnel-runtime-staging-") }
    try require(leftovers.isEmpty, "Atomic install left staging directory")

    guard chmod(runtime.executableURL.path, 0o777) == 0 else {
        throw HarnessFailure.assertion("Unable to tamper mode")
    }
    try expectError(.runtimeIntegrity) {
        _ = try installer.prepareRuntime(for: fixture.caller)
    }

    try FileManager.default.removeItem(at: destination)
    try FileManager.default.removeItem(at: payloadRoot.appendingPathComponent(entry.relativePath))
    try FileManager.default.createSymbolicLink(
        at: payloadRoot.appendingPathComponent(entry.relativePath),
        withDestinationURL: URL(fileURLWithPath: "/bin/echo")
    )
    try expectError(.runtimeIntegrity) {
        _ = try installer.prepareRuntime(for: fixture.caller)
    }

    try FileManager.default.removeItem(
        at: payloadRoot.appendingPathComponent(entry.relativePath)
    )
    try write(
        executableData,
        to: payloadRoot.appendingPathComponent(entry.relativePath),
        mode: 0o755
    )
    let wrongOwnerPolicy = PinnedTunnelRuntimeInstaller(
        digestTable: EmbeddedDigestTable(
            manifestSHA256: sha256(manifestData),
            files: [entry],
            executableRelativePath: entry.relativePath
        ),
        destinationURL: fixture.root.appendingPathComponent("wrong-owner", isDirectory: true),
        requiredOwnerID: UInt32(geteuid()) &+ 1
    )
    try expectError(.runtimeIntegrity) {
        _ = try wrongOwnerPolicy.prepareRuntime(for: fixture.caller)
    }
}

private func testEmbeddedManifestRejectsSimultaneousReplacement() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let payloadRoot = fixture.caller.bundleURL
        .appendingPathComponent(PinnedTunnelRuntimeInstaller.payloadRelativePath, isDirectory: true)
    let trustedData = Data("trusted".utf8)
    let trustedEntry = EmbeddedPayloadFile(
        relativePath: "bin/pymobiledevice3",
        sha256: sha256(trustedData),
        mode: 0o755
    )
    let trustedManifest = try JSONEncoder.sorted.encode(TunnelRuntimeManifest(files: [trustedEntry]))
    let replacementData = Data("replacement".utf8)
    let replacementEntry = EmbeddedPayloadFile(
        relativePath: trustedEntry.relativePath,
        sha256: sha256(replacementData),
        mode: trustedEntry.mode
    )
    let replacementManifest = try JSONEncoder.sorted.encode(TunnelRuntimeManifest(files: [replacementEntry]))
    try write(replacementData, to: payloadRoot.appendingPathComponent(replacementEntry.relativePath), mode: 0o755)
    try write(
        replacementManifest,
        to: payloadRoot.appendingPathComponent(PinnedTunnelRuntimeInstaller.manifestName),
        mode: 0o644
    )

    let installer = PinnedTunnelRuntimeInstaller(
        digestTable: EmbeddedDigestTable(
            manifestSHA256: sha256(trustedManifest),
            files: [trustedEntry],
            executableRelativePath: trustedEntry.relativePath
        ),
        destinationURL: fixture.root.appendingPathComponent("installed", isDirectory: true),
        requiredOwnerID: UInt32(geteuid())
    )
    try expectError(.runtimeIntegrity) {
        _ = try installer.prepareRuntime(for: fixture.caller)
    }
}

private func testOfflineWheelhouseBuildsPinnedRuntime() throws {
    let fixture = try Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let payloadRoot = fixture.caller.bundleURL
        .appendingPathComponent(PinnedTunnelRuntimeInstaller.payloadRelativePath, isDirectory: true)
    let wheelData = Data("signed wheel bytes".utf8)
    let entry = EmbeddedPayloadFile(
        relativePath: "pymobiledevice3-9.36.3-py3-none-any.whl",
        sha256: sha256(wheelData),
        mode: 0o600
    )
    let manifestData = try JSONEncoder.sorted.encode(TunnelRuntimeManifest(files: [entry]))
    try write(wheelData, to: payloadRoot.appendingPathComponent(entry.relativePath), mode: 0o644)
    try write(
        manifestData,
        to: payloadRoot.appendingPathComponent(PinnedTunnelRuntimeInstaller.manifestName),
        mode: 0o644
    )

    let builder = FakeOfflineRuntimeBuilder()
    let destination = fixture.root.appendingPathComponent("wheel-runtime", isDirectory: true)
    let plan = OfflineRuntimeBuildPlan(
        requirement: "pymobiledevice3==9.36.3",
        executableRelativePath: "runtime/pymobiledevice3"
    )
    let installer = PinnedTunnelRuntimeInstaller(
        digestTable: EmbeddedDigestTable(
            manifestSHA256: sha256(manifestData),
            files: [entry],
            buildPlan: plan
        ),
        destinationURL: destination,
        requiredOwnerID: UInt32(geteuid()),
        runtimeBuilder: builder
    )

    let runtime = try installer.prepareRuntime(for: fixture.caller)

    try require(builder.plans == [plan], "Pinned runtime builder was not called exactly once")
    try require(
        runtime.executableURL.path.hasSuffix(plan.executableRelativePath),
        "Installer did not publish the generated executable"
    )
    try require(
        FileManager.default.fileExists(atPath: runtime.executableURL.path),
        "Generated runtime executable is missing"
    )

    let sealURL = destination.appendingPathComponent(PinnedTunnelRuntimeInstaller.sealName)
    let sealData = try Data(contentsOf: sealURL)
    let seal = try JSONDecoder().decode(RuntimeSealManifest.self, from: sealData)
    let sealedPaths = seal.files.map(\.relativePath)
    try require(sealedPaths == sealedPaths.sorted(), "Runtime seal paths are not canonical")
    try require(
        seal.files.allSatisfy { $0.ownerID == UInt32(geteuid()) },
        "Runtime seal did not record file ownership"
    )
    var sealInfo = stat()
    try require(
        lstat(sealURL.path, &sealInfo) == 0 && sealInfo.st_mode & 0o777 == 0o600,
        "Runtime seal is not mode 0600"
    )

    func reinstall() throws -> InstalledTunnelRuntime {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        return try installer.prepareRuntime(for: fixture.caller)
    }

    try FileManager.default.removeItem(at: runtime.executableURL)
    try expectError(.runtimeIntegrity) {
        _ = try installer.prepareRuntime(for: fixture.caller)
    }

    let restored = try reinstall()
    let extraURL = restored.rootURL.appendingPathComponent("runtime/extra.py")
    try write(Data("extra".utf8), to: extraURL, mode: 0o600)
    try expectError(.runtimeIntegrity) {
        _ = try installer.prepareRuntime(for: fixture.caller)
    }

    let symlinkRuntime = try reinstall()
    try FileManager.default.removeItem(at: symlinkRuntime.executableURL)
    try FileManager.default.createSymbolicLink(
        at: symlinkRuntime.executableURL,
        withDestinationURL: URL(fileURLWithPath: "/bin/echo")
    )
    try expectError(.runtimeIntegrity) {
        _ = try installer.prepareRuntime(for: fixture.caller)
    }

    let modeRuntime = try reinstall()
    guard chmod(modeRuntime.executableURL.path, 0o777) == 0 else {
        throw HarnessFailure.assertion("Unable to tamper generated runtime mode")
    }
    try expectError(.runtimeIntegrity) {
        _ = try installer.prepareRuntime(for: fixture.caller)
    }

    let digestRuntime = try reinstall()
    try Data("#!/bin/true\n".utf8).write(to: digestRuntime.executableURL)
    guard chmod(digestRuntime.executableURL.path, 0o700) == 0 else {
        throw HarnessFailure.assertion("Unable to restore generated runtime mode")
    }
    try expectError(.runtimeIntegrity) {
        _ = try installer.prepareRuntime(for: fixture.caller)
    }

    _ = try reinstall()
    guard chmod(destination.appendingPathComponent(PinnedTunnelRuntimeInstaller.sealName).path, 0o644) == 0 else {
        throw HarnessFailure.assertion("Unable to tamper runtime seal mode")
    }
    try expectError(.runtimeIntegrity) {
        _ = try installer.prepareRuntime(for: fixture.caller)
    }
}

@main
private enum TunnelHelperHarness {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else {
                throw HarnessFailure.assertion("Missing scenario")
            }
            switch CommandLine.arguments[1] {
            case "caller-trust":
                try testCallerTrust()
            case "lease":
                try testDeviceIdentityOwnershipAndIdempotency()
            case "connection-identity":
                try testConnectionIdentityBinding()
            case "process":
                try testEndpointAndProcessFailures()
            case "status-diagnostics":
                try testTunnelStatusSnapshotsAndExitedLeaseRemoval()
            case "stderr-drain":
                try testFoundationProcessContinuouslyDrainsAndBoundsStderr()
            case "launch-environment":
                try testLaunchEnvironmentProvidesRequiredSystemTools()
            case "cleanup":
                try testInvalidationAndReconcile()
            case "pending":
                try testPendingStartOwnershipAndDeadline()
            case "pending-invalidation":
                try testPendingInvalidationRacesDoNotHoldConditionDuringIO()
            case "installer":
                try testInstallerAndTamperChecks()
            case "manifest":
                try testEmbeddedManifestRejectsSimultaneousReplacement()
            case "wheelhouse":
                try testOfflineWheelhouseBuildsPinnedRuntime()
            default:
                throw HarnessFailure.assertion("Unknown scenario")
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}

#else
import Foundation
import XCTest

final class TunnelHelperContractTests: XCTestCase {
    // XCTest serializes this class's setUp/tearDown lifecycle around its tests.
    nonisolated(unsafe) private static var harnessURL: URL!
    nonisolated(unsafe) private static var buildDirectory: URL!

    override class func setUp() {
        super.setUp()
        do {
            let projectRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            buildDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("TunnelHelperContractTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
            harnessURL = buildDirectory.appendingPathComponent("TunnelHelperHarness")
            let helperSourceURL = projectRoot
                .appendingPathComponent("iPhoneLocationMoveTunnelHelper/main.swift")
            let source = try String(contentsOf: helperSourceURL, encoding: .utf8)
            guard let entryStart = source.range(of: "// BEGIN PRODUCTION ENTRY"),
                  let entryEnd = source.range(of: "// END PRODUCTION ENTRY"),
                  entryStart.lowerBound < entryEnd.upperBound
            else {
                throw NSError(
                    domain: "TunnelHelperContractTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Production entry markers are missing"]
                )
            }
            var contractSource = source
            contractSource.removeSubrange(entryStart.lowerBound..<entryEnd.upperBound)
            let contractSourceURL = buildDirectory.appendingPathComponent("TunnelHelperCore.swift")
            try contractSource.write(to: contractSourceURL, atomically: true, encoding: .utf8)

            let compiler = Process()
            compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            compiler.arguments = [
                "swiftc",
                "-parse-as-library",
                "-D", "TUNNEL_HELPER_CONTRACT_TESTING",
                "-D", "TUNNEL_HELPER_HARNESS",
                contractSourceURL.path,
                #filePath,
                "-o", harnessURL.path
            ]
            let errorPipe = Pipe()
            compiler.standardError = errorPipe
            var environment = ProcessInfo.processInfo.environment
            environment["CLANG_MODULE_CACHE_PATH"] = buildDirectory
                .appendingPathComponent("clang-module-cache", isDirectory: true)
                .path
            environment["SWIFT_MODULE_CACHE_PATH"] = buildDirectory
                .appendingPathComponent("swift-module-cache", isDirectory: true)
                .path
            compiler.environment = environment
            try compiler.run()
            compiler.waitUntilExit()
            let compilerError = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            XCTAssertEqual(compiler.terminationStatus, 0, compilerError)
        } catch {
            XCTFail("Unable to build tunnel helper harness: \(error)")
        }
    }

    override class func tearDown() {
        if let buildDirectory {
            try? FileManager.default.removeItem(at: buildDirectory)
        }
        super.tearDown()
    }

    func testRejectsInvalidCallerSignatureDesignatedRequirementAndTeamID() throws {
        try run("caller-trust")
    }

    func testValidatesDeviceOwnershipAndIdempotentStart() throws {
        try run("lease")
    }

    func testConnectionIdentityIsVerifiedOnceAndCannotBeReusedAfterInvalidation() throws {
        try run("connection-identity")
    }

    func testParsesEndpointAndReportsProcessExitAndStopFailure() throws {
        try run("process")
    }

    func testReportsRunningAndExitedDiagnosticsThenRemovesExitedLease() throws {
        try run("status-diagnostics")
    }

    func testContinuouslyDrainsAndRetainsBoundedStderrTail() throws {
        try run("stderr-drain")
    }

    func testLaunchEnvironmentProvidesRequiredSystemTools() throws {
        try run("launch-environment")
    }

    func testInvalidationAndReconcileReclaimOwnedProcesses() throws {
        try run("cleanup")
    }

    func testPendingStartSharesTerminalResultAndEnforcesDeadline() throws {
        try run("pending")
    }

    func testPendingInvalidationRacesDoNotHoldConditionDuringExternalIO() throws {
        try run("pending-invalidation")
    }

    func testInstallerRejectsSymlinkModeDigestTamperAndPublishesAtomically() throws {
        try run("installer")
    }

    func testEmbeddedDigestRejectsPayloadAndManifestReplacement() throws {
        try run("manifest")
    }

    func testOfflineWheelhouseBuildsPinnedRuntime() throws {
        try run("wheelhouse")
    }

    private func run(_ scenario: String) throws {
        let process = Process()
        process.executableURL = Self.harnessURL
        process.arguments = [scenario]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let error = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, error)
    }
}
#endif
