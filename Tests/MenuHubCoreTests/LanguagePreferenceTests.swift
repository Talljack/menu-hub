import Testing
@testable import MenuHubCore

struct LanguagePreferenceTests {
    @Test func supportedLanguagesHaveStableOrderIdentifiersAndNativeNames() {
        let expected: [(LanguagePreference, String, String)] = [
            (.english, "en", "English"),
            (.simplifiedChinese, "zh-Hans", "简体中文"),
            (.traditionalChinese, "zh-Hant", "繁體中文"),
            (.japanese, "ja", "日本語"),
            (.korean, "ko", "한국어"),
            (.spanish, "es", "Español"),
            (.french, "fr", "Français"),
            (.german, "de", "Deutsch"),
            (.brazilianPortuguese, "pt-BR", "Português (Brasil)"),
            (.russian, "ru", "Русский"),
        ]

        #expect(LanguagePreference.supported == expected.map(\.0))
        #expect(LanguagePreference.supported.map(\.rawValue) == expected.map(\.1))
        #expect(LanguagePreference.supported.map(\.nativeName) == expected.map(\.2))
        #expect(LanguagePreference.selectable == [.system] + expected.map(\.0))
    }

    @Test func existingPersistedValuesRemainCompatible() {
        #expect(LanguagePreference(rawValue: "system") == .system)
        #expect(LanguagePreference(rawValue: "en") == .english)
        #expect(LanguagePreference(rawValue: "zh-Hans") == .simplifiedChinese)
    }
}
