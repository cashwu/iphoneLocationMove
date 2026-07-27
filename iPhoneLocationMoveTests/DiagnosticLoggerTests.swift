import Foundation
import XCTest
@testable import iPhoneLocationMove

final class DiagnosticLoggerTests: XCTestCase {
    func testWritesStructuredJSONLineAndSanitizesNewlines() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = DiagnosticLogger(directoryURL: directory)

        logger.record(
            .error,
            category: "dvt",
            event: "request.failed",
            metadata: [
                "requestID": "request-1",
                "detail": "first line\nsecond line",
            ]
        )

        let data = try Data(contentsOf: logger.fileURL)
        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 1)
        let entry = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(lines[0].utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(entry["level"] as? String, "error")
        XCTAssertEqual(entry["category"] as? String, "dvt")
        XCTAssertEqual(entry["event"] as? String, "request.failed")
        let metadata = try XCTUnwrap(entry["metadata"] as? [String: String])
        XCTAssertEqual(metadata["requestID"], "request-1")
        XCTAssertEqual(metadata["detail"], "first line second line")
    }

    func testRotatesAndRetainsConfiguredArchiveCount() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = DiagnosticLogger(
            directoryURL: directory,
            maxFileBytes: 180,
            retainedArchives: 2
        )

        for index in 0..<8 {
            logger.record(
                .info,
                category: "simulation",
                event: "route.update",
                metadata: ["index": String(index)]
            )
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: logger.fileURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("diagnostic.1.jsonl").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("diagnostic.2.jsonl").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("diagnostic.3.jsonl").path
            )
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
