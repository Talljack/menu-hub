import Foundation
import MenuHubCore

enum LocalizationController {
    private static let defaultsKey = "localization.languagePreference"

    static func apply(_ preference: LanguagePreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: defaultsKey)
    }

    static var languagePreference: LanguagePreference {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let preference = LanguagePreference(rawValue: rawValue) else { return .system }
        return preference
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let bundle = localizedBundle(for: languagePreference)
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale(for: languagePreference), arguments: arguments)
    }

    private static func localizedBundle(for preference: LanguagePreference) -> Bundle {
        let resourceBundle: Bundle
        #if SWIFT_PACKAGE
        resourceBundle = .module
        #else
        resourceBundle = .main
        #endif

        let language = preference == .system
            ? resourceBundle.preferredLocalizations.first ?? LanguagePreference.english.rawValue
            : preference.rawValue
        guard let path = resourceBundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return resourceBundle }
        return bundle
    }

    private static func locale(for preference: LanguagePreference) -> Locale {
        preference == .system ? .current : Locale(identifier: preference.rawValue)
    }
}

@inline(__always)
func L(_ key: String, _ arguments: CVarArg...) -> String {
    LocalizationController.string(key, arguments)
}

private extension LocalizationController {
    static func string(_ key: String, _ arguments: [CVarArg]) -> String {
        let bundle = localizedBundle(for: languagePreference)
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale(for: languagePreference), arguments: arguments)
    }
}
