import XCTest
@testable import MenuHubCore

final class SpacerStateTests: XCTestCase {
    func testStartupAlwaysRevealsItemsEvenWhenPreviousPreferenceWasHidden() {
        let state = SpacerState.startup(
            safeWidth: 1,
            requestedHiddenWidth: 280,
            shouldRestoreHiddenPreference: true,
            maximumSafeWidth: 320
        )

        XCTAssertEqual(state.visibility, .revealed)
        XCTAssertEqual(state.currentWidth, 1)
        XCTAssertTrue(state.shouldRestoreHiddenPreference)
    }

    func testHideClampsWidthToCurrentSafeMaximum() {
        var state = SpacerState.startup(
            safeWidth: 1,
            requestedHiddenWidth: 500,
            shouldRestoreHiddenPreference: false,
            maximumSafeWidth: 240
        )

        state.hideItems()

        XCTAssertEqual(state.visibility, .hidden)
        XCTAssertEqual(state.currentWidth, 240)
    }

    func testDisplayChangeImmediatelyRevealsItems() {
        var state = SpacerState.startup(
            safeWidth: 1,
            requestedHiddenWidth: 200,
            shouldRestoreHiddenPreference: true,
            maximumSafeWidth: 300
        )
        state.hideItems()

        state.revealForSafety()

        XCTAssertEqual(state.visibility, .revealed)
        XCTAssertEqual(state.currentWidth, 1)
    }

    func testSetupMarkerGetsADraggableVisibleWidth() {
        let state = SpacerState.startup(
            safeWidth: 1,
            requestedHiddenWidth: 240,
            shouldRestoreHiddenPreference: false,
            maximumSafeWidth: 320
        )

        XCTAssertEqual(state.presentationWidth(setupMarkerVisible: false, minimumMarkerWidth: 28), 1)
        XCTAssertEqual(state.presentationWidth(setupMarkerVisible: true, minimumMarkerWidth: 28), 28)
    }

    func testUncertainStartupAlwaysRevealsSpacer() {
        let state = SpacerState.startupAfterUncleanExit(
            savedHidden: true,
            safeWidth: 1,
            requestedHiddenWidth: 280,
            maximumSafeWidth: 320
        )

        XCTAssertEqual(state.visibility, .revealed)
        XCTAssertEqual(state.currentWidth, 1)
        XCTAssertFalse(state.shouldRestoreHiddenPreference)
    }
}
