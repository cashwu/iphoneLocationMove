import Foundation

struct DeviceTunnelLeaseID: RawRepresentable, Equatable, Hashable, Sendable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct DeviceTunnelEndpoint: Equatable, Sendable {
    let address: String
    let port: Int
}

struct DeviceTunnelLease: Equatable, Sendable {
    let id: DeviceTunnelLeaseID
    let deviceID: DeviceID
    let endpoint: DeviceTunnelEndpoint
}

enum DVTLocationCommand: Equatable, Sendable {
    case set(requestID: DeviceRequestID, coordinate: DeviceCoordinate)
    case clear(requestID: DeviceRequestID)

    var requestID: DeviceRequestID {
        switch self {
        case let .set(requestID, _), let .clear(requestID):
            requestID
        }
    }
}

struct DVTLocationReply: Equatable, Sendable {
    let requestID: DeviceRequestID
}

protocol PymobiledeviceBoundary: Sendable {
    func inspectRuntime() async -> RuntimeAvailability
    func discoverUSBDevices(runtime: RuntimeInstallation) async throws -> [USBDevice]
    func verifyTrust(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws
    func verifyDeveloperMode(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws
    func prepareDeveloperDiskImage(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws
    func startTunnel(
        for device: USBDevice,
        idempotencyKey: UUID
    ) async throws -> DeviceTunnelLease
    func startDVT(
        runtime: RuntimeInstallation,
        lease: DeviceTunnelLease,
        generation: DeviceSessionGeneration
    ) async throws
    func sendDVT(
        _ command: DVTLocationCommand,
        generation: DeviceSessionGeneration
    ) async throws -> DVTLocationReply
    func shutdownDVT(generation: DeviceSessionGeneration) async throws
    func stopTunnel(_ lease: DeviceTunnelLease) async throws
    func reconcileTunnels() async throws
}

private actor DeviceMutationQueue {
    private var tail: Task<Void, Never>?

    func perform<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let predecessor = tail
        let task = Task {
            if let predecessor {
                await predecessor.value
            }
            return try await operation()
        }
        tail = Task {
            _ = try? await task.value
        }
        return try await task.value
    }
}

actor PymobiledeviceAdapter: DeviceLocationClient {
    private let boundary: any PymobiledeviceBoundary
    private let mutationQueue = DeviceMutationQueue()
    private let diagnosticLogger: any DiagnosticLogging

    private var generation = DeviceSessionGeneration(rawValue: 0)
    private var runtime: RuntimeInstallation?
    private var session: PreparedDeviceSession?
    private var tunnelLease: DeviceTunnelLease?
    private var disconnectedDeviceID: DeviceID?
    private var activeSimulationSessionID: SimulationSessionID?

    private(set) var state: DeviceSessionState = .disconnected
    private(set) var selectedDevice: USBDevice?

    init(
        boundary: any PymobiledeviceBoundary,
        diagnosticLogger: any DiagnosticLogging = NullDiagnosticLogger()
    ) {
        self.boundary = boundary
        self.diagnosticLogger = diagnosticLogger
    }

    static func live() throws -> PymobiledeviceAdapter {
        let configuration = try RuntimeManager.Configuration.live()
        let processRunner = FoundationRuntimeProcessRunner()
        let runtimeManager = RuntimeManager(
            configuration: configuration,
            processRunner: processRunner
        )
        let diagnosticLogger = DiagnosticLogger.shared
        return PymobiledeviceAdapter(
            boundary: LivePymobiledeviceBoundary(
                runtimeManager: runtimeManager,
                processRunner: processRunner,
                tunnelClient: LiveTunnelClient(),
                diagnosticLogger: diagnosticLogger
            ),
            diagnosticLogger: diagnosticLogger
        )
    }

    func discoverUSBDevices() async throws -> [USBDevice] {
        let runtime = try await requireRuntime()
        return try await boundary.discoverUSBDevices(runtime: runtime)
    }

    func prepare(deviceID: DeviceID) async throws -> PreparedDeviceSession {
        try await connect(selectedDeviceID: deviceID)
    }

    func connect(
        selectedDeviceID: DeviceID? = nil
    ) async throws -> PreparedDeviceSession {
        if let session {
            guard let selectedDeviceID,
                  selectedDeviceID != session.device.id
            else {
                return session
            }
            return try await switchDevice(to: selectedDeviceID)
        }
        return try await prepareSession(
            selectedDeviceID: selectedDeviceID,
            publishReady: true
        )
    }

    func reconnect() async throws -> PreparedDeviceSession {
        guard let disconnectedDeviceID else {
            throw DeviceLocationError.usbDisconnected
        }

        let newSession = try await prepareSession(
            selectedDeviceID: disconnectedDeviceID,
            publishReady: false
        )
        do {
            try await sendClear(
                context: DeviceCleanupContext(generation: newSession.generation),
                session: newSession
            )
        } catch let error as DeviceLocationError {
            state = .cleanupPending(session: newSession, failure: error)
            throw error
        }

        activeSimulationSessionID = nil
        self.disconnectedDeviceID = nil
        state = .ready(newSession)
        return newSession
    }

    func switchDevice(to deviceID: DeviceID) async throws -> PreparedDeviceSession {
        if let session, let lease = tunnelLease {
            do {
                try await sendClear(
                    context: DeviceCleanupContext(generation: session.generation),
                    session: session
                )
            } catch let error as DeviceLocationError {
                if case let .interrupted(interruptedSession, _) = state,
                   interruptedSession == session {
                    throw error
                }
                state = .cleanupPending(session: session, failure: error)
                throw error
            }

            try await boundary.shutdownDVT(generation: session.generation)
            try await boundary.stopTunnel(lease)
            self.session = nil
            tunnelLease = nil
            runtime = nil
            activeSimulationSessionID = nil
        }

        return try await prepareSession(
            selectedDeviceID: deviceID,
            publishReady: true
        )
    }

    func setLocation(
        _ coordinate: DeviceCoordinate,
        context: DeviceMutationContext
    ) async throws {
        diagnosticLogger.record(
            .debug,
            category: "device",
            event: "location.set_requested",
            metadata: [
                "requestID": context.requestID.rawValue.uuidString,
                "sessionID": context.simulationSessionID.rawValue.uuidString,
                "generation": String(context.generation.rawValue),
            ]
        )
        do {
            try await performSetLocation(coordinate, context: context)
            diagnosticLogger.record(
                .debug,
                category: "device",
                event: "location.set_succeeded",
                metadata: [
                    "requestID": context.requestID.rawValue.uuidString,
                    "generation": String(context.generation.rawValue),
                ]
            )
        } catch {
            diagnosticLogger.record(
                .error,
                category: "device",
                event: "location.set_failed",
                metadata: [
                    "requestID": context.requestID.rawValue.uuidString,
                    "generation": String(context.generation.rawValue),
                    "failure": String(describing: error),
                ]
            )
            throw error
        }
    }

    private func performSetLocation(
        _ coordinate: DeviceCoordinate,
        context: DeviceMutationContext
    ) async throws {
        guard let session else {
            throw DeviceLocationError.usbDisconnected
        }
        guard context.generation == session.generation else {
            throw DeviceLocationError.staleGeneration
        }

        activeSimulationSessionID = context.simulationSessionID
        let boundary = self.boundary
        let command = DVTLocationCommand.set(
            requestID: context.requestID,
            coordinate: coordinate
        )
        let reply = try await mutationQueue.perform {
            try await boundary.sendDVT(command, generation: context.generation)
        }

        guard self.session?.generation == context.generation,
              generation == context.generation
        else {
            throw DeviceLocationError.staleGeneration
        }
        guard reply.requestID == context.requestID else {
            throw DeviceLocationError.responseMismatch
        }
    }

    func clearLocation(context: DeviceCleanupContext) async throws {
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "location.clear_requested",
            metadata: [
                "requestID": context.requestID.rawValue.uuidString,
                "generation": String(context.generation.rawValue),
            ]
        )
        do {
            guard let session else {
                throw DeviceLocationError.usbDisconnected
            }
            try await sendClear(context: context, session: session)
            activeSimulationSessionID = nil
            diagnosticLogger.record(
                .info,
                category: "device",
                event: "location.clear_succeeded",
                metadata: ["requestID": context.requestID.rawValue.uuidString]
            )
        } catch {
            diagnosticLogger.record(
                .error,
                category: "device",
                event: "location.clear_failed",
                metadata: [
                    "requestID": context.requestID.rawValue.uuidString,
                    "failure": String(describing: error),
                ]
            )
            throw error
        }
    }

    func shutdown(generation: DeviceSessionGeneration) async {
        guard session?.generation == generation else {
            return
        }
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "dvt.shutdown_requested",
            metadata: ["generation": String(generation.rawValue)]
        )
        try? await boundary.shutdownDVT(generation: generation)
    }

