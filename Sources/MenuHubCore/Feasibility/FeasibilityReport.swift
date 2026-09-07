import Foundation

public struct FeasibilityReport: Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case pass = "PASS"
        case fail = "FAIL"
        case blocked = "BLOCKED"
        case pending = "PENDING"
    }

    public struct Environment: Equatable, Sendable {
        public let macOSVersion: String
        public let hardware: String
        public let screenCount: Int
        public let hasAccessibilityPermission: Bool

        public init(macOSVersion: String, hardware: String, screenCount: Int, hasAccessibilityPermission: Bool) {
            self.macOSVersion = macOSVersion
            self.hardware = hardware
            self.screenCount = screenCount
            self.hasAccessibilityPermission = hasAccessibilityPermission
        }
    }

    public struct Check: Equatable, Sendable {
        public let name: String
        public let status: Status
        public let evidence: String

        public init(name: String, status: Status, evidence: String) {
            self.name = name
            self.status = status
            self.evidence = evidence
        }
    }

    public struct Target: Equatable, Sendable {
        public let name: String
        public let category: String
        public let status: Status
        public let evidence: String

        public init(name: String, category: String, status: Status = .pending, evidence: String = "Not tested on this machine") {
            self.name = name
            self.category = category
            self.status = status
            self.evidence = evidence
        }
    }

    public static let representativeTargets: [Target] = [
        .init(name: "Wi-Fi", category: "System"),
        .init(name: "Bluetooth", category: "System"),
        .init(name: "Sound", category: "System"),
        .init(name: "Battery", category: "System"),
        .init(name: "VPN A", category: "VPN"),
        .init(name: "VPN B", category: "VPN"),
        .init(name: "Sync A", category: "Cloud sync"),
        .init(name: "Sync B", category: "Cloud sync"),
        .init(name: "Recorder A", category: "Screen recording"),
        .init(name: "Recorder B", category: "Screen recording"),
        .init(name: "Container tool", category: "Development"),
        .init(name: "Audio tool", category: "Audio"),
        .init(name: "Clipboard tool", category: "Productivity"),
        .init(name: "AI tool", category: "AI"),
        .init(name: "Developer tool", category: "Development"),
    ]

    public let generatedAt: Date
    public let environment: Environment
    public let automatedChecks: [Check]
    public let targetApplications: [Target]
    public let manualChecks: [Check]

    public init(
        generatedAt: Date,
        environment: Environment,
        automatedChecks: [Check],
        targetApplications: [Target],
        manualChecks: [Check]
    ) {
        self.generatedAt = generatedAt
        self.environment = environment
        self.automatedChecks = automatedChecks
        self.targetApplications = targetApplications
        self.manualChecks = manualChecks
    }

    public var gateStatus: Status {
        let statuses = automatedChecks.map(\.status) + targetApplications.map(\.status) + manualChecks.map(\.status)
        if statuses.contains(.fail) { return .fail }
        if statuses.contains(.blocked) || statuses.contains(.pending) { return .blocked }
        return statuses.isEmpty ? .blocked : .pass
    }

    public func markdown() -> String {
        let timestamp = ISO8601DateFormatter().string(from: generatedAt)
        var lines = [
            "# Menu Hub Phase 0 Feasibility Report",
            "",
            "Generated: \(timestamp)",
            "",
            "MVP gate: \(gateStatus.rawValue)",
            "",
            "> A build result is not hardware compatibility evidence. PENDING and BLOCKED checks must not be treated as passing.",
            "",
            "## Environment",
            "",
            "- macOS: \(environment.macOSVersion)",
            "- Hardware: \(environment.hardware)",
            "- Screens detected: \(environment.screenCount)",
            "- Accessibility trusted: \(environment.hasAccessibilityPermission ? "yes" : "no")",
            "",
            "## Automated checks",
            "",
            "| Check | Status | Evidence |",
            "|---|---|---|",
        ]
        lines += automatedChecks.map { "| \($0.name) | \($0.status.rawValue) | \($0.evidence) |" }
        lines += [
            "",
            "## Representative target matrix",
            "",
            "| Target | Category | Status | Evidence |",
            "|---|---|---|---|",
        ]
        lines += targetApplications.map { "| \($0.name) | \($0.category) | \($0.status.rawValue) | \($0.evidence) |" }
        lines += [
            "",
            "## Manual layout and recovery checks",
            "",
            "| Check | Status | Evidence |",
            "|---|---|---|",
        ]
        lines += manualChecks.map { "| \($0.name) | \($0.status.rawValue) | \($0.evidence) |" }
        lines += [
            "",
            "## Decision",
            "",
            gateStatus == .pass
                ? "All mandatory Phase 0 evidence is present; MVP work may begin."
                : "MVP implementation is stopped at the Phase 0 gate until discovery, hidden-item press, restoration, and the hardware matrix are empirically verified.",
            "",
        ]
        return lines.joined(separator: "\n")
    }
}
