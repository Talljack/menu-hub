# International Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship ten complete, user-selectable Menu Hub localizations with deterministic system-language fallback and automated resource validation.

**Architecture:** Keep the existing `.lproj/Localizable.strings` resource model. Move supported-language metadata and resolution into `MenuHubCore`, let the app localization controller consume that tested API, and generate the Settings picker from one ordered language list. Extend completeness tests to parse every file and compare keys and format placeholders against English.

**Tech Stack:** Swift 6, Foundation localization bundles, SwiftUI, Swift Testing, XCTest, XcodeGen, Swift Package Manager.

---

## File Structure

- Modify `Sources/MenuHubCore/Catalog/CatalogDocument.swift`: add persisted language cases and stable language metadata.
- Create `Sources/MenuHubCore/Localization/LanguageResolver.swift`: resolve explicit and system language choices to supported resource identifiers.
- Modify `Sources/MenuHub/LocalizationController.swift`: load bundles and formatting locales through the tested resolver.
- Modify `Sources/MenuHub/SettingsView.swift`: generate the language picker from the supported language list.
- Modify `Tests/MenuHubCoreTests/LocalizationCompletenessTests.swift`: validate all ten files, key parity, and placeholders.
- Create `Tests/MenuHubCoreTests/LanguagePreferenceTests.swift`: verify persisted identifiers, ordering, labels, and system-language resolution.
- Modify `Package.swift` and `project.yml`: register all localization resources.
- Create `Resources/{zh-Hant,ja,ko,es,fr,de,pt-BR,ru}.lproj/Localizable.strings`: complete translations.
- Modify `README.md` and `README.zh-CN.md`: document all ten supported languages.

### Task 1: Stable language metadata

**Files:**
- Create: `Tests/MenuHubCoreTests/LanguagePreferenceTests.swift`
- Modify: `Sources/MenuHubCore/Catalog/CatalogDocument.swift`

- [ ] **Step 1: Write failing metadata tests**

```swift
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
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter LanguagePreferenceTests`

Expected: compilation fails because the eight new cases and metadata properties do not exist.

- [ ] **Step 3: Add the ten persisted cases and metadata**

```swift
public enum LanguagePreference: String, Codable, Equatable, Hashable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case brazilianPortuguese = "pt-BR"
    case russian = "ru"

    public static let supported: [Self] = [
        .english, .simplifiedChinese, .traditionalChinese, .japanese, .korean,
        .spanish, .french, .german, .brazilianPortuguese, .russian,
    ]
    public static let selectable: [Self] = [.system] + supported

    public var nativeName: String {
        switch self {
        case .system: "System Default"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .brazilianPortuguese: "Português (Brasil)"
        case .russian: "Русский"
        }
    }
}
```

Keep the existing `zhHans` and `en` compatibility aliases.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter LanguagePreferenceTests`

Expected: all metadata tests pass.

- [ ] **Step 5: Commit**

```sh
git add Sources/MenuHubCore/Catalog/CatalogDocument.swift Tests/MenuHubCoreTests/LanguagePreferenceTests.swift
git commit -m "feat: define supported Menu Hub languages"
```

### Task 2: Deterministic resource resolution

**Files:**
- Modify: `Tests/MenuHubCoreTests/LanguagePreferenceTests.swift`
- Create: `Sources/MenuHubCore/Localization/LanguageResolver.swift`
- Modify: `Sources/MenuHub/LocalizationController.swift`

- [ ] **Step 1: Write failing resolver tests**

```swift
@Test func explicitPreferencesResolveDirectly() {
    for preference in LanguagePreference.supported {
        #expect(LanguageResolver.resourceIdentifier(for: preference, preferredLanguages: ["ar"]) == preference.rawValue)
    }
}