    func handleUSBDisconnect(deviceID: DeviceID) async {
        guard selectedDevice?.id == deviceID, let oldSession = session else {
            return
        }
        diagnosticLogger.record(
            .warning,
            category: "device",
            event: "usb.disconnected",
            metadata: ["generation": String(oldSession.generation.rawValue)]
        )

        do {
            generation = try generation.advanced()
        } catch {
            state = .interrupted(
                session: oldSession,
                interruption: DeviceInterruption(
                    reason: .usbDisconnected,
                    positionKnowledge: .unknown
                )
            )
            return
        }

        session = nil
        disconnectedDeviceID = deviceID
        state = .interrupted(
            session: oldSession,
            interruption: DeviceInterruption(
                reason: .usbDisconnected,
                positionKnowledge: .unknown
            )
        )

        try? await boundary.shutdownDVT(generation: oldSession.generation)
        if let tunnelLease {
            try? await boundary.stopTunnel(tunnelLease)
        }
        tunnelLease = nil
        runtime = nil
    }

    func teardownForQuit() async throws {
        diagnosticLogger.record(.info, category: "device", event: "teardown.started")
        if let session, let lease = tunnelLease {
            if activeSimulationSessionID != nil {
                do {
                    try await sendClear(
                        context: DeviceCleanupContext(generation: session.generation),
                        session: session
                    )
                } catch let error as DeviceLocationError {
                    state = .cleanupPending(session: session, failure: error)
                    throw error
                }
            }
            try await boundary.shutdownDVT(generation: session.generation)
            try await boundary.stopTunnel(lease)
        }
        try await boundary.reconcileTunnels()

        runtime = nil
        session = nil
        tunnelLease = nil
        selectedDevice = nil
        disconnectedDeviceID = nil
        activeSimulationSessionID = nil
        state = .disconnected
        diagnosticLogger.record(.info, category: "device", event: "teardown.completed")
    }

