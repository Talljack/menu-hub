import XCTest
@testable import MenuHubCore

final class FeasibilityReportTests: XCTestCase {
    func testPendingManualChecksAreNeverRenderedAsPassing() {
        let report = FeasibilityReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            environment: .init(macOSVersion: "26.0", hardware: "Apple Silicon", screenCount: 1, hasAccessibilityPermission: false),
            automatedChecks: [
                .init(name: "AX permission", status: .blocked, evidence: "Permission not granted")
            ],
            targetApplications: FeasibilityReport.representativeTargets,
            manualChecks: [
                .init(name: "Notch display recovery", status: .pending, evidence: "Requires physical test")
            ]
        )

        let markdown = report.markdown()

        XCTAssertEqual(FeasibilityReport.representativeTargets.count, 15)
        XCTAssertTrue(markdown.contains("BLOCKED"))
        XCTAssertTrue(markdown.contains("PENDING"))
        XCTAssertTrue(markdown.contains("MVP gate: BLOCKED"))
        XCTAssertFalse(markdown.contains("MVP gate: PASS"))
    }
}
