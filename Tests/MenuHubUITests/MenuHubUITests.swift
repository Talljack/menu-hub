import Carbon
import XCTest

@MainActor
final class MenuHubUITests: XCTestCase {
    private var app: XCUIApplication!

    func testAuthorizedMixedPanelSupportsSearchKeyboardAndStableIdentifiers() {
        launch(permission: "authorized", catalog: "mixed", language: "en", reset: true)

        let search = element(identifier: "hub.search")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["hub.items.scroll"].exists)
        XCTAssertTrue(app.buttons["panel.rescan"].exists)
        XCTAssertTrue(element(identifier: FixtureItemID.lark).exists, app.debugDescription)

        typeText("lark", into: search)
        XCTAssertTrue(
            element(identifier: FixtureItemID.weChat).waitForNonExistence(timeout: 2),
            app.debugDescription
        )
        XCTAssertTrue(element(identifier: FixtureItemID.lark).exists, app.debugDescription)

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertNotEqual(app.state, .notRunning)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(search.waitForExistence(timeout: 2))
    }

    func testOnboardingCanSkipPermissionWithoutOpeningSystemSettings() {
        launch(permission: "denied", catalog: "mixed", language: "en", onboarding: true, reset: true)
        XCTAssertTrue(element(identifier: "onboarding.root").waitForExistence(timeout: 5))
        app.buttons["onboarding.primary"].click()
        app.buttons["onboarding.primary"].click()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 2))
        app.buttons["onboarding.skip"].click()
        XCTAssertTrue(app.staticTexts["Scan Results"].waitForExistence(timeout: 2))
        app.buttons["onboarding.primary"].click()
        XCTAssertTrue(
            app.staticTexts["Place the Menu Bar Entry"].waitForExistence(timeout: 2),
            app.debugDescription
        )
    }

    func testDeniedLauncherModeAndEmptyAndErrorFixturesRenderWithoutTCC() {
        launch(permission: "denied", catalog: "launcher-only", language: "en", reset: true)
        XCTAssertTrue(app.staticTexts["Accessibility Permission Required"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: "hub.item.launcher").exists)
        app.terminate()

        launch(permission: "authorized", catalog: "empty", language: "en", reset: true)
        XCTAssertTrue(app.buttons["panel.rescan"].waitForExistence(timeout: 5))
        app.terminate()

        launch(permission: "authorized", catalog: "error", language: "en", reset: true)
        XCTAssertTrue(app.staticTexts["The scan did not complete. Try again later."].waitForExistence(timeout: 5))
    }

    func testChineseAndDarkAppearance() {
        launch(permission: "authorized", catalog: "mixed", language: "zh-Hans", appearance: "dark", reset: true)
        XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: FixtureItemID.lark).exists)
        XCTAssertTrue(app.staticTexts["全部项目"].exists)
    }

    func testEnglishAndLightAppearance() {
        launch(permission: "authorized", catalog: "mixed", language: "en", appearance: "light", reset: true)
        XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["All Items"].exists)
        XCTAssertTrue(element(identifier: FixtureItemID.lark).exists)
    }

    func testLongEuropeanLocalizationsRenderThePanel() {
        let expectations = [
            (language: "de", allItems: "Alle Elemente"),
            (language: "fr", allItems: "Tous les éléments"),
            (language: "pt-BR", allItems: "Todos os itens"),
            (language: "ru", allItems: "Все элементы"),
        ]

        for expectation in expectations {
            launch(
                permission: "authorized",
                catalog: "mixed",
                language: expectation.language,
                reset: true
            )
            XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[expectation.allItems].exists)
            XCTAssertTrue(element(identifier: FixtureItemID.lark).exists)
            app.terminate()
        }
    }

    func testFixtureCatalogPersistsAcrossRelaunch() {
        let suite = "persistence-\(UUID().uuidString)"
        launch(permission: "authorized", catalog: "mixed", language: "en", suite: suite, reset: true)
        XCTAssertTrue(element(identifier: FixtureItemID.lark).waitForExistence(timeout: 5))
        app.terminate()

        launch(permission: "denied", catalog: "empty", language: "en", suite: suite)
        XCTAssertTrue(element(identifier: FixtureItemID.lark).waitForExistence(timeout: 5))
    }

    func testReleaseBindingCrashRegressionSmokeUsesRealLaunchAndPanel() {
        launch(permission: "authorized", catalog: "mixed", language: "en", reset: true)
        XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertTrue(element(identifier: FixtureItemID.lark).exists)
    }

    func testIconGridKeyboardSelectionOpensSelectedItemActions() {
        launch(permission: "authorized", catalog: "mixed", language: "en", layout: "grid", reset: true)
        XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey("k", modifierFlags: .command)

        XCTAssertTrue(element(identifier: "hub.item.actions.panel").waitForExistence(timeout: 3))
    }

    func testUnreadFixtureKeepsPanelInteractionAvailable() {
        launch(permission: "authorized", catalog: "mixed", language: "en", reset: true)

        XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: FixtureItemID.lark).label.contains("Lark — 6"))
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element(identifier: "hub.item.actions.panel").waitForExistence(timeout: 3))
    }

    func testGlassActionPanelSupportsRenameAndLayeredEscapeInIconGrid() {
        launch(permission: "authorized", catalog: "mixed", language: "en", layout: "grid", reset: true)
        XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey("k", modifierFlags: .command)

        XCTAssertTrue(element(identifier: "hub.item.actions.panel").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["hub.item.actions.primary"].exists)
        XCTAssertTrue(app.buttons["hub.item.actions.rename"].exists)
        XCTAssertTrue(app.buttons["hub.item.actions.more"].exists)

        app.buttons["hub.item.actions.rename"].click()
        XCTAssertTrue(element(identifier: "hub.item.actions.aliasField").waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["hub.item.actions.primary"].waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element(identifier: "hub.item.actions.panel").waitForNonExistence(timeout: 2))
    }

    func testFailedGridActionExposesRetryAndOpenApp() {
        launch(
            permission: "authorized", catalog: "mixed", language: "en", layout: "grid",
            actionFailure: "targetUnresponsive", reset: true
        )
        let item = element(identifier: FixtureItemID.lark)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        XCTAssertTrue(app.staticTexts["Action Failed"].waitForExistence(timeout: 3))

        let retry = app.buttons["hub.item.actions.primary"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        XCTAssertTrue(retry.label.hasPrefix("Retry"))
        XCTAssertTrue(app.buttons["hub.item.actions.openHost"].exists)
    }

    private func launch(
        permission: String,
        catalog: String,
        language: String,
        appearance: String = "system",
        layout: String = "compact",
        actionFailure: String? = nil,
        onboarding: Bool = false,
        suite: String = UUID().uuidString,
        reset: Bool = false
    ) {
        app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "1",
            "-permissionFixture", permission,
            "-catalogFixture", catalog,
            "-uiTestLanguage", language,
            "-uiTestAppearance", appearance,
            "-uiTestLayout", layout,
            "-uiTestSuite", suite,
            "-showOnboarding", onboarding ? "1" : "0",
            "-resetFixture", reset ? "1" : "0"
        ]
        if let actionFailure {
            app.launchArguments += ["-uiTestActionFailure", actionFailure]
        }
        app.launch()
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// XCUIElement.typeText is routed through the user's active input method on macOS.
    /// Temporarily selecting the system's ASCII-capable input source makes the test
    /// deterministic, then restores the user's original source immediately.
    private func typeText(_ text: String, into element: XCUIElement) {
        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let ascii = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
        TISSelectInputSource(ascii)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        element.click()
        element.typeText(text)
        TISSelectInputSource(original)
    }
}

private enum FixtureItemID {
    static let lark = "hub.item.com.larksuite.mac|ax:lark"
    static let weChat = "hub.item.com.tencent.xinwechat|ax:wechat"
}