    private func prepareSession(
        selectedDeviceID: DeviceID?,
        publishReady: Bool
    ) async throws -> PreparedDeviceSession {
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "session.prepare_started",
            metadata: ["explicitSelection": String(selectedDeviceID != nil)]
        )
        state = .discovering
        let runtime = try await requireRuntime()
        let devices = try await boundary.discoverUSBDevices(runtime: runtime)
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "usb.discovery_completed",
            metadata: ["deviceCount": String(devices.count)]
        )
        let device = try selectDevice(
            from: devices,
            selectedDeviceID: selectedDeviceID
        )

        guard device.support == .supported else {
            state = .selectionRequired(devices)
            throw DeviceLocationError.unsupportedDevice
        }

        state = .preparing(device: device, stage: .trust)
        diagnosticLogger.record(.info, category: "device", event: "trust.verify_started")
        try await boundary.verifyTrust(for: device, runtime: runtime)

        state = .preparing(device: device, stage: .developerMode)
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "developer_mode.verify_started"
        )
        try await boundary.verifyDeveloperMode(for: device, runtime: runtime)

        state = .preparing(device: device, stage: .developerDiskImage)
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "developer_disk_image.prepare_started"
        )
        try await boundary.prepareDeveloperDiskImage(for: device, runtime: runtime)

        let newGeneration = try generation.advanced()
        state = .preparing(device: device, stage: .tunnel)
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "tunnel.start_requested",
            metadata: ["generation": String(newGeneration.rawValue)]
        )
        let lease = try await boundary.startTunnel(
            for: device,
            idempotencyKey: UUID()
        )
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "tunnel.started",
            metadata: ["generation": String(newGeneration.rawValue)]
        )

        state = .preparing(device: device, stage: .dvtHelper)
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "dvt.start_requested",
            metadata: ["generation": String(newGeneration.rawValue)]
        )
        do {
            try await boundary.startDVT(
                runtime: runtime,
                lease: lease,
                generation: newGeneration
            )
            diagnosticLogger.record(
                .info,
                category: "device",
                event: "dvt.started",
                metadata: ["generation": String(newGeneration.rawValue)]
            )
        } catch {
            diagnosticLogger.record(
                .error,
                category: "device",
                event: "dvt.start_failed",
                metadata: [
                    "generation": String(newGeneration.rawValue),
                    "failure": String(describing: error),
                ]
            )
            try? await boundary.stopTunnel(lease)
            throw error
        }

        let prepared = PreparedDeviceSession(
            device: device,
            generation: newGeneration
        )
        generation = newGeneration
        self.runtime = runtime
        session = prepared
        tunnelLease = lease
        selectedDevice = device
        if publishReady {
            state = .ready(prepared)
        }
        diagnosticLogger.record(
            .info,
            category: "device",
            event: "session.ready",
            metadata: ["generation": String(newGeneration.rawValue)]
        )
        return prepared
    }

    private func requireRuntime() async throws -> RuntimeInstallation {
        switch await boundary.inspectRuntime() {
        case let .ready(runtime):
            return runtime
        case .installationRequired:
            throw DeviceLocationError.prerequisiteFailed(
                stage: .runtime,
                message: "pymobiledevice3 installation is required"
            )
        case let .pythonUnavailable(minimumVersion):
            throw DeviceLocationError.prerequisiteFailed(
                stage: .runtime,
                message: "Python \(minimumVersion) or newer is required"
            )
        case .incompleteManagedEnvironment:
            throw DeviceLocationError.prerequisiteFailed(
                stage: .runtime,
                message: "Managed pymobiledevice3 environment is incomplete"
            )
        case let .configurationFailure(failure):
            throw DeviceLocationError.prerequisiteFailed(
                stage: .runtime,
                message: String(describing: failure)
            )
        }
    }

    private func selectDevice(
        from devices: [USBDevice],
        selectedDeviceID: DeviceID?
    ) throws -> USBDevice {
        guard !devices.isEmpty else {
            state = .disconnected
            throw DeviceLocationError.noUSBDevice
        }
        if let selectedDeviceID {
            guard let device = devices.first(where: { $0.id == selectedDeviceID }) else {
                state = .selectionRequired(devices)
                throw DeviceLocationError.deviceNotFound
            }
            return device
        }
        guard devices.count == 1, let device = devices.first else {
            state = .selectionRequired(devices)
            throw DeviceLocationError.selectionRequired
        }
        return device
    }

    private func sendClear(
        context: DeviceCleanupContext,
        session: PreparedDeviceSession
    ) async throws {
        guard context.generation == session.generation else {
            throw DeviceLocationError.staleGeneration
        }
        let boundary = self.boundary
        let command = DVTLocationCommand.clear(requestID: context.requestID)
        let reply = try await mutationQueue.perform {
            try await boundary.sendDVT(command, generation: context.generation)
        }

        guard self.session?.generation == context.generation,
              generation == context.generation
        else {
            throw DeviceLocationError.staleGeneration
        }
        guard reply.requestID == context.requestID else {
            throw DeviceLocationError.responseMismatch
        }
    }
}

