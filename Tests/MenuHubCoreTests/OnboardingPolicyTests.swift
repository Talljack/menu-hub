import XCTest
@testable import MenuHubCore

final class OnboardingPolicyTests: XCTestCase {
    func testPermissionMayBeSkippedIntoLauncherMode() {
        XCTAssertEqual(
            OnboardingPolicy.next(after: .permission, choice: .skip),
            .scanSummary(mode: .launcher)
        )
    }

    func testAuthorizedReturnAdvancesInFullMode() {
        XCTAssertEqual(
            OnboardingPolicy.next(after: .permission, choice: .authorized),
            .scanSummary(mode: .full)
        )
    }

    func testFlowContainsEveryRequiredStep() {
        XCTAssertEqual(OnboardingPolicy.next(after: .welcome, choice: .continue), .capabilityBoundary)
        XCTAssertEqual(OnboardingPolicy.next(after: .capabilityBoundary, choice: .continue), .permission)
        XCTAssertEqual(
            OnboardingPolicy.next(after: .scanSummary(mode: .full), choice: .continue),
            .statusItemPlacement(mode: .full)
        )
        XCTAssertEqual(
            OnboardingPolicy.next(after: .statusItemPlacement(mode: .launcher), choice: .continue),
            .shortcutConfirmation(mode: .launcher)
        )
    }

    func testBackNavigationPreservesChosenMode() {
        XCTAssertEqual(
            OnboardingPolicy.previous(before: .shortcutConfirmation(mode: .launcher)),
            .statusItemPlacement(mode: .launcher)
        )
        XCTAssertEqual(
            OnboardingPolicy.previous(before: .statusItemPlacement(mode: .full)),
            .scanSummary(mode: .full)
        )
        XCTAssertEqual(OnboardingPolicy.previous(before: .scanSummary(mode: .full)), .permission)
        XCTAssertEqual(OnboardingPolicy.previous(before: .permission), .capabilityBoundary)
        XCTAssertNil(OnboardingPolicy.previous(before: .welcome))
    }

    func testAuthorizationUpgradePreservesPositionInFlow() {
        XCTAssertEqual(
            OnboardingPolicy.authorizedVersion(of: .scanSummary(mode: .launcher)),
            .scanSummary(mode: .full)
        )
        XCTAssertEqual(
            OnboardingPolicy.authorizedVersion(of: .shortcutConfirmation(mode: .launcher)),
            .shortcutConfirmation(mode: .full)
        )
    }

    func testOnlyShortcutConfirmationCanFinish() {
        XCTAssertFalse(OnboardingPolicy.canFinish(.scanSummary(mode: .full)))
        XCTAssertTrue(OnboardingPolicy.canFinish(.shortcutConfirmation(mode: .full)))
        XCTAssertTrue(OnboardingPolicy.canFinish(.shortcutConfirmation(mode: .launcher)))
    }

    func testRepairRequiresConfirmationAndTargetsOnlyMenuHubAccessibilityEntry() {
        XCTAssertNil(AccessibilityRepairPolicy.resetArguments(userConfirmed: false))
        XCTAssertEqual(
            AccessibilityRepairPolicy.resetArguments(userConfirmed: true),
            ["reset", "Accessibility", "com.local.MenuHub"]
        )
    }

    func testCapabilitySummarySeparatesPressLaunchAndUnavailableItems() {
        let summary = OnboardingCapabilitySummary(capabilities: [
            .full, .actionable, .launchOnly, .unavailable, .launchOnly,
        ])

        XCTAssertEqual(summary.pressableCount, 2)
        XCTAssertEqual(summary.launchOnlyCount, 2)
        XCTAssertEqual(summary.unavailableCount, 1)
        XCTAssertEqual(summary.totalCount, 5)
    }
}
