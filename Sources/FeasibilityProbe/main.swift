import AppKit
import Foundation
import MenuHubCore

@main
enum FeasibilityProbeCommand {
    static func main() async {
        let arguments = CommandLine.arguments
        if arguments.contains("--prompt") {
            _ = AccessibilityClient.isTrusted(prompt: true)
        }

        let trusted = AccessibilityClient.isTrusted()
        let client = AccessibilityClient()
        let scan = await client.scanRunningApplications()
        let outputURL = outputURL(from: arguments)
        let pressCheck = await requestedPressCheck(arguments: arguments, snapshots: scan.snapshots, client: client)
        let discoveryStatus: FeasibilityReport.Status = trusted
            ? (scan.snapshots.isEmpty ? .fail : .pass)
            : .blocked
        let discoveredNames = scan.snapshots.compactMap(\.title)
        let targets = FeasibilityReport.representativeTargets.map { target in
            guard let match = discoveredNames.first(where: { $0.localizedCaseInsensitiveContains(target.name) }) else {
                return target
            }
            return FeasibilityReport.Target(
                name: target.name,
                category: target.category,
                status: .pending,
                evidence: "Discovery candidate matched '\(match)'; hidden-state press still requires user verification."
            )
        }

        let report = FeasibilityReport(
            generatedAt: Date(),
            environment: .init(
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                hardware: hardwareDescription,
                screenCount: NSScreen.screens.count,
                hasAccessibilityPermission: trusted
            ),
            automatedChecks: [
                .init(name: "Public API build", status: .pass, evidence: "Probe is running with AppKit and ApplicationServices."),
                .init(name: "Accessibility permission", status: trusted ? .pass : .blocked, evidence: trusted ? "AXIsProcessTrusted returned true." : "Grant permission from an explicit app action, then rerun."),
                .init(name: "Menu-bar candidate discovery", status: discoveryStatus, evidence: "Found \(scan.snapshots.count) candidate(s). \(scan.errors.joined(separator: " "))"),
                pressCheck,
            ],
            targetApplications: targets,
            manualChecks: manualChecks
        )

        do {
            try report.markdown().write(to: outputURL, atomically: true, encoding: .utf8)
            print("Wrote \(outputURL.path)")
            print("Candidates: \(scan.snapshots.count)")
            print("MVP gate: \(report.gateStatus.rawValue)")
            printCandidates(scan.snapshots)
        } catch {
            FileHandle.standardError.write(Data("Failed to write report: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func requestedPressCheck(
        arguments: [String],
        snapshots: [AccessibilitySnapshot],
        client: AccessibilityClient
    ) async -> FeasibilityReport.Check {
        guard let flag = arguments.firstIndex(of: "--press-index"),
              arguments.indices.contains(flag + 1),
              let index = Int(arguments[flag + 1]),
              snapshots.indices.contains(index) else {
            return .init(name: "Hidden-item AXPress", status: .pending, evidence: "Collapse the spacer, then rerun with --press-index N for an explicitly selected candidate.")
        }

        let target = snapshots[index]
        let result = await client.press(target)
        switch result {
        case .success:
            return .init(name: "User-selected AXPress", status: .pass, evidence: "Pressed candidate \(index), '\(target.title ?? target.processName)'. Confirm popup placement and hidden state manually.")
        case .failure(let error):
            return .init(name: "User-selected AXPress", status: .fail, evidence: "Candidate \(index), '\(target.title ?? target.processName)', failed as \(error.rawValue).")
        }
    }

    private static func printCandidates(_ snapshots: [AccessibilitySnapshot]) {
        guard !snapshots.isEmpty else { return }
        print("Candidate index | Host | Name | Actions")
        for (index, snapshot) in snapshots.enumerated() {
            print("\(index) | \(snapshot.processName) | \(snapshot.title ?? "unnamed") | \(snapshot.actions.joined(separator: ",")) | \(snapshot.diagnosticSummary)")
        }
    }

    private static func outputURL(from arguments: [String]) -> URL {
        guard let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) else {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("FeasibilityReport.md")
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    private static var hardwareDescription: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #else
        return "Intel (x86_64)"
        #endif
    }

    private static let manualChecks: [FeasibilityReport.Check] = [
        .init(name: "1000 collapse/reveal cycles", status: .pending, evidence: "Run the repeatable UI protocol."),
        .init(name: "Built-in notch display", status: .pending, evidence: "Requires visual and click validation on notch hardware."),
        .init(name: "External display hot-plug", status: .pending, evidence: "Requires physical external display."),
        .init(name: "Scaled resolution change", status: .pending, evidence: "Requires interactive display setting change."),
        .init(name: "Full-screen application", status: .pending, evidence: "Requires interactive full-screen test."),
        .init(name: "Sleep and wake recovery", status: .pending, evidence: "Requires repeated physical sleep/wake."),
        .init(name: "SystemUIServer restart recovery", status: .pending, evidence: "Requires interactive recovery observation."),
        .init(name: "Hidden item remains AXPress actionable", status: .pending, evidence: "Requires explicit user-selected target press."),
    ]
}
