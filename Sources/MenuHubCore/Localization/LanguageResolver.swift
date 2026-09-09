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