// MARK: - Production boundary

private actor LivePymobiledeviceBoundary: PymobiledeviceBoundary {
    private let runtimeManager: RuntimeManager
    private let processRunner: any RuntimeProcessRunning
    private let tunnelClient: LiveTunnelClient
    private let diagnosticLogger: any DiagnosticLogging
    private var dvtSession: DVTProcessSession?
    private var dvtGeneration: DeviceSessionGeneration?

    init(
        runtimeManager: RuntimeManager,
        processRunner: any RuntimeProcessRunning,
        tunnelClient: LiveTunnelClient,
        diagnosticLogger: any DiagnosticLogging
    ) {
        self.runtimeManager = runtimeManager
        self.processRunner = processRunner
        self.tunnelClient = tunnelClient
        self.diagnosticLogger = diagnosticLogger
    }

    func inspectRuntime() async -> RuntimeAvailability {
        await runtimeManager.inspect()
    }

    func discoverUSBDevices(
        runtime: RuntimeInstallation
    ) async throws -> [USBDevice] {
        let output = try await run(
            runtime: runtime,
            arguments: ["usbmux", "list", "--usb"],
            stage: .usbSelection
        )
        return try Self.decodeUSBDevices(output.standardOutput)
    }

    func verifyTrust(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws {
        _ = try await run(
            runtime: runtime,
            arguments: ["lockdown", "info", "--udid", device.id.rawValue],
            stage: .trust
        )
    }

    func verifyDeveloperMode(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws {
        let output = try await run(
            runtime: runtime,
            arguments: [
                "amfi",
                "developer-mode-status",
                "--udid",
                device.id.rawValue,
            ],
            stage: .developerMode
        )
        let normalized = output.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized == "true"
            || normalized.contains("\"developer_mode_status\": true")
            || normalized.contains("\"developer-mode-status\": true")
        else {
            throw DeviceLocationError.prerequisiteFailed(
                stage: .developerMode,
                message: "Developer Mode is not enabled"
            )
        }
    }

    func prepareDeveloperDiskImage(
        for device: USBDevice,
        runtime: RuntimeInstallation
    ) async throws {
        _ = try await run(
            runtime: runtime,
            arguments: ["mounter", "auto-mount", "--udid", device.id.rawValue],
            stage: .developerDiskImage
        )
        let mountedImages = try await run(
            runtime: runtime,
            arguments: ["mounter", "list", "--udid", device.id.rawValue],
            stage: .developerDiskImage
        )
        guard let data = mountedImages.standardOutput.data(using: .utf8),
              let images = try? JSONSerialization.jsonObject(with: data)
                as? [[String: Any]],
              !images.isEmpty
        else {
            throw DeviceLocationError.prerequisiteFailed(
                stage: .developerDiskImage,
                message: "Developer Disk Image is not mounted"
            )
        }
    }

    func startTunnel(
        for device: USBDevice,
        idempotencyKey: UUID
    ) async throws -> DeviceTunnelLease {
        try await tunnelClient.startTunnel(
            deviceID: device.id,
            idempotencyKey: idempotencyKey
        )
    }

    func startDVT(
        runtime: RuntimeInstallation,
        lease: DeviceTunnelLease,
        generation: DeviceSessionGeneration
    ) async throws {
        if let dvtSession, let dvtGeneration {
            try? await Task.detached {
                try dvtSession.shutdown(generation: dvtGeneration)
            }.value
        }

        let interpreterURL = try Self.pythonInterpreter(for: runtime)
        guard let helperURL = Bundle.main.url(
            forResource: "helper",
            withExtension: "py"
        ) else {
            throw DeviceLocationError.helperFailure(
                "Bundled DVT helper is missing"
            )
        }
        let session = DVTProcessSession(
            interpreterURL: interpreterURL,
            helperURL: helperURL,
            endpoint: lease.endpoint,
            diagnosticLogger: diagnosticLogger
        )
        try await Task.detached {
            try session.start()
        }.value
        dvtSession = session
        dvtGeneration = generation
    }

    func sendDVT(
        _ command: DVTLocationCommand,
        generation: DeviceSessionGeneration
    ) async throws -> DVTLocationReply {
        guard let dvtSession, dvtGeneration == generation else {
            throw DeviceLocationError.staleGeneration
        }
        return try await Task.detached {
            try dvtSession.send(command)
        }.value
    }

    func shutdownDVT(generation: DeviceSessionGeneration) async throws {
        guard let dvtSession, dvtGeneration == generation else {
            return
        }
        defer {
            self.dvtSession = nil
            dvtGeneration = nil
        }
        try await Task.detached {
            try dvtSession.shutdown(generation: generation)
        }.value
    }

    func stopTunnel(_ lease: DeviceTunnelLease) async throws {
        try await tunnelClient.stopTunnel(lease)
    }

    func reconcileTunnels() async throws {
        try await tunnelClient.reconcile()
    }

    private func run(
        runtime: RuntimeInstallation,
        arguments: [String],
        stage: DevicePrerequisiteStage
    ) async throws -> RuntimeProcessOutput {
        let output: RuntimeProcessOutput
        do {
            output = try await processRunner.run(
                RuntimeProcessCommand(
                    executableURL: runtime.executableURL,
                    arguments: arguments
                )
            )
        } catch {
            throw DeviceLocationError.transportFailure(
                "Unable to launch pymobiledevice3: \(error.localizedDescription)"
            )
        }
        guard output.exitCode == 0 else {
            let detail = Self.failureDetail(output)
            if Self.isAuthorizationFailure(detail) {
                throw DeviceLocationError.authorizationDenied
            }
            throw DeviceLocationError.prerequisiteFailed(
                stage: stage,
                message: detail
            )
        }
        return output
    }

    private static func failureDetail(_ output: RuntimeProcessOutput) -> String {
        let detail = (output.standardError + "\n" + output.standardOutput)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "pymobiledevice3 exited with \(output.exitCode)" : detail
    }

    private static func isAuthorizationFailure(_ detail: String) -> Bool {
        let normalized = detail.lowercased()
        return normalized.contains("not trusted")
            || normalized.contains("pairing")
            || normalized.contains("permission denied")
            || normalized.contains("user denied")
    }

    private static func decodeUSBDevices(_ output: String) throws -> [USBDevice] {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            throw DeviceLocationError.transportFailure(
                "USB discovery returned invalid JSON"
            )
        }

        let rawDevices: [[String: Any]]
        if let devices = object as? [[String: Any]] {
            rawDevices = devices
        } else if let envelope = object as? [String: Any],
                  let devices = envelope["devices"] as? [[String: Any]] {
            rawDevices = devices
        } else {
            throw DeviceLocationError.transportFailure(
                "USB discovery returned an unexpected data shape"
            )
        }

        return try rawDevices.compactMap { rawDevice in
            let info = (rawDevice["short_info"] as? [String: Any]) ?? rawDevice
            let connectionType = Self.string(
                in: info,
                keys: ["ConnectionType", "connection_type", "connectionType"]
            )
            if let connectionType,
               connectionType.caseInsensitiveCompare("USB") != .orderedSame {
                return nil
            }
            if let deviceClass = Self.string(
                in: info,
                keys: ["DeviceClass", "device_class", "deviceClass"]
            ), deviceClass.caseInsensitiveCompare("iPhone") != .orderedSame {
                return nil
            }
            guard let identifier = Self.string(
                in: info,
                keys: ["Identifier", "UDID", "udid", "identifier"]
            ), let version = Self.string(
                in: info,
                keys: ["ProductVersion", "product_version", "productVersion"]
            ) else {
                throw DeviceLocationError.transportFailure(
                    "USB device identity or iOS version is missing"
                )
            }
            let name = Self.string(
                in: info,
                keys: ["DeviceName", "device_name", "name"]
            ) ?? "iPhone"
            return try USBDevice(
                id: DeviceID(identifier),
                name: name,
                operatingSystemVersion: try Self.operatingSystemVersion(version)
            )
        }
    }

    private static func string(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        keys.lazy.compactMap { dictionary[$0] as? String }.first
    }

    private static func operatingSystemVersion(
        _ value: String
    ) throws -> OperatingSystemVersion {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard let major = components.first.flatMap({ Int($0) }) else {
            throw DeviceLocationError.transportFailure(
                "USB device returned an invalid iOS version"
            )
        }
        return OperatingSystemVersion(
            majorVersion: major,
            minorVersion: components.count > 1 ? Int(components[1]) ?? 0 : 0,
            patchVersion: components.count > 2 ? Int(components[2]) ?? 0 : 0
        )
    }

    private static func pythonInterpreter(
        for runtime: RuntimeInstallation
    ) throws -> URL {
        let fileManager = FileManager.default
        let sibling = runtime.executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("python3")
        if fileManager.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        let executableURL = runtime.executableURL.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: executableURL),
              let contents = String(data: data, encoding: .utf8),
              let firstLine = contents.split(whereSeparator: \.isNewline).first,
              firstLine.hasPrefix("#!")
        else {
            throw DeviceLocationError.helperFailure(
                "Unable to locate the Python interpreter for pymobiledevice3"
            )
        }
        let interpreterPath = firstLine
            .dropFirst(2)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? ""
        guard interpreterPath.hasPrefix("/"),
              fileManager.isExecutableFile(atPath: interpreterPath)
        else {
            throw DeviceLocationError.helperFailure(
                "pymobiledevice3 uses an unavailable Python interpreter"
            )
        }
        return URL(fileURLWithPath: interpreterPath)
    }
}

