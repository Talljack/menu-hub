@preconcurrency import ApplicationServices
import Foundation

public enum AccessibilityScanIssue: Codable, Equatable, Sendable {
    case permissionDenied
    case traversalLimit(process: String)
    case targetUnresponsive(process: String?)
    case processFailure(
        processIdentifier: Int32?,
        process: String,
        error: AccessibilityDomainError
    )

    public var message: String {
        switch self {
        case .permissionDenied:
            return "Accessibility permission is not granted."
        case .traversalLimit(let process):
            return "Traversal limit reached for \(process)."
        case .targetUnresponsive(let process):
            return process.map { "\($0) did not respond to accessibility inspection." }
                ?? "Accessibility inspection did not respond."
        case .processFailure(let processIdentifier, let process, let error):
            let pid = processIdentifier.map { " (pid \($0))" } ?? ""
            return "\(process)\(pid): \(error.rawValue)"
        }
    }

    static func issue(
        for error: AXError,
        processIdentifier: Int32?,
        process: String
    ) -> Self? {
        switch error {
        case .success, .noValue, .attributeUnsupported, .actionUnsupported,
             .parameterizedAttributeUnsupported:
            return nil
        case .apiDisabled:
            return .permissionDenied
        default:
            return .processFailure(
                processIdentifier: processIdentifier,
                process: process,
                error: AccessibilityDomainError(axError: error)
            )
        }
    }
}

public struct AccessibilityScanResult: Sendable, Equatable {
    public let snapshots: [AccessibilitySnapshot]
    public let issues: [AccessibilityScanIssue]
    private let legacyErrors: [String]?

    public var errors: [String] {
        legacyErrors ?? issues.map(\.message)
    }

    public init(snapshots: [AccessibilitySnapshot], errors: [String]) {
        self.snapshots = snapshots
        self.issues = errors.map {
            .processFailure(processIdentifier: nil, process: $0, error: .unknown)
        }
        self.legacyErrors = errors
    }

    public init(snapshots: [AccessibilitySnapshot], issues: [AccessibilityScanIssue]) {
        self.snapshots = snapshots
        self.issues = issues
        self.legacyErrors = nil
    }
}

public protocol AccessibilityServing: Sendable {
    func scan() async -> AccessibilityScanResult
    /// Re-reads already discovered elements without traversing every running application's AX tree.
    func refresh(_ snapshots: [AccessibilitySnapshot]) async -> AccessibilityScanResult
    func press(_ snapshot: AccessibilitySnapshot) async -> Result<Void, AccessibilityDomainError>
}

public extension AccessibilityServing {
    func refresh(_ snapshots: [AccessibilitySnapshot]) async -> AccessibilityScanResult {
        AccessibilityScanResult(snapshots: snapshots, issues: [])
    }
}

extension AccessibilitySnapshot {
    var menuBarItemIdentity: MenuBarItemIdentity {
        MenuBarItemIdentity.accessibilityIdentity(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            processName: processName,
            title: title,
            identifier: identifier,
            path: accessibilityPath,
            positionX: positionX,
            positionY: positionY
        )
    }
}

extension MenuBarItemIdentity {
    static func accessibilityIdentity(
        processIdentifier: Int32,
        bundleIdentifier: String?,
        processName: String,
        title: String?,
        identifier: String?,
        path: [Int],
        positionX: Double?,
        positionY: Double?
    ) -> Self {
        let position: MenuBarItemPosition? = if let positionX, let positionY {
            MenuBarItemPosition(x: positionX, y: positionY)
        } else {
            nil
        }
        return Self(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier ?? processName,
            originalName: title ?? processName,
            axIdentifier: identifier,
            path: path,
            position: position
        )
    }
}
