import XCTest
@testable import MenuHubCore

final class UsageGuidePolicyTests: XCTestCase {
    func testFirstLaunchPresentsGuide() {
        XCTAssertTrue(UsageGuidePolicy.shouldPresentOnLaunch(hasShownGuide: false))
    }

    func testRoutineBackgroundLaunchDoesNotRepeatGuide() {
        XCTAssertFalse(UsageGuidePolicy.shouldPresentOnLaunch(hasShownGuide: true))
    }

    func testExplicitReopenDoesNotReplaceTheMainPanelWithTheGuide() {
        XCTAssertFalse(UsageGuidePolicy.shouldPresentOnReopen)
    }
}
