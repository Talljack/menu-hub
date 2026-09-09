import XCTest
@testable import MenuHub
@testable import MenuHubCore

final class SettingsLanguageOptionsTests: XCTestCase {
    func testSettingsExposeEverySelectableLanguageInStableOrder() {
        XCTAssertEqual(SettingsLanguageOptions.all, LanguagePreference.selectable)
    }
}
