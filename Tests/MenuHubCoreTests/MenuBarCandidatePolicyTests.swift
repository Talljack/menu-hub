import XCTest
@testable import MenuHubCore

final class MenuBarCandidatePolicyTests: XCTestCase {
    func testKeepsMenuBarItemsAndMenuExtras() {
        XCTAssertTrue(MenuBarCandidatePolicy.isCandidate(role: "AXMenuBarItem", subrole: nil, actions: []))
        XCTAssertTrue(MenuBarCandidatePolicy.isCandidate(role: "AXButton", subrole: "AXMenuExtra", actions: ["AXPress"]))
    }

    func testRejectsOrdinaryApplicationButtons() {
        XCTAssertFalse(MenuBarCandidatePolicy.isCandidate(role: "AXButton", subrole: nil, actions: ["AXPress"]))
        XCTAssertFalse(MenuBarCandidatePolicy.isCandidate(role: "AXWindow", subrole: nil, actions: []))
    }
}
