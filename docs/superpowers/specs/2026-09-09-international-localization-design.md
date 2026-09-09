# Menu Hub International Localization Design

## Goal

Expand Menu Hub from English and Simplified Chinese to ten complete, user-selectable languages without changing existing user preferences or weakening the English fallback.

## Supported Languages

| Language | Resource identifier | Picker label |
| --- | --- | --- |
| English | `en` | English |
| Simplified Chinese | `zh-Hans` | 简体中文 |
| Traditional Chinese | `zh-Hant` | 繁體中文 |
| Japanese | `ja` | 日本語 |
| Korean | `ko` | 한국어 |
| Spanish | `es` | Español |
| French | `fr` | Français |
| German | `de` | Deutsch |
| Brazilian Portuguese | `pt-BR` | Português (Brasil) |
| Russian | `ru` | Русский |

Arabic is outside this release because complete support requires right-to-left layout validation, not only translated strings.

## Language Selection

`LanguagePreference` remains the persisted source of truth. Existing raw values for `system`, `en`, and `zh-Hans` remain unchanged so upgrades preserve current selections. New enum cases use the resource identifiers in the table.

The language picker lists System Default first, followed by the ten supported languages. Language names use their native names so users can find their language even when the current interface language is unfamiliar.

When System Default is selected, `Bundle.preferredLocalizations` chooses the best available localization. Unsupported system languages fall back to English. Regional variants may use their supported base language, for example Spanish regional settings use `es` and Traditional Chinese uses `zh-Hant`.

## Resource Architecture

The existing `.lproj/Localizable.strings` architecture remains in place for macOS 14 compatibility and a small change surface. Eight new resource bundles are added alongside `en.lproj` and `zh-Hans.lproj`.

Every localization contains the complete key set. A missing resource bundle or lookup failure falls back to English rather than displaying a localization key or mixing arbitrary languages.

Formatting placeholders such as `%@`, `%d`, and positional variants must preserve the English argument contract. Translators may reorder text only with positional placeholders that keep the same types and counts.

## Translation Quality

All user-facing strings are translated individually for the macOS context. Terminology must stay consistent across the panel, onboarding, settings, permissions, diagnostics, menu commands, capabilities, and error messages.

Translations favor short native UI language over literal word-for-word phrasing. Product and technical names such as Menu Hub, macOS, Accessibility, Developer ID, `AXPress`, and keyboard symbols remain recognizable where appropriate.

## UI Behavior

Changing language keeps the current persistence behavior. Menus and windows update when reopened, and the app asks users to restart only if an already-open surface retains old text.

The existing panel and settings layouts remain structurally unchanged. German, French, Portuguese, and Russian strings receive explicit truncation checks because they are commonly longer than English. Japanese, Korean, and both Chinese variants receive checks for readable line breaking and native punctuation.

## Testing

Implementation follows test-first development.

Automated tests must verify:

1. The supported language list contains exactly the ten specified identifiers.
2. Existing persisted raw values remain compatible.
3. Every localization file parses as a strings property list.
4. Every localization has exactly the English key set.
5. Formatting placeholders match the English contract for every key.
6. Required user-facing areas exist in every localization.
7. Explicit language selection resolves the intended resource bundle and locale.
8. Unsupported system languages fall back to English.

The Xcode project, Swift package resources, release builds, and signed app bundle must all include the ten `.lproj` directories.

Manual validation covers the language picker, main panel, onboarding, settings, permission repair, diagnostics, and representative error states in all ten languages. Long-string layouts are checked at the default panel and settings window sizes.

## Documentation and Release

Both READMEs are updated to list all ten languages. The next release notes call out the eight newly added localizations.

Version bumping, tagging, signing, notarization, and GitHub Release publication remain separate release actions and require explicit version confirmation.

## Out of Scope

- Arabic and other right-to-left languages
- Machine-translated fallback text at runtime
- Downloading translations or other network activity
- Changing the panel layout or visual design
- Translating app names or third-party menu bar item names
