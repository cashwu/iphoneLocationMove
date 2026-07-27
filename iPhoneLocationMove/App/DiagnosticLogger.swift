import Foundation
import OSLog

enum DiagnosticLogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

protocol DiagnosticLogging: Sendable {
    func record(
        _ level: DiagnosticLogLevel,
        category: String,
        event: String,
        metadata: [String: String]
    )
}

extension DiagnosticLogging {
    func record(
        _ level: DiagnosticLogLevel,
        category: String,
        event: String
    ) {
        record(level, category: category, event: event, metadata: [:])
    }
}

struct NullDiagnosticLogger: DiagnosticLogging {
    func record(
        _: DiagnosticLogLevel,
        category _: String,
        event _: String,
        metadata _: [String: String]
    ) {}
}

final class DiagnosticLogger: DiagnosticLogging, @unchecked Sendable {
    static let shared = DiagnosticLogger()

    let fileURL: URL

    private let maxFileBytes: UInt64
    private let retainedArchives: Int
    private let fileManager: FileManager
    private let lock = NSLock()
    private let systemLogger = Logger(
        subsystem: "com.cash.iPhoneLocationMove",
        category: "diagnostic"
    )
    private let timestampFormatter: ISO8601DateFormatter

    init(
        directoryURL: URL? = nil,
        maxFileBytes: UInt64 = 2 * 1_024 * 1_024,
        retainedArchives: Int = 2,
        fileManager: FileManager = .default
    ) {
        let directory = directoryURL
            ?? fileManager.urls(
                for: .libraryDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent("Logs/iPhoneLocationMove", isDirectory: true)
        fileURL = directory.appendingPathComponent("diagnostic.jsonl")
        self.maxFileBytes = max(1, maxFileBytes)
        self.retainedArchives = max(0, retainedArchives)
        self.fileManager = fileManager

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        timestampFormatter = formatter
    }

    func record(
        _ level: DiagnosticLogLevel,
        category: String,
        event: String,
        metadata: [String: String] = [:]
    ) {
        let entry: [String: Any] = [
            "timestamp": timestampFormatter.string(from: Date()),
            "level": level.rawValue,
            "category": sanitize(category, limit: 128),
            "event": sanitize(event, limit: 128),
            "metadata": metadata.mapValues { sanitize($0, limit: 2_048) },
        ]

        guard var data = try? JSONSerialization.data(
            withJSONObject: entry,
            options: [.sortedKeys]
        ) else {
            systemLogger.error("無法序列化診斷紀錄")
            return
        }
        data.append(0x0A)

        mirrorToSystemLog(level: level, category: category, event: event)
        lock.withLock {
            do {
                try prepareFile(forAdditionalBytes: UInt64(data.count))
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                systemLogger.error(
                    "無法寫入診斷紀錄：\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func prepareFile(forAdditionalBytes bytes: UInt64) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let currentBytes = (
            try? fileManager.attributesOfItem(atPath: fileURL.path)[.size]
                as? NSNumber
        )?.uint64Value ?? 0
        if currentBytes > 0, currentBytes + bytes > maxFileBytes {
            try rotate()
        }

        if !fileManager.fileExists(atPath: fileURL.path) {
            guard fileManager.createFile(
                atPath: fileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    private func rotate() throws {
        guard retainedArchives > 0 else {
            try fileManager.removeItem(at: fileURL)
            return
        }

        for index in stride(from: retainedArchives, through: 1, by: -1) {
            let destination = archiveURL(index: index)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            let source = index == 1 ? fileURL : archiveURL(index: index - 1)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.moveItem(at: source, to: destination)
            }
        }
    }

    private func archiveURL(index: Int) -> URL {
        fileURL
            .deletingPathExtension()
            .appendingPathExtension("\(index).jsonl")
    }

    private func sanitize(_ value: String, limit: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return String(normalized.prefix(limit))
    }

    private func mirrorToSystemLog(
        level: DiagnosticLogLevel,
        category: String,
        event: String
    ) {
        let message = "\(category).\(event)"
        switch level {
        case .debug:
            systemLogger.debug("\(message, privacy: .public)")
        case .info:
            systemLogger.info("\(message, privacy: .public)")
        case .warning:
            systemLogger.warning("\(message, privacy: .public)")
        case .error:
            systemLogger.error("\(message, privacy: .public)")
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
