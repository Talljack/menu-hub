import AppKit
import MenuHubCore
import ServiceManagement
import SwiftUI

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .notRegistered: self = .disabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }

    var label: String {
        switch self {
        case .enabled: L("settings.loginEnabled")
        case .disabled: L("settings.loginDisabled")
        case .requiresApproval: L("settings.loginApproval")
        case .unavailable: L("settings.loginUnavailable")
        }
    }
}

@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published private(set) var status = LaunchAtLoginStatus(SMAppService.mainApp.status)
    @Published private(set) var errorMessage: String?

    var enabled: Bool { status == .enabled }

    func refresh() { status = LaunchAtLoginStatus(SMAppService.mainApp.status) }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}

struct SettingsEnvironment {
    let controller: CatalogController
    let panelModel: HubPanelModel
    let registerHotKey: @MainActor (HotKeyDescriptor) -> HotKeyRegistrationResult
    let showManagement: @MainActor () -> Void
    let restoreMenuBar: @MainActor () -> Void
    let exportDiagnostics: @MainActor () -> Void
    let applyPreferences: @MainActor (Preferences) -> Void
}

private enum SettingsSection: CaseIterable, Identifiable {
    case general, appearance, items, shortcuts, permissions, diagnostics
    var id: Self { self }
    var title: String {
        switch self {
        case .general: L("settings.general")
        case .appearance: L("settings.appearance")
        case .items: L("settings.items")
        case .shortcuts: L("settings.shortcuts")
        case .permissions: L("settings.permissions")
        case .diagnostics: L("settings.diagnostics")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .items: "square.grid.2x2"
        case .shortcuts: "keyboard"
        case .permissions: "hand.raised"
        case .diagnostics: "stethoscope"
        }
    }
}

struct SettingsView: View {
    let environment: SettingsEnvironment
    @ObservedObject private var controller: CatalogController
    @ObservedObject private var panelModel: HubPanelModel
    @StateObject private var loginModel = LaunchAtLoginModel()
    @State private var selection: SettingsSection? = .general
    @State private var hotKeyConflict = false