private final class DVTProcessSession: @unchecked Sendable {
    private let interpreterURL: URL
    private let helperURL: URL
    private let endpoint: DeviceTunnelEndpoint
    private let diagnosticLogger: any DiagnosticLogging
    private let stateLock = NSLock()
    private let inputOutputLock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?

    init(
        interpreterURL: URL,
        helperURL: URL,
        endpoint: DeviceTunnelEndpoint,
        diagnosticLogger: any DiagnosticLogging
    ) {
        self.interpreterURL = interpreterURL
        self.helperURL = helperURL
        self.endpoint = endpoint
        self.diagnosticLogger = diagnosticLogger
    }

    func start() throws {
        try stateLock.withLock {
            guard process == nil else {
                return
            }
            let process = Process()
            let standardInput = Pipe()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = interpreterURL
            process.arguments = [
                helperURL.path,
                "--rsd-host",
                endpoint.address,
                "--rsd-port",
                String(endpoint.port),
            ]
            process.standardInput = standardInput
            process.standardOutput = standardOutput
            process.standardError = standardError
            do {
                try process.run()
            } catch {
                diagnosticLogger.record(
                    .error,
                    category: "dvt",
                    event: "helper.launch_failed",
                    metadata: ["failure": error.localizedDescription]
                )
                throw DeviceLocationError.helperFailure(
                    "Unable to launch DVT helper: \(error.localizedDescription)"
                )
            }

            self.process = process
            input = standardInput.fileHandleForWriting
            output = standardOutput.fileHandleForReading
            errorOutput = standardError.fileHandleForReading
            startReadingStandardError(standardError.fileHandleForReading)
            diagnosticLogger.record(.info, category: "dvt", event: "helper.launched")
            let readyLine = try readLine()
            guard let data = readyLine.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  event["event"] as? String == "ready"
            else {
                process.terminate()
                self.process = nil
                input = nil
                output = nil
                errorOutput?.readabilityHandler = nil
                errorOutput = nil
                diagnosticLogger.record(
                    .error,
                    category: "dvt",
                    event: "helper.not_ready"
                )
                throw DeviceLocationError.helperFailure(
                    "DVT helper did not become ready"
                )
            }
            diagnosticLogger.record(.info, category: "dvt", event: "helper.ready")
        }
    }

