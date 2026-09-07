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
        isIgnored: Bool = false
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
    }

    public var displayName: String {
        guard let alias, !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return identity.originalName
        }
        return alias
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
