import Foundation

public struct MenuBarItemPosition: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct MenuBarItemIdentity: Codable, Hashable, Sendable {
    public var processIdentifier: Int32?
    public var bundleIdentifier: String
    public var originalName: String
    public var axIdentifier: String?
    public var path: [Int]
    public var position: MenuBarItemPosition?

    public init(
        processIdentifier: Int32? = nil,
        bundleIdentifier: String,
        originalName: String,
        axIdentifier: String?,
        path: [Int],
        position: MenuBarItemPosition? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.originalName = originalName
        self.axIdentifier = axIdentifier
        self.path = path
        self.position = position
    }

    public var stableID: String {
        let bundle = Self.normalizedHumanReadable(bundleIdentifier)
        if let identifier = axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identifier.isEmpty {
            return "\(bundle)|ax:\(identifier)"
        }
        let normalizedName = Self.normalizedHumanReadable(originalName)
        let encodedPath = path.map(String.init).joined(separator: ".")
        return "\(bundle)|name:\(normalizedName)|path:\(encodedPath)"
    }

    private static func normalizedHumanReadable(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public struct MenuBarItemRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var identity: MenuBarItemIdentity
    public var hostName: String
    public var hostBundleIdentifier: String?
    public var alias: String?
    public var capability: ItemCapability
    public var isFavorite: Bool
    public var groupIDs: [UUID]
    public var manualOrder: Int
    public var lastSeenAt: Date
    public var successfulInvocations: [Date]
    public var lastError: AccessibilityDomainError?
    public var isIgnored: Bool
    public var unreadBadgePreference: UnreadBadgePreference

    public init(
        id: String? = nil,
        identity: MenuBarItemIdentity,
        hostName: String,
        hostBundleIdentifier: String? = nil,
        alias: String? = nil,
        capability: ItemCapability,
        isFavorite: Bool = false,
        groupIDs: [UUID] = [],
        manualOrder: Int = 0,
        lastSeenAt: Date,
        successfulInvocations: [Date] = [],
        lastError: AccessibilityDomainError? = nil,
        isIgnored: Bool = false,
        unreadBadgePreference: UnreadBadgePreference = .automatic
    ) {
        self.id = id ?? identity.stableID
        self.identity = identity
        self.hostName = hostName
        self.hostBundleIdentifier = hostBundleIdentifier
        self.alias = alias
        self.capability = capability
        self.isFavorite = isFavorite
        self.groupIDs = groupIDs
        self.manualOrder = manualOrder
        self.lastSeenAt = lastSeenAt
        self.successfulInvocations = successfulInvocations
        self.lastError = lastError
        self.isIgnored = isIgnored
        self.unreadBadgePreference = unreadBadgePreference
    }

    public var displayName: String {
        guard let alias, !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return identity.originalName
        }
        return alias
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case identity
        case hostName
        case hostBundleIdentifier
        case alias
        case capability
        case isFavorite
        case groupIDs
        case manualOrder
        case lastSeenAt
        case successfulInvocations
        case lastError
        case isIgnored
        case unreadBadgePreference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        identity = try container.decode(MenuBarItemIdentity.self, forKey: .identity)
        hostName = try container.decode(String.self, forKey: .hostName)
        hostBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .hostBundleIdentifier)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        capability = try container.decode(ItemCapability.self, forKey: .capability)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        groupIDs = try container.decode([UUID].self, forKey: .groupIDs)
        manualOrder = try container.decode(Int.self, forKey: .manualOrder)
        lastSeenAt = try container.decode(Date.self, forKey: .lastSeenAt)
        successfulInvocations = try container.decode([Date].self, forKey: .successfulInvocations)
        lastError = try container.decodeIfPresent(AccessibilityDomainError.self, forKey: .lastError)
        isIgnored = try container.decode(Bool.self, forKey: .isIgnored)
        let rawPreference = try container.decodeIfPresent(String.self, forKey: .unreadBadgePreference)
        unreadBadgePreference = rawPreference.flatMap(UnreadBadgePreference.init(rawValue:)) ?? .automatic
    }
}

public struct GroupRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var manualOrder: Int

    public init(id: UUID = UUID(), name: String, manualOrder: Int = 0) {
        self.id = id
        self.name = name
        self.manualOrder = manualOrder
    }
}
