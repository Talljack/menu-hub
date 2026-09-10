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
        XCTAssertTrue(element(identifier: "hub.item.lark").exists)

        search.click()
        search.typeText("lark")
        XCTAssertTrue(element(identifier: "hub.item.wechat").waitForNonExistence(timeout: 2))
        XCTAssertTrue(element(identifier: "hub.item.lark").exists)

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertNotEqual(app.state, .notRunning)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(search.waitForExistence(timeout: 2))
    }

    func testOnboardingCanSkipPermissionWithoutOpeningSystemSettings() {
        launch(permission: "denied", catalog: "mixed", language: "en", onboarding: true, reset: true)
        XCTAssertTrue(app.otherElements["onboarding.root"].waitForExistence(timeout: 5))
        app.buttons["onboarding.primary"].click()
        app.buttons["onboarding.primary"].click()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 2))
        app.buttons["onboarding.skip"].click()
        XCTAssertTrue(app.staticTexts["Place the Menu Bar Entry"].waitForExistence(timeout: 2))
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
        XCTAssertTrue(element(identifier: "hub.item.lark").exists)
        XCTAssertTrue(app.staticTexts["全部项目"].exists)
    }

    func testEnglishAndLightAppearance() {
        launch(permission: "authorized", catalog: "mixed", language: "en", appearance: "light", reset: true)
        XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["All Items"].exists)
        XCTAssertTrue(element(identifier: "hub.item.lark").exists)
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
            XCTAssertTrue(element(identifier: "hub.item.lark").exists)
            app.terminate()
        }
    }

    func testFixtureCatalogPersistsAcrossRelaunch() {
        let suite = "persistence-\(UUID().uuidString)"
        launch(permission: "authorized", catalog: "mixed", language: "en", suite: suite, reset: true)
        XCTAssertTrue(element(identifier: "hub.item.lark").waitForExistence(timeout: 5))
        app.terminate()

        launch(permission: "authorized", catalog: "empty", language: "en", suite: suite)
        XCTAssertTrue(element(identifier: "hub.item.lark").waitForExistence(timeout: 5))
    }

    func testReleaseBindingCrashRegressionSmokeUsesRealLaunchAndPanel() {
        launch(permission: "authorized", catalog: "mixed", language: "en", reset: true)
        XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hub.item.actions.'")).firstMatch.exists)
    }

    func testIconGridKeyboardSelectionOpensSelectedItemActions() {
        launch(permission: "authorized", catalog: "mixed", language: "en", layout: "grid", reset: true)
        XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey("k", modifierFlags: .command)

        XCTAssertTrue(element(identifier: "hub.item.actions.lark").waitForExistence(timeout: 3))
    }

    private func launch(
        permission: String,
        catalog: String,
        language: String,
        appearance: String = "system",
        layout: String = "compact",
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
        app.launch()
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