    func send(_ command: DVTLocationCommand) throws -> DVTLocationReply {
        try inputOutputLock.withLock {
            let message: [String: Any]
            switch command {
            case let .set(requestID, coordinate):
                message = [
                    "requestID": requestID.rawValue.uuidString,
                    "command": "set",
                    "latitude": coordinate.latitude,
                    "longitude": coordinate.longitude,
                ]
            case let .clear(requestID):
                message = [
                    "requestID": requestID.rawValue.uuidString,
                    "command": "clear",
                ]
            }
            diagnosticLogger.record(
                .debug,
                category: "dvt",
                event: "request.sent",
                metadata: [
                    "requestID": command.requestID.rawValue.uuidString,
                    "command": command.name,
                ]
            )
            return try exchange(message)
        }
    }

    func shutdown(generation: DeviceSessionGeneration) throws {
        if inputOutputLock.try() {
            defer { inputOutputLock.unlock() }
            let requestID = DeviceRequestID()
            _ = try? exchange([
                "requestID": requestID.rawValue.uuidString,
                "command": "shutdown",
            ])
        }

        stateLock.withLock {
            if process?.isRunning == true {
                process?.terminate()
            }
            input?.closeFile()
            errorOutput?.readabilityHandler = nil
            errorOutput?.closeFile()
            self.process = nil
            input = nil
            output = nil
            errorOutput = nil
        }
        diagnosticLogger.record(
            .info,
            category: "dvt",
            event: "helper.stopped",
            metadata: ["generation": String(generation.rawValue)]
        )
    }

