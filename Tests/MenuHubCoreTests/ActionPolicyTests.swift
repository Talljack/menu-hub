import XCTest
@testable import MenuHubCore

final class ActionPolicyTests: XCTestCase {
    func testDefaultActionsMatchCapabilities() {
        XCTAssertEqual(ActionPolicy.defaultAction(for: .full), .press)
        XCTAssertEqual(ActionPolicy.defaultAction(for: .actionable), .press)
        XCTAssertEqual(ActionPolicy.defaultAction(for: .launchOnly), .openHostApplication)
        XCTAssertEqual(ActionPolicy.defaultAction(for: .unavailable), .unavailable)
    }

    func testUnsupportedItemsNeverExposePressAsASecondaryAction() {
        XCTAssertFalse(ActionPolicy.secondaryActions(for: .launchOnly).contains(.press))
        XCTAssertFalse(ActionPolicy.secondaryActions(for: .unavailable).contains(.press))
    }

    func testPressableItemsCanOfferHostApplicationAsSecondaryAction() {
        XCTAssertEqual(ActionPolicy.secondaryActions(for: .full), [.openHostApplication])
        XCTAssertEqual(ActionPolicy.secondaryActions(for: .actionable), [.openHostApplication])
    }

    func testUnavailableItemsHaveNoSecondaryActions() {
        XCTAssertEqual(ActionPolicy.secondaryActions(for: .unavailable), [])
    }
}
