import Foundation
import Testing
@testable import MenuHubCore

struct LocalizationCompletenessTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func everySupportedLocalizationMatchesEnglish() throws {
        let english = try strings(for: .english)
        #expect(!english.isEmpty)

        for language in LanguagePreference.supported {
            let translation = try strings(for: language)
            #expect(
                Set(translation.keys) == Set(english.keys),
                "Key mismatch for \(language.rawValue)"
            )
            for key in english.keys.sorted() {
                #expect(
                    placeholders(in: translation[key, default: ""]) == placeholders(in: english[key, default: ""]),
                    "Placeholder mismatch for \(language.rawValue):\(key)"
                )
            }
        }
    }

    @Test func requiredUserFacingAreasAreCovered() throws {
        let keys = Set(try strings(at: "Resources/en.lproj/Localizable.strings").keys)
        let requiredPrefixes = [
            "panel.", "statusMenu.", "onboarding.", "management.",
            "settings.", "error.", "permission.", "capability.",
            "diagnostics.", "accessibility."
        ]

        for prefix in requiredPrefixes {
            #expect(keys.contains(where: { $0.hasPrefix(prefix) }), "Missing localization area: \(prefix)")
        }

        let requiredKeys = [
            "management.unreadBadge",
            "management.unreadBadgeAutomatic",
            "management.unreadBadgeInclude",
            "management.unreadBadgeExclude",
            "management.unreadBadgeHelp",
            "statusItem.unreadFormat",
            "statusItem.unreadOverflow",
            "panel.retry",
            "actionPanel.menuBarItem",
            "actionPanel.ready",
            "actionPanel.quickActions",
            "actionPanel.customize",
            "actionPanel.rename",
            "actionPanel.groups",
            "actionPanel.moreActions",
            "actionPanel.displayName",
            "actionPanel.optional",
            "actionPanel.keyboardDefault",
            "actionPanel.keyboardRename",
            "actionPanel.keyboardGroups",
        ]
        for key in requiredKeys {
            #expect(keys.contains(key), "Missing required localization: \(key)")
        }
    }

    private func strings(at relativePath: String) throws -> [String: String] {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let strings = object as? [String: String] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return strings
    }

    private func strings(for language: LanguagePreference) throws -> [String: String] {
        try strings(at: "Resources/\(language.rawValue).lproj/Localizable.strings")
    }

    private func placeholders(in value: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?(?:@|d)"#)
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }.sorted()
    }
}
