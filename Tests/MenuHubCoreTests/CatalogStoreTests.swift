import Foundation
import XCTest
@testable import MenuHubCore

final class CatalogStoreTests: XCTestCase {
    func testLoadWithoutPrimaryReturnsEmptyDocument() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let loaded = try await CatalogStore(directory: directory).load()

        XCTAssertEqual(loaded, .empty)
    }

    func testLoadWithMissingPrimaryRestoresAndReturnsBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CatalogStore(directory: directory)
        let first = makeDocument(alias: "Backup")
        try await store.save(first)
        try await store.save(makeDocument(alias: "Primary"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("catalog-v1.json"))

        let loaded = try await store.load()

        XCTAssertEqual(loaded, first)
        XCTAssertEqual(try decodeFile(named: "catalog-v1.json", in: directory), first)
    }

    func testFirstSaveRoundTripsDocumentUsingReadableStableISO8601JSON() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CatalogStore(directory: directory)
        let document = makeDocument(alias: "First", timestamp: 1_700_000_000)

        try await store.save(document)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, document)
        let data = try Data(contentsOf: directory.appendingPathComponent("catalog-v1.json"))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\n"))
        XCTAssertTrue(json.contains("2023-11-14T22:13:20Z"))
        let groupsIndex = try XCTUnwrap(json.range(of: "\"groups\"")?.lowerBound)
        let itemsIndex = try XCTUnwrap(json.range(of: "\"items\"")?.lowerBound)
        XCTAssertLessThan(groupsIndex, itemsIndex)
    }

    func testRoundTripPreservesFractionalSecondDates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CatalogStore(directory: directory)
        let document = makeDocument(alias: "Precise", timestamp: 1_700_000_000.123456)

        try await store.save(document)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, document)
    }

    func testSecondSaveKeepsPreviousDocumentInBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CatalogStore(directory: directory)
        let first = makeDocument(alias: "First")
        let second = makeDocument(alias: "Second")

        try await store.save(first)
        try await store.save(second)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, second)
        XCTAssertEqual(try decodeFile(named: "catalog-v1.backup.json", in: directory), first)
    }

    func testCorruptPrimaryLoadsBackupAndRepairsPrimary() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CatalogStore(directory: directory)
        let first = makeDocument(alias: "Recover me")

        try await store.save(first)
        try await store.save(makeDocument(alias: "Newest"))
        try Data("not json".utf8).write(to: directory.appendingPathComponent("catalog-v1.json"))

        let loaded = try await store.load()
        XCTAssertEqual(loaded, first)
        XCTAssertEqual(try decodeFile(named: "catalog-v1.json", in: directory), first)
    }

    func testCorruptPrimaryAndBackupThrowsDistinctError() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("bad primary".utf8).write(to: directory.appendingPathComponent("catalog-v1.json"))
        try Data("bad backup".utf8).write(to: directory.appendingPathComponent("catalog-v1.backup.json"))

        do {
            _ = try await CatalogStore(directory: directory).load()
            XCTFail("Expected corruptPrimaryAndBackup")
        } catch let error as CatalogStoreError {
            XCTAssertEqual(error, .corruptPrimaryAndBackup)
        }
    }

    func testUnsupportedPrimarySchemaThrowsVersionErrorWithoutFallingBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unsupported = makeDocument(alias: "Future", schemaVersion: 9)
        try encoded(unsupported).write(to: directory.appendingPathComponent("catalog-v1.json"))
        try encoded(makeDocument(alias: "Old backup")).write(
            to: directory.appendingPathComponent("catalog-v1.backup.json")
        )

        do {
            _ = try await CatalogStore(directory: directory).load()
            XCTFail("Expected unsupportedSchema")
        } catch let error as CatalogStoreError {
            XCTAssertEqual(error, .unsupportedSchema(9))
        }
    }

    func testInterruptedThirdSaveBeforePrimaryCommitPreservesPrimaryAndBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primaryURL = directory.appendingPathComponent("catalog-v1.json")
        let backupURL = directory.appendingPathComponent("catalog-v1.backup.json")
        let store = CatalogStore(directory: directory)
        try await store.save(makeDocument(alias: "v1"))
        try await store.save(makeDocument(alias: "v2"))
        let originalPrimary = try Data(contentsOf: primaryURL)
        let originalBackup = try Data(contentsOf: backupURL)
        let interruptedStore = CatalogStore(directory: directory) { stage in
            if stage == .beforePrimaryReplacement { throw SimulatedInterruption() }
        }

        do {
            try await interruptedStore.save(makeDocument(alias: "v3"))
            XCTFail("Expected simulated interruption")
        } catch is SimulatedInterruption {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: primaryURL), originalPrimary)
        XCTAssertEqual(try Data(contentsOf: backupURL), originalBackup)
        try assertNoTransactionFiles(in: directory)
    }

    func testThirdSaveBackupStageFailureRollsBackPrimaryAndPreservesBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primaryURL = directory.appendingPathComponent("catalog-v1.json")
        let backupURL = directory.appendingPathComponent("catalog-v1.backup.json")
        let store = CatalogStore(directory: directory)
        try await store.save(makeDocument(alias: "v1"))
        try await store.save(makeDocument(alias: "v2"))
        let originalPrimary = try Data(contentsOf: primaryURL)
        let originalBackup = try Data(contentsOf: backupURL)
        let failingStore = CatalogStore(directory: directory) { stage in
            if stage == .beforeBackupReplacement { throw SimulatedInterruption() }
        }

        do {
            try await failingStore.save(makeDocument(alias: "v3"))
            XCTFail("Expected simulated backup failure")
        } catch is SimulatedInterruption {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: primaryURL), originalPrimary)
        XCTAssertEqual(try Data(contentsOf: backupURL), originalBackup)
        try assertNoTransactionFiles(in: directory)
    }

    func testLoadCompletesBackupWhenNewPrimaryWasPublishedBeforeRestart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldBackup = makeDocument(alias: "v1")
        let oldPrimary = makeDocument(alias: "v2")
        let newPrimary = makeDocument(alias: "v3")
        try encoded(newPrimary).write(to: directory.appendingPathComponent("catalog-v1.json"))
        try encoded(oldBackup).write(to: directory.appendingPathComponent("catalog-v1.backup.json"))
        try encoded(oldPrimary).write(to: directory.appendingPathComponent(".catalog-v1.old.stage"))

        let loaded = try await CatalogStore(directory: directory).load()

        XCTAssertEqual(loaded, newPrimary)
        XCTAssertEqual(try decodeFile(named: "catalog-v1.backup.json", in: directory), oldPrimary)
        try assertNoTransactionFiles(in: directory)
    }

    func testLoadAbortsPrePrimaryCrashWithoutOverwritingPreviousBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let previousBackup = makeDocument(alias: "v1")
        let unchangedPrimary = makeDocument(alias: "v2")
        try encoded(unchangedPrimary).write(to: directory.appendingPathComponent("catalog-v1.json"))
        try encoded(previousBackup).write(to: directory.appendingPathComponent("catalog-v1.backup.json"))
        try encoded(makeDocument(alias: "unpublished v3")).write(
            to: directory.appendingPathComponent(".catalog-v1.new.stage")
        )
        try encoded(unchangedPrimary).write(
            to: directory.appendingPathComponent(".catalog-v1.old.stage")
        )

        let loaded = try await CatalogStore(directory: directory).load()

        XCTAssertEqual(loaded, unchangedPrimary)
        XCTAssertEqual(try decodeFile(named: "catalog-v1.backup.json", in: directory), previousBackup)
        try assertNoTransactionFiles(in: directory)
    }

    func testLoadDiscardsPartialBothStagesWhenCommittedPrimaryIsValid() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let previousBackup = makeDocument(alias: "v1")
        let primary = makeDocument(alias: "v2")
        try encoded(primary).write(to: directory.appendingPathComponent("catalog-v1.json"))
        try encoded(previousBackup).write(to: directory.appendingPathComponent("catalog-v1.backup.json"))
        try encoded(makeDocument(alias: "unpublished v3")).write(
            to: directory.appendingPathComponent(".catalog-v1.new.stage")
        )
        try Data("partial old".utf8).write(
            to: directory.appendingPathComponent(".catalog-v1.old.stage")
        )

        let loaded = try await CatalogStore(directory: directory).load()

        XCTAssertEqual(loaded, primary)
        XCTAssertEqual(try decodeFile(named: "catalog-v1.backup.json", in: directory), previousBackup)
        try assertNoTransactionFiles(in: directory)
    }

    func testLoadDiscardsInvalidNewStageWhenCommittedPrimaryIsValid() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = makeDocument(alias: "Committed")
        try encoded(primary).write(to: directory.appendingPathComponent("catalog-v1.json"))
        try Data("partial new".utf8).write(
            to: directory.appendingPathComponent(".catalog-v1.new.stage")
        )

        let loaded = try await CatalogStore(directory: directory).load()

        XCTAssertEqual(loaded, primary)
        try assertNoTransactionFiles(in: directory)
    }

    func testLoadRestoresOldStageWhenPrimaryWasLostBeforeRestart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let previousBackup = makeDocument(alias: "v1")
        let oldPrimary = makeDocument(alias: "v2")
        try encoded(previousBackup).write(to: directory.appendingPathComponent("catalog-v1.backup.json"))
        try encoded(oldPrimary).write(to: directory.appendingPathComponent(".catalog-v1.old.stage"))

        let loaded = try await CatalogStore(directory: directory).load()

        XCTAssertEqual(loaded, oldPrimary)
        XCTAssertEqual(try decodeFile(named: "catalog-v1.json", in: directory), oldPrimary)
        XCTAssertEqual(try decodeFile(named: "catalog-v1.backup.json", in: directory), previousBackup)
        try assertNoTransactionFiles(in: directory)
    }

    func testLoadCleansDeterministicNewStageAndLegacyTemporaryArtifactsWhenPrimaryIsValid() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = makeDocument(alias: "v2")
        try encoded(primary).write(to: directory.appendingPathComponent("catalog-v1.json"))
        try encoded(makeDocument(alias: "abandoned v3")).write(
            to: directory.appendingPathComponent(".catalog-v1.new.stage")
        )
        try Data("legacy".utf8).write(
            to: directory.appendingPathComponent(".catalog-v1.json.temporary-OLD")
        )
        try Data("legacy".utf8).write(
            to: directory.appendingPathComponent(".catalog-v1.json.stage-OLD")
        )
        try Data("partial write".utf8).write(
            to: directory.appendingPathComponent(".catalog-v1.new.stage.write-OLD")
        )
        let unrelatedURL = directory.appendingPathComponent("notes.stage-final")
        try Data("keep me".utf8).write(to: unrelatedURL)

        let loaded = try await CatalogStore(directory: directory).load()

        XCTAssertEqual(loaded, primary)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
        try assertNoTransactionFiles(in: directory)
    }

    func testInvalidDeterministicOldStageThrowsUnrecoverableTransaction() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try encoded(makeDocument(alias: "Primary")).write(
            to: directory.appendingPathComponent("catalog-v1.json")
        )
        try Data("partial stage".utf8).write(
            to: directory.appendingPathComponent(".catalog-v1.old.stage")
        )

        do {
            _ = try await CatalogStore(directory: directory).load()
            XCTFail("Expected unrecoverable transaction")
        } catch let error as CatalogStoreError {
            XCTAssertEqual(error, .unrecoverableTransaction)
        }
    }

    func testEncodingFailurePreservesExistingPrimaryAndBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CatalogStore(directory: directory)
        try await store.save(makeDocument(alias: "First"))
        try await store.save(makeDocument(alias: "Second"))
        let primaryURL = directory.appendingPathComponent("catalog-v1.json")
        let backupURL = directory.appendingPathComponent("catalog-v1.backup.json")
        let oldPrimary = try Data(contentsOf: primaryURL)
        let oldBackup = try Data(contentsOf: backupURL)
        var invalid = makeDocument(alias: "Invalid")
        invalid.items[0].identity.position = .init(x: .nan, y: 0)

        do {
            try await store.save(invalid)
            XCTFail("Expected encoding to fail")
        } catch is EncodingError {
            // Expected exact encoding failure.
        }

        XCTAssertEqual(try Data(contentsOf: primaryURL), oldPrimary)
        XCTAssertEqual(try Data(contentsOf: backupURL), oldBackup)
    }

    func testTwoStoreInstancesSerializeConcurrentSavesAndLoads() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStore = CatalogStore(directory: directory)
        let secondStore = CatalogStore(directory: directory)
        let firstDocuments = (0..<30).map { makeDocument(alias: "A-\($0)", timestamp: Double($0)) }
        let secondDocuments = (0..<30).map { makeDocument(alias: "B-\($0)", timestamp: Double($0 + 100)) }
        let allDocuments = firstDocuments + secondDocuments

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for document in firstDocuments {
                    try await firstStore.save(document)
                    _ = try await firstStore.load()
                    await Task.yield()
                }
            }
            group.addTask {
                for document in secondDocuments {
                    try await secondStore.save(document)
                    _ = try await secondStore.load()
                    await Task.yield()
                }
            }
            try await group.waitForAll()
        }

        let primary = try decodeFile(named: "catalog-v1.json", in: directory)
        let backup = try decodeFile(named: "catalog-v1.backup.json", in: directory)
        XCTAssertTrue(allDocuments.contains(primary))
        XCTAssertTrue(allDocuments.contains(backup))
        try assertNoTransactionFiles(in: directory)
    }

    func testFailingStoreAndNormalStoreDoNotInterfereAcrossSharedDirectoryLock() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let seedStore = CatalogStore(directory: directory)
        try await seedStore.save(makeDocument(alias: "seed-1"))
        try await seedStore.save(makeDocument(alias: "seed-2"))
        let failingStore = CatalogStore(directory: directory) { stage in
            if stage == .beforeBackupReplacement {
                Thread.sleep(forTimeInterval: 0.01)
                throw SimulatedInterruption()
            }
        }
        let normalStore = CatalogStore(directory: directory)
        let normalDocuments = (0..<12).map { makeDocument(alias: "normal-\($0)") }
        let failedDocument = makeDocument(alias: "must-rollback")
        let seedDocuments = [makeDocument(alias: "seed-1"), makeDocument(alias: "seed-2")]

        async let interrupted: Void = {
            do {
                try await failingStore.save(failedDocument)
                XCTFail("Expected simulated interruption")
            } catch is SimulatedInterruption {
                // Expected.
            }
        }()
        async let normal: Void = {
            for document in normalDocuments {
                try await normalStore.save(document)
                await Task.yield()
            }
        }()
        _ = try await (interrupted, normal)

        let primary = try decodeFile(named: "catalog-v1.json", in: directory)
        let backup = try decodeFile(named: "catalog-v1.backup.json", in: directory)
        let allowedDocuments = normalDocuments + seedDocuments
        XCTAssertTrue(allowedDocuments.contains(primary))
        XCTAssertTrue(allowedDocuments.contains(backup))
        try assertNoTransactionFiles(in: directory)
    }

    func testLockPathSymlinkIsRejectedWithoutTouchingTarget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentinelURL = directory.appendingPathComponent("sentinel")
        let sentinel = Data("do not touch".utf8)
        try sentinel.write(to: sentinelURL)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent(".catalog-v1.lock"),
            withDestinationURL: sentinelURL
        )

        do {
            _ = try await CatalogStore(directory: directory).load()
            XCTFail("Expected invalid lock file")
        } catch let error as CatalogStoreError {
            XCTAssertEqual(error, .invalidLockFile)
        }
        XCTAssertEqual(try Data(contentsOf: sentinelURL), sentinel)
    }

    func testLockPathDirectoryIsRejectedWithoutDeletingIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockDirectory = directory.appendingPathComponent(".catalog-v1.lock", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: false)

        do {
            _ = try await CatalogStore(directory: directory).load()
            XCTFail("Expected invalid lock file")
        } catch let error as CatalogStoreError {
            XCTAssertEqual(error, .invalidLockFile)
        }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeDocument(
        alias: String,
        timestamp: TimeInterval = 100,
        schemaVersion: Int = 1
    ) -> CatalogDocument {
        let groupID = UUID(uuidString: "A3D49F5C-3B46-47F5-B6A7-AB8681732F48")!
        let identity = MenuBarItemIdentity(
            bundleIdentifier: "com.example.status",
            originalName: "Status",
            axIdentifier: "status-item",
            path: [0, 1],
            position: .init(x: 900, y: 0)
        )
        let item = MenuBarItemRecord(
            identity: identity,
            hostName: "Example",
            alias: alias,
            capability: .full,
            isFavorite: true,
            groupIDs: [groupID],
            manualOrder: 2,
            lastSeenAt: Date(timeIntervalSince1970: timestamp),
            successfulInvocations: [Date(timeIntervalSince1970: timestamp + 1)]
        )
        return CatalogDocument(
            schemaVersion: schemaVersion,
            items: [item],
            groups: [.init(id: groupID, name: "Utilities")],
            preferences: .default
        )
    }

    private func encoded(_ document: CatalogDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private func decodeFile(named name: String, in directory: URL) throws -> CatalogDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            CatalogDocument.self,
            from: Data(contentsOf: directory.appendingPathComponent(name))
        )
    }

    private func assertNoTransactionFiles(
        in directory: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter {
                $0 == ".catalog-v1.new.stage"
                    || $0 == ".catalog-v1.old.stage"
                    || $0 == ".catalog-v1.backup-publish.stage"
                    || $0.hasPrefix(".catalog-v1.json.temporary-")
                    || $0.hasPrefix(".catalog-v1.backup.json.temporary-")
                    || $0.hasPrefix(".catalog-v1.json.stage-")
                    || $0.hasPrefix(".catalog-v1.backup.json.stage-")
                    || $0.hasPrefix(".catalog-v1.new.stage.write-")
                    || $0.hasPrefix(".catalog-v1.old.stage.write-")
                    || $0.hasPrefix(".catalog-v1.backup-publish.stage.write-")
            }
        XCTAssertTrue(leftovers.isEmpty, "Leftover transaction files: \(leftovers)", file: file, line: line)
    }
}

private struct SimulatedInterruption: Error {}
