#if DEBUG
import AppKit
import Foundation
import MenuHubCore

/// Deterministic, local-only data used by XCUITest. This path never asks AX for trust,
/// opens System Settings, launches another app, or reads the production catalog.
struct UITestRuntime {
    let permissionState: PermissionState
    let catalogName: String
    let language: LanguagePreference
    let appearance: AppearancePreference
    let showsOnboarding: Bool
    let resetFixture: Bool
    let directory: URL

    static var current: Self? {
        let arguments = ProcessInfo.processInfo.arguments
        guard value(after: "-uiTesting", in: arguments) == "1" else { return nil }
        let permission = value(after: "-permissionFixture", in: arguments) == "authorized"
            ? PermissionState.authorized : .denied
        let catalog = value(after: "-catalogFixture", in: arguments) ?? "mixed"
        let language = LanguagePreference(rawValue: value(after: "-uiTestLanguage", in: arguments) ?? "en") ?? .english
        let appearance = AppearancePreference(rawValue: value(after: "-uiTestAppearance", in: arguments) ?? "system") ?? .system
        let rawSuite = value(after: "-uiTestSuite", in: arguments) ?? UUID().uuidString
        let suite = rawSuite.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.local.MenuHubUITests", isDirectory: true)
            .appendingPathComponent(suite.isEmpty ? UUID().uuidString : suite, isDirectory: true)
        return Self(
            permissionState: permission,
            catalogName: catalog,
            language: language,
            appearance: appearance,
            showsOnboarding: value(after: "-showOnboarding", in: arguments) == "1",
            resetFixture: value(after: "-resetFixture", in: arguments) == "1",
            directory: directory
        )
    }

    var trusted: Bool { permissionState == .authorized }

    @MainActor
    func makeModel() -> HubPanelModel {
        let fixture = Self.fixture(named: catalogName, language: language)
        let store = UITestCatalogStore(directory: directory, seed: fixture.document, reset: resetFixture)
        let controller = CatalogController(
            store: store,
            accessibility: UITestAccessibility(result: fixture.scanResult),
            launcher: UITestLauncher(),
            canLaunchHost: { _ in true },
            hostMetadataResolver: UITestHostMetadataResolver()
        )
        let model = HubPanelModel(
            controller: controller,
            initialPermissionState: permissionState,
            permissionEffectHandler: UITestPermissionEffects(),
            accessibilityTrustProvider: { trusted }
        )
        Task { await controller.load() }
        return model
    }

    private static func value(after key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func fixture(named name: String, language: LanguagePreference) -> (document: CatalogDocument, scanResult: AccessibilityScanResult) {
        if name == "empty" { return (.empty, .init(snapshots: [], issues: [])) }
        if name == "error" {
            return (.empty, .init(snapshots: [], issues: [.targetUnresponsive(process: nil)]))
        }

        let host = language == .simplifiedChinese ? "飞书" : "Lark"
        if name == "launcher-only" {
            let item = record(id: "launcher", host: "Example Launcher", title: "Example Launcher", bundle: "com.example.launcher", capability: .launchOnly, order: 0)
            return (CatalogDocument(items: [item], groups: [], preferences: preferences(language)), .init(snapshots: [], issues: []))
        }

        let lark = record(id: "lark", host: host, title: "6", bundle: "com.larksuite.mac", capability: .full, favorite: true, order: 0)
        let wechat = record(id: "wechat", host: "WeChat", title: "WeChat", bundle: "com.tencent.xinWeChat", capability: .launchOnly, order: 1)
        let unavailable = record(id: "unavailable", host: "Example Utility", title: "Status", bundle: "com.example.utility", capability: .unavailable, order: 2)
        let snapshots = [snapshot(for: lark), snapshot(for: wechat)]
        return (
            CatalogDocument(items: [lark, wechat, unavailable], groups: [], preferences: preferences(language)),
            .init(snapshots: snapshots, issues: [])
        )
    }

    private static func preferences(_ language: LanguagePreference) -> Preferences {
        var value = Preferences.default
        value.language = language
        value.automaticScanning = true
        value.closeAfterSuccessfulTrigger = false
        return value
    }

    private static func record(
        id: String, host: String, title: String, bundle: String, capability: ItemCapability,
        favorite: Bool = false, order: Int
    ) -> MenuBarItemRecord {
        MenuBarItemRecord(
            id: id,
            identity: .init(bundleIdentifier: bundle, originalName: title, axIdentifier: id, path: [order]),
            hostName: host,
            hostBundleIdentifier: bundle,
            capability: capability,
            isFavorite: favorite,
            manualOrder: order,
            lastSeenAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private static func snapshot(for record: MenuBarItemRecord) -> AccessibilitySnapshot {
        .init(
            processIdentifier: 42,
            processName: record.hostName,
            bundleIdentifier: record.identity.bundleIdentifier,
            title: record.identity.originalName,
            role: kAXMenuBarItemRole as String,
            subrole: nil,
            identifier: record.identity.axIdentifier,
            positionX: Double(record.manualOrder * 30), positionY: 0, width: 24, height: 24,
            actions: record.capability == .launchOnly ? [] : [kAXPressAction as String],
            accessibilityPath: record.identity.path
        )
    }
}

private actor UITestCatalogStore: CatalogStoring {
    private let fileURL: URL
    private let seed: CatalogDocument
    private let reset: Bool
    private var prepared = false

    init(directory: URL, seed: CatalogDocument, reset: Bool) {
        fileURL = directory.appendingPathComponent("catalog.json")
        self.seed = seed
        self.reset = reset
    }

    func load() throws -> CatalogDocument {
        try prepareIfNeeded()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try JSONDecoder().decode(CatalogDocument.self, from: Data(contentsOf: fileURL))
        }
        try save(seed)
        return seed
    }

    func save(_ document: CatalogDocument) throws {
        try prepareIfNeeded()
        let data = try JSONEncoder().encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        try prepareIfNeeded()
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }

    private func prepareIfNeeded() throws {
        guard !prepared else { return }
        prepared = true
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if reset, FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
}

private struct UITestAccessibility: AccessibilityServing {
    let result: AccessibilityScanResult
    func scan() async -> AccessibilityScanResult { result }
    func press(_ snapshot: AccessibilitySnapshot) async -> Result<Void, AccessibilityDomainError> { .success(()) }
}

private struct UITestLauncher: ApplicationLaunching {
    func launch(bundleIdentifier: String) async -> Bool { true }
}

private struct UITestHostMetadataResolver: HostMetadataResolving {
    @MainActor
    func metadata(for snapshot: AccessibilitySnapshot) -> HostApplicationMetadata? {
        HostApplicationMetadata(
            displayName: snapshot.processName,
            icon: nil,
            bundleIdentifier: snapshot.bundleIdentifier,
            applicationURL: nil
        )
    }
}

@MainActor
private final class UITestPermissionEffects: PermissionEffectHandling {
    func requestSystemPrompt() {}
    func openAccessibilitySettings() {}
    func requestAccessibilityReset() -> Bool { false }
}
#endif
