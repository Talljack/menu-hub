import Foundation
import Testing

struct LocalizationCompletenessTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func englishAndSimplifiedChineseContainTheSameKeys() throws {
        let english = try strings(at: "Resources/en.lproj/Localizable.strings")
        let chinese = try strings(at: "Resources/zh-Hans.lproj/Localizable.strings")

        #expect(!english.isEmpty)
        #expect(Set(english.keys) == Set(chinese.keys))
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
}
