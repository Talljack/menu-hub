import ApplicationServices
import Foundation

public enum AccessibilityDomainError: String, Error, Codable, Equatable, Sendable {
    case permissionDenied
    case elementNotFound
    case actionUnsupported
    case targetUnresponsive
    case staleElement
    case ambiguousMatch
    case unknown

    public init(axError: AXError) {
        switch axError {
        case .apiDisabled:
            self = .permissionDenied
        case .invalidUIElement, .invalidUIElementObserver:
            self = .staleElement
        case .actionUnsupported, .attributeUnsupported, .parameterizedAttributeUnsupported:
            self = .actionUnsupported
        case .cannotComplete:
            self = .targetUnresponsive
        case .noValue:
            self = .elementNotFound
        default:
            self = .unknown
        }
    }
}

public enum ItemCapability: String, Codable, Equatable, Sendable {
    case full
    case actionable
    case launchOnly
    case unavailable

    public static func classify(hasName: Bool, actions: [String], canLaunchHost: Bool) -> Self {
        if actions.contains(kAXPressAction as String) {
            return hasName ? .full : .actionable
        }
        return canLaunchHost ? .launchOnly : .unavailable
    }
}

public struct AccessibilitySnapshot: Codable, Equatable, Sendable {
    public let processIdentifier: Int32
    public let processName: String
    public let bundleIdentifier: String?
    public let title: String?
    public let role: String?
    public let subrole: String?
    public let identifier: String?
    public let positionX: Double?
    public let positionY: Double?
    public let width: Double?
    public let height: Double?
    public let actions: [String]
    public let accessibilityPath: [Int]

    public init(
        processIdentifier: Int32,
        processName: String,
        bundleIdentifier: String?,
        title: String?,
        role: String?,
        subrole: String?,
        identifier: String?,
        positionX: Double?,
        positionY: Double?,
        width: Double?,
        height: Double?,
        actions: [String],
        accessibilityPath: [Int]
    ) {
        self.processIdentifier = processIdentifier
        self.processName = processName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.positionX = positionX
        self.positionY = positionY
        self.width = width
        self.height = height
        self.actions = actions
        self.accessibilityPath = accessibilityPath
    }

    public var diagnosticSummary: String {
        "x=\(Self.format(positionX)) y=\(Self.format(positionY)) width=\(Self.format(width)) height=\(Self.format(height))"
    }

    private static func format(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "unknown"
    }
}