    init(environment: SettingsEnvironment) {
        self.environment = environment
        controller = environment.controller
        panelModel = environment.panelModel
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            Form { sectionContent(selection ?? .general) }
                .formStyle(.grouped)
                .navigationTitle((selection ?? .general).title)
        }
        .frame(minWidth: 680, minHeight: 480)
        .onAppear { loginModel.refresh() }
    }

    @ViewBuilder
    private func sectionContent(_ section: SettingsSection) -> some View {
        switch section {
        case .general: generalSection
        case .appearance: appearanceSection
        case .items: itemsSection
        case .shortcuts: shortcutsSection
        case .permissions: permissionsSection
        case .diagnostics: diagnosticsSection
        }
    }

    private var generalSection: some View {
        Group {
            Section {
                Toggle(L("settings.launchAtLogin"), isOn: Binding(
                    get: { loginModel.enabled },
                    set: { value in
                        loginModel.setEnabled(value)
                        setPreference { $0.launchAtLogin = loginModel.enabled }
                    }
                ))
                LabeledContent(L("settings.actualStatus"), value: loginModel.status.label)
                if let error = loginModel.errorMessage { Text(error).foregroundStyle(.red) }
                if loginModel.status == .requiresApproval {
                    Button(L("settings.openLoginItems")) { SMAppService.openSystemSettingsLoginItems() }
                }
                if loginModel.status == .unavailable {
                    Text(L("settings.loginUnavailableHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                preferenceToggle(L("settings.restoreHidden"), \.restoreHiddenState)
                preferenceToggle(L("settings.closeFocusLoss"), \.closeOnFocusLoss)
                preferenceToggle(L("settings.closeAfterAction"), \.closeAfterSuccessfulTrigger)
                preferenceToggle(L("settings.automaticScan"), \.automaticScanning)
                Picker(L("settings.language"), selection: languageBinding) {
                    ForEach(SettingsLanguageOptions.all, id: \.self) { preference in
                        Text(preference == .system ? L("settings.languageSystem") : preference.nativeName)
                            .tag(preference)
                    }
                }
                Text(L("settings.languageRestartHint")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSection: some View {
        Group {
            Section {
                Picker(L("settings.appearancePicker"), selection: preferenceBinding(\.appearance)) {
                    Text(L("settings.appearanceSystem")).tag(AppearancePreference.system)
                    Text(L("settings.appearanceLight")).tag(AppearancePreference.light)
                    Text(L("settings.appearanceDark")).tag(AppearancePreference.dark)
                }.pickerStyle(.segmented)
                Picker(L("settings.layout"), selection: preferenceBinding(\.layout)) {
                    Text(L("settings.layoutCompact")).tag(LayoutPreference.compact)
                    Text(L("settings.layoutGrid")).tag(LayoutPreference.grid)
                }.pickerStyle(.segmented)
            }
            Section {
                preferenceToggle(L("settings.showGroupHeadings"), \.showGroupHeadings)
                preferenceToggle(L("settings.showCapabilities"), \.showCapabilities)
                Text(L("settings.accessibilityAppearanceHint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var itemsSection: some View {
        Section {
            Text(L("settings.itemsDescription"))
            Button(L("settings.openManagement"), action: environment.showManagement)
        }
    }

    private var shortcutsSection: some View {
        Group {
            Section(L("settings.openPanel")) {
                ShortcutRecorderView(
                    descriptor: HotKeyDescriptor(controller.document.preferences.hotKey),
                    conflict: hotKeyConflict
                ) { descriptor in
                    let result = environment.registerHotKey(descriptor)
                    hotKeyConflict = result == .conflict
                    guard result == .registered else { return }
                    setPreference { $0.hotKey = descriptor.preference }
                }
                if hotKeyConflict { Text(L("settings.hotKeyConflict")) }
            }
            Section(L("settings.fixedShortcuts")) {
                LabeledContent(L("settings.toggleHidden"), value: L("settings.optionClick"))
                LabeledContent(L("settings.favoriteShortcuts"), value: "⌘1 … ⌘9")
            }
            Button(L("settings.restoreDefaultShortcut")) {
                let descriptor = HotKeyDescriptor.default
                let result = environment.registerHotKey(descriptor)
                hotKeyConflict = result == .conflict
                if result == .registered { setPreference { $0.hotKey = descriptor.preference } }
            }
        }
    }

    private var permissionsSection: some View {
        Group {
            Section {
                LabeledContent("Accessibility", value: L(panelModel.permissionGranted ? "settings.authorized" : "settings.notAuthorized"))
                Button(L("settings.recheck")) { panelModel.applicationBecameActive(isTrusted: AccessibilityClient.isTrusted()) }
                Button(L("settings.openSystemSettings")) { panelModel.openAccessibilitySettings() }
                Text(L("settings.permissionExplanation"))
            }
            Section(L("settings.localData")) {
                Text(applicationSupportDirectory.path).textSelection(.enabled)
                Button(L("settings.exportData"), action: exportLocalData)
                Button(L("settings.clearData"), role: .destructive, action: clearLocalData)
                Text(L("settings.privacyStatement"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsSection: some View {
        Group {
            Section {
                Button(L("settings.rescan")) { panelModel.refresh() }
                Button(L("settings.rebuildIndex")) { panelModel.rebuildSearchIndex() }
                Button(L("settings.restoreMenuBar"), action: environment.restoreMenuBar)
                Button(L("settings.exportDiagnostics"), action: environment.exportDiagnostics)
            }
            Section(L("settings.version")) {
                LabeledContent(L("common.appName"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("settings.developmentBuild"))
                LabeledContent(L("diagnostics.macos"), value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent(L("settings.recentError"), value: recentError)
            }
        }
    }

    private var recentError: String {
        if let action = controller.errors.actionFailure {
            switch action {
            case .accessibility(let error): return error.rawValue
            case .launchFailed: return "launchFailed"
            }
        }
        if controller.errors.saveMessage != nil { return "persistenceFailure" }
        if !controller.errors.scanMessages.isEmpty || !controller.errors.scanWarnings.isEmpty { return "scanFailure" }
        return L("common.none")
    }

    private var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Menu Hub", isDirectory: true)
    }

    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { controller.document.preferences[keyPath: keyPath] },
            set: { value in setPreference { $0[keyPath: keyPath] = value } }
        )
    }

    private var languageBinding: Binding<LanguagePreference> {
        Binding(
            get: { controller.document.preferences.language },
            set: { value in
                LocalizationController.apply(value)
                setPreference { $0.language = value }
            }
        )
    }

    private func preferenceToggle(_ title: String, _ keyPath: WritableKeyPath<Preferences, Bool>) -> some View {
        Toggle(title, isOn: preferenceBinding(keyPath))
    }

    private func setPreference(_ mutation: @escaping (inout Preferences) -> Void) {
        Task {
            await controller.updatePreferences(mutation)
            environment.applyPreferences(controller.document.preferences)
        }
    }

    private func exportLocalData() {
        guard let data = try? JSONEncoder().encode(controller.document) else { return }
        save(data: data, suggestedName: "Menu-Hub-Data.json")
    }

    private func clearLocalData() {
        let alert = NSAlert()
        alert.messageText = L("settings.clearConfirmTitle")
        alert.informativeText = L("settings.clearConfirmBody")
        alert.addButton(withTitle: L("settings.clearConfirmAction"))
        alert.addButton(withTitle: L("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await controller.clearLocalData()
            loginModel.setEnabled(false)
            environment.applyPreferences(.default)
        }
    }

    private func save(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }
}
