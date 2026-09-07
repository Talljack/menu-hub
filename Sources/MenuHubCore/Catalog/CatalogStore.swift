import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum CatalogStoreError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case corruptPrimaryAndBackup
    case unrecoverableTransaction
    case invalidLockFile
}

enum CatalogStoreSaveStage: Equatable, Sendable {
    case beforePrimaryReplacement
    case beforeBackupReplacement
}

public actor CatalogStore {
    private static let supportedSchemaVersion = 1
    private static let primaryFileName = "catalog-v1.json"
    private static let backupFileName = "catalog-v1.backup.json"
    private static let newStageFileName = ".catalog-v1.new.stage"
    private static let oldStageFileName = ".catalog-v1.old.stage"
    private static let backupPublishStageFileName = ".catalog-v1.backup-publish.stage"
    private static let lockFileName = ".catalog-v1.lock"

    private let directory: URL
    private let saveHook: @Sendable (CatalogStoreSaveStage) throws -> Void

    public init(directory: URL) {
        self.directory = directory
        self.saveHook = { _ in }
    }

    init(
        directory: URL,
        saveHook: @escaping @Sendable (CatalogStoreSaveStage) throws -> Void
    ) {
        self.directory = directory
        self.saveHook = saveHook
    }

    public func load() throws -> CatalogDocument {
        try ensureDirectoryExists()
        return try withExclusiveDirectoryLock {
            try loadWhileLocked()
        }
    }

    private func loadWhileLocked() throws -> CatalogDocument {
        let fileManager = FileManager.default
        try recoverPendingTransaction()

        let primaryURL = url(for: Self.primaryFileName)
        let backupURL = url(for: Self.backupFileName)
        guard fileManager.fileExists(atPath: primaryURL.path) else {
            guard fileManager.fileExists(atPath: backupURL.path) else {
                return .empty
            }
            return try restoreMissingPrimary(from: backupURL)
        }

        let primaryData = try Data(contentsOf: primaryURL)
        do {
            return try decodeDocument(from: primaryData)
        } catch let error as CatalogStoreError {
            throw error
        } catch {
            guard fileManager.fileExists(atPath: backupURL.path) else {
                throw CatalogStoreError.corruptPrimaryAndBackup
            }
            let backupData = try Data(contentsOf: backupURL)
            do {
                let document = try decodeDocument(from: backupData)
                try repairPrimary(with: backupData)
                return document
            } catch let error as CatalogStoreError {
                throw error
            } catch {
                throw CatalogStoreError.corruptPrimaryAndBackup
            }
        }
    }

    public func save(_ document: CatalogDocument) throws {
        try ensureDirectoryExists()
        try withExclusiveDirectoryLock {
            try saveWhileLocked(document)
        }
    }

    /// Removes the primary, backup, and transaction artifacts while retaining the lock file.
    /// This is used only after an explicit destructive confirmation from the user.
    public func clearAll() throws {
        try ensureDirectoryExists()
        try withExclusiveDirectoryLock {
            for name in [
                Self.primaryFileName, Self.backupFileName, Self.newStageFileName,
                Self.oldStageFileName, Self.backupPublishStageFileName
            ] {
                try removeArtifactIfPresent(at: url(for: name))
            }
        }
    }

    private func saveWhileLocked(_ document: CatalogDocument) throws {
        try recoverPendingTransaction()

        guard document.schemaVersion == Self.supportedSchemaVersion else {
            throw CatalogStoreError.unsupportedSchema(document.schemaVersion)
        }

        let encoded = try encode(document)
        let fileManager = FileManager.default
        let primaryURL = url(for: Self.primaryFileName)
        let backupURL = url(for: Self.backupFileName)
        let newStageURL = url(for: Self.newStageFileName)
        let oldStageURL = url(for: Self.oldStageFileName)
        let backupPublishStageURL = url(for: Self.backupPublishStageFileName)
        var preserveOldStageForRecovery = false

        defer {
            try? removeArtifactIfPresent(at: newStageURL)
            try? removeArtifactIfPresent(at: backupPublishStageURL)
            if !preserveOldStageForRecovery {
                try? removeArtifactIfPresent(at: oldStageURL)
            }
        }

        try writeSynchronized(encoded, to: newStageURL)

        guard fileManager.fileExists(atPath: primaryURL.path) else {
            try saveHook(.beforePrimaryReplacement)
            do {
                try atomicallyReplace(itemAt: newStageURL, destination: primaryURL)
            } catch {
                let publicationError = error
                if !fileManager.fileExists(atPath: newStageURL.path) {
                    do {
                        try removeArtifactIfPresent(at: primaryURL)
                    } catch {
                        throw CatalogStoreError.unrecoverableTransaction
                    }
                }
                throw publicationError
            }
            return
        }

        let previousData = try Data(contentsOf: primaryURL)
        _ = try decodeDocument(from: previousData)
        let previousBackupData = fileManager.fileExists(atPath: backupURL.path)
            ? try Data(contentsOf: backupURL)
            : nil
        try writeSynchronized(previousData, to: oldStageURL)
        try saveHook(.beforePrimaryReplacement)
        do {
            try atomicallyReplace(itemAt: newStageURL, destination: primaryURL)
        } catch {
            let publicationError = error
            if !fileManager.fileExists(atPath: newStageURL.path) {
                do {
                    try atomicallyReplace(itemAt: oldStageURL, destination: primaryURL)
                } catch {
                    preserveOldStageForRecovery = true
                    throw CatalogStoreError.unrecoverableTransaction
                }
            }
            throw publicationError
        }

        do {
            try writeSynchronized(previousData, to: backupPublishStageURL)
            try saveHook(.beforeBackupReplacement)
            try atomicallyReplace(itemAt: backupPublishStageURL, destination: backupURL)
        } catch {
            let transactionError = error
            if !fileManager.fileExists(atPath: backupPublishStageURL.path) {
                do {
                    if let previousBackupData {
                        try writeSynchronized(previousBackupData, to: backupPublishStageURL)
                        try atomicallyReplace(itemAt: backupPublishStageURL, destination: backupURL)
                    } else {
                        try removeArtifactIfPresent(at: backupURL)
                    }
                } catch {
                    preserveOldStageForRecovery = true
                    throw CatalogStoreError.unrecoverableTransaction
                }
            }
            do {
                try atomicallyReplace(itemAt: oldStageURL, destination: primaryURL)
            } catch {
                preserveOldStageForRecovery = true
                throw CatalogStoreError.unrecoverableTransaction
            }
            throw transactionError
        }
    }

    private func restoreMissingPrimary(from backupURL: URL) throws -> CatalogDocument {
        let backupData = try Data(contentsOf: backupURL)
        let document: CatalogDocument
        do {
            document = try decodeDocument(from: backupData)
        } catch let error as CatalogStoreError {
            throw error
        } catch {
            throw CatalogStoreError.corruptPrimaryAndBackup
        }
        try repairPrimary(with: backupData)
        return document
    }

    private func recoverPendingTransaction() throws {
        let fileManager = FileManager.default
        let primaryURL = url(for: Self.primaryFileName)
        let backupURL = url(for: Self.backupFileName)
        let newStageURL = url(for: Self.newStageFileName)
        let oldStageURL = url(for: Self.oldStageFileName)
        let backupPublishStageURL = url(for: Self.backupPublishStageFileName)
        let hasPrimary = fileManager.fileExists(atPath: primaryURL.path)
        let hasOldStage = fileManager.fileExists(atPath: oldStageURL.path)
        let hasNewStage = fileManager.fileExists(atPath: newStageURL.path)

        // A completed primary rename consumes newStage, so both stages with a
        // valid primary can only be an abandoned pre-publication transaction.
        if hasOldStage, hasNewStage, hasPrimary {
            try validateTransactionArtifact(at: primaryURL)
            try removeArtifactIfPresent(at: oldStageURL)
            try removeArtifactIfPresent(at: newStageURL)
        } else if hasOldStage {
            try validateTransactionArtifact(at: oldStageURL)
            if hasPrimary {
                try validateTransactionArtifact(at: primaryURL)
                try atomicallyReplace(itemAt: oldStageURL, destination: backupURL)
            } else {
                try atomicallyReplace(itemAt: oldStageURL, destination: primaryURL)
            }
            if hasNewStage, fileManager.fileExists(atPath: newStageURL.path) {
                try removeArtifactIfPresent(at: newStageURL)
            }
        } else if hasNewStage {
            if hasPrimary {
                try validateTransactionArtifact(at: primaryURL)
                try removeArtifactIfPresent(at: newStageURL)
            } else {
                try validateTransactionArtifact(at: newStageURL)
                try atomicallyReplace(itemAt: newStageURL, destination: primaryURL)
            }
        }

        try removeArtifactIfPresent(at: backupPublishStageURL)

        try cleanLegacyTransactionArtifacts()
    }

    private func validateTransactionArtifact(at url: URL) throws {
        let data = try Data(contentsOf: url)
        do {
            _ = try decodeDocument(from: data)
        } catch let error as CatalogStoreError {
            throw error
        } catch {
            throw CatalogStoreError.unrecoverableTransaction
        }
    }

    private func cleanLegacyTransactionArtifacts() throws {
        let fileManager = FileManager.default
        let names = try fileManager.contentsOfDirectory(atPath: directory.path)
        let ownedPrefixes = [
            ".catalog-v1.json.temporary-",
            ".catalog-v1.backup.json.temporary-",
            ".catalog-v1.json.stage-",
            ".catalog-v1.backup.json.stage-",
            ".catalog-v1.new.stage.write-",
            ".catalog-v1.old.stage.write-",
            ".catalog-v1.backup-publish.stage.write-",
        ]
        for name in names where ownedPrefixes.contains(where: name.hasPrefix) {
            try removeArtifactIfPresent(at: url(for: name))
        }
    }

    private func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func encode(_ document: CatalogDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let timestamp = date.timeIntervalSince1970
            guard timestamp.isFinite else {
                throw EncodingError.invalidValue(
                    date,
                    .init(codingPath: encoder.codingPath, debugDescription: "Date must be finite")
                )
            }
            var wholeSeconds = floor(timestamp)
            var nanoseconds = Int(((timestamp - wholeSeconds) * 1_000_000_000).rounded())
            if nanoseconds == 1_000_000_000 {
                wholeSeconds += 1
                nanoseconds = 0
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            var value = formatter.string(from: Date(timeIntervalSince1970: wholeSeconds))
            if nanoseconds != 0 {
                let fraction = String(format: "%09d", nanoseconds)
                    .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                value.removeLast()
                value += ".\(fraction)Z"
            }
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private func decodeDocument(from data: Data) throws -> CatalogDocument {
        struct VersionEnvelope: Decodable {
            let schemaVersion: Int
        }

        let decoder = JSONDecoder()
        let version = try decoder.decode(VersionEnvelope.self, from: data).schemaVersion
        guard version == Self.supportedSchemaVersion else {
            throw CatalogStoreError.unsupportedSchema(version)
        }
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let wholeSecondFormatter = ISO8601DateFormatter()
            wholeSecondFormatter.formatOptions = [.withInternetDateTime]
            if let decimalIndex = value.firstIndex(of: "."),
               let zoneIndex = value[value.index(after: decimalIndex)...]
                .firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
                let digits = value[value.index(after: decimalIndex)..<zoneIndex]
                let wholeValue = String(value[..<decimalIndex]) + String(value[zoneIndex...])
                if let wholeDate = wholeSecondFormatter.date(from: wholeValue),
                   let fraction = Double("0.\(digits)") {
                    return wholeDate.addingTimeInterval(fraction)
                }
            }
            if let date = wholeSecondFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date"
            )
        }
        return try decoder.decode(CatalogDocument.self, from: data)
    }

    private func repairPrimary(with data: Data) throws {
        let newStageURL = url(for: Self.newStageFileName)
        do {
            try writeSynchronized(data, to: newStageURL)
            try atomicallyReplace(itemAt: newStageURL, destination: url(for: Self.primaryFileName))
        } catch {
            try? removeArtifactIfPresent(at: newStageURL)
            throw error
        }
    }

    private func writeSynchronized(_ data: Data, to url: URL) throws {
        let temporaryURL = directory.appendingPathComponent(
            "\(url.lastPathComponent).write-\(UUID().uuidString)"
        )
        defer { try? removeArtifactIfPresent(at: temporaryURL) }

        let descriptor = temporaryURL.path.withCString {
            open(
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(S_IRUSR | S_IWUSR)
            )
        }
        guard descriptor >= 0 else { throw currentPOSIXError() }

        var isOpen = true
        defer {
            if isOpen { _ = close(descriptor) }
        }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written: Int
                #if canImport(Darwin)
                written = Darwin.write(descriptor, baseAddress.advanced(by: offset), rawBuffer.count - offset)
                #else
                written = Glibc.write(descriptor, baseAddress.advanced(by: offset), rawBuffer.count - offset)
                #endif
                if written < 0, errno == EINTR { continue }
                if written == 0 { throw POSIXError(.EIO) }
                guard written > 0 else { throw currentPOSIXError() }
                offset += written
            }
        }

        try synchronizeFileDescriptor(descriptor)
        guard close(descriptor) == 0 else {
            isOpen = false
            throw currentPOSIXError()
        }
        isOpen = false
        try synchronizeDirectory()
        try atomicallyReplace(itemAt: temporaryURL, destination: url)
    }

    private func atomicallyReplace(itemAt source: URL, destination: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else { throw currentPOSIXError() }
        try synchronizeDirectory()
    }

    private func removeArtifactIfPresent(at url: URL) throws {
        let result = url.path.withCString { unlink($0) }
        if result != 0 {
            if errno == ENOENT { return }
            throw currentPOSIXError()
        }
        try synchronizeDirectory()
    }

    private func synchronizeDirectory() throws {
        let descriptor = directory.path.withCString { open($0, O_RDONLY) }
        guard descriptor >= 0 else { throw currentPOSIXError() }
        var isOpen = true
        defer {
            if isOpen { _ = close(descriptor) }
        }
        try synchronizeFileDescriptor(descriptor)
        guard close(descriptor) == 0 else {
            isOpen = false
            throw currentPOSIXError()
        }
        isOpen = false
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private func synchronizeFileDescriptor(_ descriptor: Int32) throws {
        while fsync(descriptor) != 0 {
            if errno == EINTR { continue }
            throw currentPOSIXError()
        }
    }

    private func withExclusiveDirectoryLock<T>(_ body: () throws -> T) throws -> T {
        let descriptor = url(for: Self.lockFileName).path.withCString {
            open(
                $0,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                mode_t(S_IRUSR | S_IWUSR)
            )
        }
        guard descriptor >= 0 else {
            if errno == ELOOP || errno == EISDIR {
                throw CatalogStoreError.invalidLockFile
            }
            throw currentPOSIXError()
        }

        var fileStatus = stat()
        guard fstat(descriptor, &fileStatus) == 0 else {
            let error = currentPOSIXError()
            _ = close(descriptor)
            throw error
        }
        guard fileStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            _ = close(descriptor)
            throw CatalogStoreError.invalidLockFile
        }

        do {
            try changeLock(descriptor, operation: LOCK_EX)
        } catch {
            _ = close(descriptor)
            throw error
        }
        defer {
            try? changeLock(descriptor, operation: LOCK_UN)
            _ = close(descriptor)
        }
        return try body()
    }

    private func changeLock(_ descriptor: Int32, operation: Int32) throws {
        while flock(descriptor, operation) != 0 {
            if errno == EINTR { continue }
            throw currentPOSIXError()
        }
    }

    private func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }
}