    private func exchange(_ message: [String: Any]) throws -> DVTLocationReply {
        let handles = stateLock.withLock {
            (
                input: input,
                output: output,
                isRunning: process?.isRunning == true
            )
        }
        guard let input = handles.input,
              let output = handles.output,
              handles.isRunning
        else {
            throw DeviceLocationError.helperFailure(
                "DVT helper is not running"
            )
        }
        let data = try JSONSerialization.data(withJSONObject: message)
        input.write(data)
        input.write(Data([0x0A]))
        let responseLine = try readLine(from: output)
        guard let responseData = responseLine.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: responseData)
                as? [String: Any],
              let requestIDString = response["requestID"] as? String,
              let requestUUID = UUID(uuidString: requestIDString),
              let success = response["ok"] as? Bool
        else {
            throw DeviceLocationError.helperFailure(
                "DVT helper returned an invalid response"
            )
        }
        guard success else {
            let error = response["error"] as? [String: Any]
            let code = error?["code"] as? String
            let errorMessage = error?["message"] as? String
            let backendDetail = error?["detail"] as? String
            diagnosticLogger.record(
                .error,
                category: "dvt",
                event: "request.failed",
                metadata: [
                    "requestID": requestIDString,
                    "command": message["command"] as? String ?? "unknown",
                    "code": code ?? "unknown",
                    "message": errorMessage ?? "DVT location request failed",
                    "detail": backendDetail ?? "none",
                ]
            )
            let failureMessage = [
                errorMessage,
                code,
                backendDetail,
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
            throw DeviceLocationError.helperFailure(
                failureMessage.isEmpty
                    ? "DVT location request failed"
                    : failureMessage
            )
        }
        diagnosticLogger.record(
            .debug,
            category: "dvt",
            event: "request.succeeded",
            metadata: ["requestID": requestIDString]
        )
        return DVTLocationReply(
            requestID: DeviceRequestID(rawValue: requestUUID)
        )
    }

    private func readLine() throws -> String {
        guard let output else {
            throw DeviceLocationError.helperFailure(
                "DVT helper output is unavailable"
            )
        }
        return try readLine(from: output)
    }

    private func readLine(from output: FileHandle) throws -> String {
        var data = Data()
        while true {
            guard let byte = try output.read(upToCount: 1), !byte.isEmpty else {
                throw DeviceLocationError.helperFailure(
                    "DVT helper exited unexpectedly"
                )
            }
            if byte[byte.startIndex] == 0x0A {
                break
            }
            guard data.count < 64 * 1024 else {
                throw DeviceLocationError.helperFailure(
                    "DVT helper response exceeded the size limit"
                )
            }
            data.append(byte)
        }
        guard let line = String(data: data, encoding: .utf8) else {
            throw DeviceLocationError.helperFailure(
                "DVT helper response is not UTF-8"
            )
        }
        return line
    }

