import XCTest
@testable import MenuHubCore

final class DiagnosticRedactionTests: XCTestCase {
    func testArchiveNeverExportsRawIdentityOrSensitiveText() throws {
        let event = DiagnosticEvent.make(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "6.0",
            menuHubVersion: "0.1.0",
            macOSVersion: "14.7",
            domain: "scan",
            errorCode: "private search /Users/example/Documents/report",
            stableItemID: "Lark Helper — confidential item name",
            scanCount: 42,
            durationMilliseconds: 18
        )

        let archive = DiagnosticArchive.make(
            events: [event],
            homeDirectory: "/Users/example"
        )
        let text = String(decoding: try archive.jsonData(), as: UTF8.self)

        XCTAssertFalse(text.contains("/Users/example"))
        XCTAssertFalse(text.contains("example"))
        XCTAssertFalse(text.contains("private search"))
        XCTAssertFalse(text.contains("Lark Helper"))
        XCTAssertFalse(text.contains("confidential item name"))
        XCTAssertTrue(text.contains("stableItemHash"))
    }

    func testStableIdentityHashIsDeterministicAndDoesNotExposeInput() {
        let first = DiagnosticEvent.make(
            timestamp: .distantPast,
            appVersion: nil,
            menuHubVersion: "1",
            macOSVersion: "14",
            domain: "action",
            errorCode: "staleElement",
            stableItemID: "com.example.secret-item",
            scanCount: nil,
            durationMilliseconds: nil
        )
        let second = DiagnosticEvent.make(
            timestamp: .distantFuture,
            appVersion: nil,
            menuHubVersion: "1",
            macOSVersion: "14",
            domain: "action",
            errorCode: nil,
            stableItemID: "com.example.secret-item",
            scanCount: nil,
            durationMilliseconds: nil
        )

        XCTAssertEqual(first.stableItemHash, second.stableItemHash)
        XCTAssertNotEqual(first.stableItemHash, "com.example.secret-item")
        XCTAssertEqual(first.stableItemHash?.count, 64)
    }

    func testRingBufferDropsExpiredAndOldestEventsToStayWithinBounds() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        var buffer = DiagnosticRingBuffer(maxBytes: 850, retentionInterval: 60)

        buffer.append(fixture(at: now.addingTimeInterval(-61), code: "expired"), now: now)
        for index in 0..<20 {
            buffer.append(fixture(at: now, code: "error-\(index)"), now: now)
        }

        let archive = buffer.archive(homeDirectory: "/Users/example")
        let data = try archive.jsonData()
        XCTAssertLessThanOrEqual(data.count, 850)
        XCTAssertFalse(archive.events.contains { $0.errorCode == "expired" })
        XCTAssertFalse(archive.events.contains { $0.errorCode == "error-0" })
        XCTAssertEqual(archive.events.last?.errorCode, "error-19")
    }

    func testArchiveContainsOnlyDocumentedDiagnosticFields() throws {
        let archive = DiagnosticArchive.make(
            events: [fixture(at: Date(timeIntervalSince1970: 123), code: "permissionDenied")],
            homeDirectory: "/Users/example"
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: archive.jsonData()) as? [String: Any])
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        let keys = Set(try XCTUnwrap(events.first).keys)

        XCTAssertEqual(keys, [
            "timestamp", "appVersion", "menuHubVersion", "macOSVersion", "domain",
            "errorCode", "stableItemHash", "scanCount", "durationMilliseconds"
        ])
    }

    private func fixture(at timestamp: Date, code: String) -> DiagnosticEvent {
        DiagnosticEvent.make(
            timestamp: timestamp,
            appVersion: "1.0",
            menuHubVersion: "0.1.0",
            macOSVersion: "14.7",
            domain: "scan",
            errorCode: code,
            stableItemID: "stable-item-id",
            scanCount: 3,
            durationMilliseconds: 12
        )
    }
}
