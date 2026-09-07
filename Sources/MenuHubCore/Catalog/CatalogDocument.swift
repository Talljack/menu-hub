import Foundation

public enum AppearancePreference: String, Codable, Equatable, Sendable {
    case system
    case light
    case dark
}

public enum LanguagePreference: String, Codable, Equatable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public static let zhHans = Self.simplifiedChinese
    public static let en = Self.english
}

public enum LayoutPreference: String, Codable, Equatable, Sendable {
    case compact
    case grid
}

public enum HotKeyModifier: String, Codable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
}

public struct HotKeyPreference: Codable, Equatable, Sendable {
    public var keyCode: UInt32?
    public var modifiers: Set<HotKeyModifier>

    public init(keyCode: UInt32?, modifiers: Set<HotKeyModifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let `default` = Self(keyCode: 46, modifiers: [.option])
}

public struct Preferences: Codable, Equatable, Sendable {
    public var appearance: AppearancePreference
    public var language: LanguagePreference
    public var hotKey: HotKeyPreference
    public var launchAtLogin: Bool
    public var restoreHiddenState: Bool
    public var closeOnFocusLoss: Bool
    public var closeAfterSuccessfulTrigger: Bool
    public var automaticScanning: Bool
    public var showGroupHeadings: Bool
    public var showCapabilities: Bool
    public var layout: LayoutPreference

    public init(
        appearance: AppearancePreference = .system,
        language: LanguagePreference = .system,
        hotKey: HotKeyPreference = .default,
        launchAtLogin: Bool = false,
        restoreHiddenState: Bool = false,
        closeOnFocusLoss: Bool = true,
        closeAfterSuccessfulTrigger: Bool = true,
        automaticScanning: Bool = true,
        showGroupHeadings: Bool = true,
        showCapabilities: Bool = true,
        layout: LayoutPreference = .compact
    ) {
        self.appearance = appearance
        self.language = language
        self.hotKey = hotKey
        self.launchAtLogin = launchAtLogin
        self.restoreHiddenState = restoreHiddenState
        self.closeOnFocusLoss = closeOnFocusLoss
        self.closeAfterSuccessfulTrigger = closeAfterSuccessfulTrigger
        self.automaticScanning = automaticScanning
        self.showGroupHeadings = showGroupHeadings
        self.showCapabilities = showCapabilities
        self.layout = layout
    }

    public static let `default` = Self()
}

public typealias CatalogPreferences = Preferences

public struct CatalogDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var items: [MenuBarItemRecord]
    public var groups: [GroupRecord]
    public var preferences: Preferences

    public init(
        schemaVersion: Int = 1,
        items: [MenuBarItemRecord],
        groups: [GroupRecord],
        preferences: Preferences
    ) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.groups = groups
        self.preferences = preferences
    }

    public static let empty = Self(items: [], groups: [], preferences: .default)
}