@Test func systemPreferenceMatchesRegionsAndFallsBackToEnglish() {
    #expect(LanguageResolver.resourceIdentifier(for: .system, preferredLanguages: ["zh-TW"]) == "zh-Hant")
    #expect(LanguageResolver.resourceIdentifier(for: .system, preferredLanguages: ["es-MX"]) == "es")
    #expect(LanguageResolver.resourceIdentifier(for: .system, preferredLanguages: ["fr-CA"]) == "fr")
    #expect(LanguageResolver.resourceIdentifier(for: .system, preferredLanguages: ["pt-PT"]) == "pt-BR")
    #expect(LanguageResolver.resourceIdentifier(for: .system, preferredLanguages: ["ar"]) == "en")
    #expect(LanguageResolver.resourceIdentifier(for: .system, preferredLanguages: []) == "en")
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter LanguagePreferenceTests`

Expected: compilation fails because `LanguageResolver` does not exist.

- [ ] **Step 3: Implement the resolver**

```swift
import Foundation

public enum LanguageResolver {
    public static func resourceIdentifier(
        for preference: LanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        guard preference == .system else { return preference.rawValue }
        return Bundle.preferredLocalizations(
            from: LanguagePreference.supported.map(\.rawValue),
            forPreferences: preferredLanguages
        ).first ?? LanguagePreference.english.rawValue
    }
}
```

Update `LocalizationController.localizedBundle` to call the resolver. If the selected bundle is missing, explicitly load `en.lproj`; only return the resource bundle itself when English is also unavailable. Use `.current` for System Default formatting and `Locale(identifier: preference.rawValue)` for explicit preferences.

- [ ] **Step 4: Run focused and controller-adjacent tests**

Run: `swift test --filter LanguagePreferenceTests`

Expected: resolver tests pass, including regional matching and English fallback.

- [ ] **Step 5: Commit**

```sh
git add Sources/MenuHubCore/Localization/LanguageResolver.swift Sources/MenuHub/LocalizationController.swift Tests/MenuHubCoreTests/LanguagePreferenceTests.swift
git commit -m "feat: resolve supported system languages"
```

### Task 3: Data-driven language picker

**Files:**
- Create: `Sources/MenuHub/SettingsLanguageOptions.swift`
- Create: `Tests/MenuHubTests/SettingsLanguageOptionsTests.swift`
- Modify: `Sources/MenuHub/SettingsView.swift`

- [ ] **Step 1: Add a failing picker-option contract test**

```swift
@Test func settingsExposeEverySelectableLanguageInStableOrder() {
    #expect(SettingsLanguageOptions.all == LanguagePreference.selectable)
}
```

- [ ] **Step 2: Verify RED before changing the picker**

Run: `swift test --filter SettingsLanguageOptionsTests`

Expected: compilation fails because `SettingsLanguageOptions` does not exist.

- [ ] **Step 3: Add the picker option adapter and replace hard-coded rows**

`SettingsLanguageOptions.all` returns `LanguagePreference.selectable`. Render System Default through the localized string key and every explicit language through its native name:

```swift
Picker(L("settings.language"), selection: languageBinding) {
    ForEach(LanguagePreference.selectable, id: \.self) { preference in
        Text(preference == .system ? L("settings.languageSystem") : preference.nativeName)
            .tag(preference)
    }
}
```

- [ ] **Step 4: Run settings and language tests**

Run: `swift test --filter 'LanguagePreferenceTests|ManagementSettingsTests'`

Expected: all selected tests pass.

- [ ] **Step 5: Commit**

```sh
git add Sources/MenuHub/SettingsLanguageOptions.swift Sources/MenuHub/SettingsView.swift Tests/MenuHubTests/SettingsLanguageOptionsTests.swift
git commit -m "feat: show all supported languages in settings"
```

### Task 4: Resource completeness and placeholder contracts

**Files:**
- Modify: `Tests/MenuHubCoreTests/LocalizationCompletenessTests.swift`

- [ ] **Step 1: Replace the two-language test with a failing ten-language test**

The test loads `Resources/<identifier>.lproj/Localizable.strings` for every value in `LanguagePreference.supported`, verifies parsing, and compares each key set to English. Add a placeholder extractor using `NSRegularExpression(pattern: #"%(?:(\d+)\$)?(?:@|d)"#)` and compare sorted placeholder tokens for every translated value.

```swift
@Test func everySupportedLocalizationMatchesEnglish() throws {
    let english = try strings(for: .english)
    #expect(!english.isEmpty)

    for language in LanguagePreference.supported {
        let translation = try strings(for: language)
        #expect(Set(translation.keys) == Set(english.keys), "Key mismatch for \(language.rawValue)")
        for key in english.keys.sorted() {
            #expect(
                placeholders(in: translation[key, default: ""]) == placeholders(in: english[key, default: ""]),
                "Placeholder mismatch for \(language.rawValue):\(key)"
            )
        }
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run: `swift test --filter LocalizationCompletenessTests`

Expected: the test throws file-not-found errors for the eight new resource identifiers.

- [ ] **Step 3: Keep the failing test in place for translation tasks**

Do not weaken the expected language list or skip missing files. Commit the red test only together with the first resource batch in Task 5, after it becomes green for that complete ten-language expectation.

### Task 5: Add eight complete human-context translations

**Files:**
- Create: `Resources/zh-Hant.lproj/Localizable.strings`
- Create: `Resources/ja.lproj/Localizable.strings`
- Create: `Resources/ko.lproj/Localizable.strings`
- Create: `Resources/es.lproj/Localizable.strings`
- Create: `Resources/fr.lproj/Localizable.strings`
- Create: `Resources/de.lproj/Localizable.strings`
- Create: `Resources/pt-BR.lproj/Localizable.strings`
- Create: `Resources/ru.lproj/Localizable.strings`
- Modify: `Package.swift`
- Modify: `project.yml`
- Test: `Tests/MenuHubCoreTests/LocalizationCompletenessTests.swift`

- [ ] **Step 1: Translate every English key into Traditional Chinese, Japanese, and Korean**

Create all three files with the exact English key order. Translate panel, onboarding, permissions, management, settings, diagnostics, accessibility, capabilities, and errors with native macOS terminology. Preserve `Menu Hub`, keyboard symbols, bundle identifiers, and all four format contracts exactly.

- [ ] **Step 2: Translate every English key into Spanish, French, and German**

Use concise native UI terms, formal neutral address, and platform terminology familiar to macOS users. Keep button labels short enough for the existing settings width and preserve all format contracts.

- [ ] **Step 3: Translate every English key into Brazilian Portuguese and Russian**

Use Brazilian rather than European Portuguese terminology. Use neutral standard Russian UI language. Keep product names, keyboard symbols, and format contracts unchanged.

- [ ] **Step 4: Register every resource directory**

Add these exact resource paths to both `Package.swift` and the `MenuHub` resource sources in `project.yml`:

```text
Resources/zh-Hant.lproj
Resources/ja.lproj
Resources/ko.lproj
Resources/es.lproj
Resources/fr.lproj
Resources/de.lproj
Resources/pt-BR.lproj
Resources/ru.lproj
```

- [ ] **Step 5: Run completeness tests and verify GREEN**

Run: `swift test --filter LocalizationCompletenessTests`

Expected: every file parses; all ten key sets and all format placeholders match English.

- [ ] **Step 6: Commit**

```sh
git add Package.swift project.yml Resources Tests/MenuHubCoreTests/LocalizationCompletenessTests.swift
git commit -m "feat: add eight international localizations"
```

### Task 6: Documentation and bundle validation

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Test: generated `MenuHub.xcodeproj` and built app bundle

- [ ] **Step 1: Update the documented language list**

Replace the two-language sentence in each README with the exact ten-language list and retain the System Default behavior and English fallback explanation.

- [ ] **Step 2: Regenerate the Xcode project**

Run: `xcodegen generate`

Expected: generation succeeds and `MenuHub.xcodeproj/project.pbxproj` contains all ten `.lproj` identifiers.

- [ ] **Step 3: Run all Swift tests**

Run: `swift test`

Expected: all XCTest and Swift Testing tests pass with zero failures.

- [ ] **Step 4: Build and test the Xcode project**

Run:

```sh
xcodebuild test \
  -project MenuHub.xcodeproj \
  -scheme MenuHub \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData/Localization \
  -skip-testing:MenuHubUITests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Verify all resources in the built app**

Run:

```sh
for locale in en zh-Hans zh-Hant ja ko es fr de pt-BR ru; do
  test -f "DerivedData/Localization/Build/Products/Debug/MenuHub.app/Contents/Resources/$locale.lproj/Localizable.strings"
done
```

Expected: every file exists.

- [ ] **Step 6: Commit**

```sh
git add README.md README.zh-CN.md MenuHub.xcodeproj/project.pbxproj
git commit -m "docs: document ten supported languages"
```

### Task 7: Release-quality verification and integration

**Files:**
- Verify all files changed by Tasks 1 through 6.

- [ ] **Step 1: Run dual-architecture release builds**

Run: `BUILD_ONLY=1 ./scripts/build-release.sh`

Expected: native `arm64` and `x86_64` Menu Hub apps build successfully.

- [ ] **Step 2: Verify release app localization bundles**

For both `DerivedData/Release-arm64` and `DerivedData/Release-x86_64`, assert that all ten `.lproj/Localizable.strings` files exist under the built app's `Contents/Resources` directory.

- [ ] **Step 3: Inspect representative long strings**

Launch a debug build once for `de`, `fr`, `pt-BR`, and `ru`. Check the panel, settings sidebar, General page, Permissions & Privacy, onboarding permission page, and one error message at default window sizes. No text may overlap controls or become unreadable; standard truncation is acceptable only for third-party item names.

- [ ] **Step 4: Run final repository checks**

Run:

```sh
git diff --check
swift test
git status --short
```

Expected: no whitespace errors, all tests pass, and only intentional changes are present.

- [ ] **Step 5: Open a pull request and wait for required CI**

Push `codex/international-localization`, create a PR to `main`, and wait for the required `build-release` check. Merge only after the check succeeds.

- [ ] **Step 6: Keep release publication separate**

Do not bump `VERSION`, create a tag, or publish a GitHub Release until the user explicitly confirms the next version number.
