import CryptoKit
import Foundation

/// A deliberately narrow diagnostic event. Free-form UI text, paths, process
/// names, window titles, and Accessibility payloads have no place in this type.
public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let appVersion: String?
    public let menuHubVersion: String
    public let macOSVersion: String
    public let domain: String
    public let errorCode: String?
    public let stableItemHash: String?
    public let scanCount: Int?
    public let durationMilliseconds: Int?

    public static func make(
        timestamp: Date = Date(),
        appVersion: String?,
        menuHubVersion: String,
        macOSVersion: String,
        domain: String,
        errorCode: String?,
        stableItemID: String?,
        scanCount: Int?,
        durationMilliseconds: Int?
    ) -> Self {
        Self(
            timestamp: timestamp,
            appVersion: DiagnosticRedactor.code(appVersion),
            menuHubVersion: DiagnosticRedactor.code(menuHubVersion) ?? "unknown",
            macOSVersion: DiagnosticRedactor.code(macOSVersion) ?? "unknown",
            domain: DiagnosticRedactor.code(domain) ?? "unknown",
            errorCode: DiagnosticRedactor.code(errorCode),
            stableItemHash: stableItemID.map(DiagnosticHasher.hash),
            scanCount: scanCount.map { max(0, $0) },
            durationMilliseconds: durationMilliseconds.map { max(0, $0) }
        )
    }

    fileprivate func redacted(homeDirectory: String) -> Self {
        let username = URL(fileURLWithPath: homeDirectory).lastPathComponent
        return Self(
            timestamp: timestamp,
            appVersion: DiagnosticRedactor.exportValue(appVersion, homeDirectory: homeDirectory, username: username),
            menuHubVersion: DiagnosticRedactor.exportValue(menuHubVersion, homeDirectory: homeDirectory, username: username) ?? "unknown",
            macOSVersion: DiagnosticRedactor.exportValue(macOSVersion, homeDirectory: homeDirectory, username: username) ?? "unknown",
            domain: DiagnosticRedactor.exportValue(domain, homeDirectory: homeDirectory, username: username) ?? "unknown",
            errorCode: DiagnosticRedactor.exportValue(errorCode, homeDirectory: homeDirectory, username: username),
            stableItemHash: stableItemHash,
            scanCount: scanCount,
            durationMilliseconds: durationMilliseconds
        )
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, appVersion, menuHubVersion, macOSVersion, domain
        case errorCode, stableItemHash, scanCount, durationMilliseconds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        if appVersion == nil { try container.encodeNil(forKey: .appVersion) }
        try container.encode(menuHubVersion, forKey: .menuHubVersion)
        try container.encode(macOSVersion, forKey: .macOSVersion)
        try container.encode(domain, forKey: .domain)
        try container.encodeIfPresent(errorCode, forKey: .errorCode)
        if errorCode == nil { try container.encodeNil(forKey: .errorCode) }
        try container.encodeIfPresent(stableItemHash, forKey: .stableItemHash)
        if stableItemHash == nil { try container.encodeNil(forKey: .stableItemHash) }
        try container.encodeIfPresent(scanCount, forKey: .scanCount)
        if scanCount == nil { try container.encodeNil(forKey: .scanCount) }
        try container.encodeIfPresent(durationMilliseconds, forKey: .durationMilliseconds)
        if durationMilliseconds == nil { try container.encodeNil(forKey: .durationMilliseconds) }
    }
}

public struct DiagnosticArchive: Codable, Equatable, Sendable {
    public let events: [DiagnosticEvent]

    public static func make(events: [DiagnosticEvent], homeDirectory: String) -> Self {
        Self(events: events.map { $0.redacted(homeDirectory: homeDirectory) })
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// A memory-only FIFO capped by both encoded size and age.
public struct DiagnosticRingBuffer: Sendable {
    public static let defaultMaximumBytes = 2 * 1_024 * 1_024
    public static let defaultRetentionInterval: TimeInterval = 7 * 24 * 60 * 60

    public let maxBytes: Int
    public let retentionInterval: TimeInterval
    public private(set) var events: [DiagnosticEvent] = []

    public init(
        maxBytes: Int = Self.defaultMaximumBytes,
        retentionInterval: TimeInterval = Self.defaultRetentionInterval
    ) {
        self.maxBytes = max(0, maxBytes)
        self.retentionInterval = max(0, retentionInterval)
    }

    public mutating func append(_ event: DiagnosticEvent, now: Date = Date()) {
        events.append(event)
        prune(now: now)
    }

    public mutating func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        events.removeAll { $0.timestamp < cutoff }

        while !events.isEmpty && encodedSize() > maxBytes {
            events.removeFirst()
        }
    }

    public func archive(homeDirectory: String) -> DiagnosticArchive {
        .make(events: events, homeDirectory: homeDirectory)
    }

    private func encodedSize() -> Int {
        (try? DiagnosticArchive(events: events).jsonData().count) ?? Int.max
    }
}

private enum DiagnosticHasher {
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private enum DiagnosticRedactor {
    private static let allowedCodeScalars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-+()"))

    static func code(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let truncated = String(value.unicodeScalars.prefix(128))
        guard truncated.unicodeScalars.allSatisfy(allowedCodeScalars.contains) else { return "redacted" }
        return truncated
    }

    static func exportValue(_ value: String?, homeDirectory: String, username: String) -> String? {
        guard let value else { return nil }
        guard !value.localizedCaseInsensitiveContains(homeDirectory),
              username.isEmpty || !value.localizedCaseInsensitiveContains(username)
        else { return "redacted" }
        return code(value)
    }
}