    private func startReadingStandardError(_ handle: FileHandle) {
        let diagnosticLogger = self.diagnosticLogger
        handle.readabilityHandler = { readableHandle in
            let data = readableHandle.availableData
            guard !data.isEmpty else {
                readableHandle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            diagnosticLogger.record(
                .warning,
                category: "dvt",
                event: "helper.stderr",
                metadata: ["message": text]
            )
        }
    }
}

private extension DVTLocationCommand {
    var name: String {
        switch self {
        case .set:
            "set"
        case .clear:
            "clear"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

// MARK: - Privileged tunnel XPC client

private struct LiveTunnelReply<Value: Decodable>: Decodable {
    let value: Value?
    let error: LiveTunnelError?
}

private struct LiveTunnelError: Decodable {
    let code: String
    let detail: String
}

private struct LiveTunnelLeaseSnapshot: Decodable {
    struct LeaseID: Decodable {
        let rawValue: UUID
    }

    struct DeviceIdentifier: Decodable {
        let rawValue: String
    }

    struct Endpoint: Decodable {
        let address: String
        let port: UInt16
    }

    let leaseID: LeaseID
    let deviceID: DeviceIdentifier
    let endpoint: Endpoint
    let state: String
}

private struct LiveReconcileReport: Decodable {
    let reclaimedLeaseCount: Int
    let failures: [LiveTunnelError]
}

private struct LiveEmptyReply: Decodable {}

private final class LiveTunnelContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

private actor LiveTunnelClient {
    private static let serviceName = "com.cash.iPhoneLocationMoveTunnelHelper"
    private var connection: NSXPCConnection?

    func startTunnel(
        deviceID: DeviceID,
        idempotencyKey: UUID
    ) async throws -> DeviceTunnelLease {
        let snapshot: LiveTunnelLeaseSnapshot = try await request { proxy, reply in
            proxy.startTunnel(
                deviceID: deviceID.rawValue,
                idempotencyKey: idempotencyKey,
                withReply: reply
            )
        }
        guard snapshot.state == "running",
              snapshot.deviceID.rawValue == deviceID.rawValue,
              !snapshot.endpoint.address.isEmpty,
              snapshot.endpoint.port > 0
        else {
            throw DeviceLocationError.tunnelFailure(
                "Tunnel helper returned an invalid lease"
            )
        }
        return DeviceTunnelLease(
            id: DeviceTunnelLeaseID(rawValue: snapshot.leaseID.rawValue),
            deviceID: deviceID,
            endpoint: DeviceTunnelEndpoint(
                address: snapshot.endpoint.address,
                port: Int(snapshot.endpoint.port)
            )
        )
    }

    func stopTunnel(_ lease: DeviceTunnelLease) async throws {
        let _: LiveEmptyReply = try await request { proxy, reply in
            proxy.stopTunnel(
                leaseID: lease.id.rawValue,
                withReply: reply
            )
        }
    }

    func reconcile() async throws {
        let report: LiveReconcileReport = try await request { proxy, reply in
            proxy.reconcile(withReply: reply)
        }
        if let failure = report.failures.first {
            throw Self.map(failure)
        }
    }

    private func request<Value: Decodable & Sendable>(
        _ operation: @escaping (
            TunnelHelperXPCProtocol,
            @escaping (Data) -> Void
        ) -> Void
    ) async throws -> Value {
        return try await withCheckedThrowingContinuation { continuation in
            let continuation = LiveTunnelContinuation(continuation)
            let proxy: TunnelHelperXPCProtocol
            do {
                proxy = try remoteProxy { error in
                    continuation.resume(
                        throwing: DeviceLocationError.tunnelFailure(
                            "Tunnel helper communication failed: \(error.localizedDescription)"
                        )
                    )
                }
            } catch {
                continuation.resume(throwing: error)
                return
            }

            Task {
                try? await Task.sleep(for: .seconds(15))
                continuation.resume(throwing: DeviceLocationError.timeout)
            }
            operation(proxy) { data in
                do {
                    let envelope = try JSONDecoder().decode(
                        LiveTunnelReply<Value>.self,
                        from: data
                    )
                    if let error = envelope.error {
                        continuation.resume(throwing: Self.map(error))
                    } else if let value = envelope.value {
                        continuation.resume(returning: value)
                    } else {
                        continuation.resume(
                            throwing: DeviceLocationError.tunnelFailure(
                                "Tunnel helper returned an empty reply"
                            )
                        )
                    }
                } catch {
                    continuation.resume(
                        throwing: DeviceLocationError.tunnelFailure(
                            "Tunnel helper returned malformed data"
                        )
                    )
                }
            }
        }
    }

    private func remoteProxy(
        errorHandler: @escaping @Sendable (Error) -> Void
    ) throws -> TunnelHelperXPCProtocol {
        let connection: NSXPCConnection
        if let existing = self.connection {
            connection = existing
        } else {
            let created = NSXPCConnection(
                machServiceName: Self.serviceName,
                options: .privileged
            )
            created.remoteObjectInterface = NSXPCInterface(
                with: TunnelHelperXPCProtocol.self
            )
            created.invalidationHandler = { [weak self] in
                Task {
                    await self?.discardConnection()
                }
            }
            created.interruptionHandler = { [weak self] in
                Task {
                    await self?.discardConnection()
                }
            }
            created.resume()
            self.connection = created
            connection = created
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler)
            as? TunnelHelperXPCProtocol
        else {
            throw DeviceLocationError.tunnelFailure(
                "Privileged tunnel helper is unavailable"
            )
        }
        return proxy
    }

    private func discardConnection() {
        connection = nil
    }

    nonisolated private static func map(
        _ error: LiveTunnelError
    ) -> DeviceLocationError {
        if error.code == "callerNotTrusted" {
            return .authorizationDenied
        }
        return .tunnelFailure(error.detail)
    }
}
