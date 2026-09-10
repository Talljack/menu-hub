import AppKit
import Combine
import MenuHubCore
import SwiftUI

enum RestoreHiddenStartupPolicy {
    static func shouldRestore(preferenceEnabled: Bool, lastVisibilityHidden: Bool, previousRunEndedUnexpectedly: Bool) -> Bool {
        preferenceEnabled && lastVisibilityHidden && !previousRunEndedUnexpectedly
    }
}

enum MenuHubWindowPlacement {
    static func centeredOrigin(windowFrame: NSRect, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - (windowFrame.width / 2),
            y: visibleFrame.midY - (windowFrame.height / 2)
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum DefaultsKey {
        static let hideWidth = "phase0.hideWidth"
        static let restoreHidden = "phase0.restoreHidden"
        static let wasHidden = "phase0.wasHidden"
        static let launchInProgress = "phase0.launchInProgress"
        static let hasCompletedOnboarding = "onboarding.completed.v1"
    }

    private let hubItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let spacerItem = NSStatusBar.system.statusItem(withLength: 1)
    private let accessibilityClient = AccessibilityClient()
    private let diagnosticsController = DiagnosticsController()
    #if DEBUG
    private let uiTestRuntime = UITestRuntime.current
    #endif
    private lazy var panelModel: HubPanelModel = {
        #if DEBUG
        if let uiTestRuntime { return uiTestRuntime.makeModel() }
        #endif
        return HubPanelModel(client: accessibilityClient)
    }()
    private lazy var permissionCoordinator: PermissionCoordinator = {
        #if DEBUG
        if let uiTestRuntime {
            return PermissionCoordinator(model: panelModel, trustProvider: { uiTestRuntime.trusted })
        }
        #endif
        return PermissionCoordinator(model: panelModel)
    }()
    private lazy var hotKeyController = HotKeyController { [weak self] in self?.togglePanel() }
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width: HubPanelLayout.width, height: 430)
        popover.contentViewController = NSHostingController(rootView: HubPanelView(model: panelModel))
        panelModel.onSuccessfulInvocation = { [weak popover] in popover?.performClose(nil) }
        return popover
    }()
    private var state = SpacerState.startup(safeWidth: 1, requestedHiddenWidth: 240, shouldRestoreHiddenPreference: false, maximumSafeWidth: 600)
    private var animationTask: Task<Void, Never>?
    private var setupMarkerVisible = false
    private var onboardingWindow: NSWindow?
    private var settingsWindowController: NSWindowController?
    private var managementWindowController: NSWindowController?
    private lazy var managementModel = ManagementModel(controller: panelModel.catalogController)
    private var diagnosticSubscriptions = Set<AnyCancellable>()
    private var diagnosticScanStartedAt: Date?
    private var terminationPreparationInProgress = false
    private var terminationPrepared = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        #if DEBUG
        if let uiTestRuntime {
            LocalizationController.apply(uiTestRuntime.language)
            switch uiTestRuntime.appearance {
            case .system: NSApp.appearance = nil
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
        #endif
        let previousRunEndedUnexpectedly = defaults.bool(forKey: DefaultsKey.launchInProgress)
        defaults.set(true, forKey: DefaultsKey.launchInProgress)

        let savedHidden = defaults.bool(forKey: DefaultsKey.wasHidden)
        let requestedHiddenWidth = defaults.object(forKey: DefaultsKey.hideWidth) as? Double ?? 240
        let maximumSafeWidth = maximumSafeSpacerWidth()
        if previousRunEndedUnexpectedly {
            state = .startupAfterUncleanExit(
                savedHidden: savedHidden,
                safeWidth: 1,
                requestedHiddenWidth: requestedHiddenWidth,
                maximumSafeWidth: maximumSafeWidth
            )
            defaults.set(false, forKey: DefaultsKey.wasHidden)
        } else {
            state = .startup(
                safeWidth: 1,
                requestedHiddenWidth: requestedHiddenWidth,
                shouldRestoreHiddenPreference: RestoreHiddenStartupPolicy.shouldRestore(
                    preferenceEnabled: defaults.bool(forKey: DefaultsKey.restoreHidden),
                    lastVisibilityHidden: savedHidden,
                    previousRunEndedUnexpectedly: false
                ),
                maximumSafeWidth: maximumSafeWidth
            )
        }
        configureStatusItems()
        configureMainMenu()
        #if DEBUG
        panelModel.hotKeyAvailable = uiTestRuntime == nil ? hotKeyController.registerCommandOptionControlM() : true
        #else
        panelModel.hotKeyAvailable = hotKeyController.registerCommandOptionControlM()
        #endif
        panelModel.onOpenSettings = { [weak self] in self?.presentSettings() }
        panelModel.onOpenManagement = { [weak self] itemID in
            self?.showManagement(selecting: itemID)
        }
        #if DEBUG
        if uiTestRuntime == nil { registerPersistedHotKeyWhenLoaded() }
        #else
        registerPersistedHotKeyWhenLoaded()
        #endif
        permissionCoordinator.start()
        panelModel.startBackgroundUpdates()
        observeDiagnostics()
        observeSafetyEvents()
        spacerItem.length = state.currentWidth

        #if DEBUG
        if let uiTestRuntime {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                if uiTestRuntime.showsOnboarding { self?.presentOnboarding() }
                else { self?.showPanelIfNeeded() }
            }
        } else if !defaults.bool(forKey: DefaultsKey.hasCompletedOnboarding) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.presentOnboarding()
            }
        }
        #else
        if !defaults.bool(forKey: DefaultsKey.hasCompletedOnboarding) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.presentOnboarding()
            }
        }
        #endif

        if state.shouldRestoreHiddenPreference {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.hideItems()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionCoordinator.stop()
        panelModel.stopMonitoring()
        panelModel.shutdown()
        hotKeyController.shutdown()
        let wasHidden = state.visibility == .hidden
        revealItems(immediate: true)
        UserDefaults.standard.set(wasHidden, forKey: DefaultsKey.wasHidden)
        UserDefaults.standard.set(false, forKey: DefaultsKey.launchInProgress)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationPrepared { return .terminateNow }
        if terminationPreparationInProgress { return .terminateLater }
        terminationPreparationInProgress = true
        Task { @MainActor [weak self] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: true)
                return
            }
            await panelModel.prepareForTermination()
            terminationPrepared = true
            terminationPreparationInProgress = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanelIfNeeded()
        return true
    }

    private func configureStatusItems() {
        if let button = hubItem.button {
            button.image = MenuBarIconFactory.makeImage()
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = L("common.appName")
            button.setAccessibilityLabel(L("common.appName"))
            button.target = self
            button.action = #selector(handleHubClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateSpacerAppearance()
    }

    private func observeSafetyEvents() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleSafetyEvent), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleSafetyEvent), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleApplicationSetChange), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleApplicationSetChange), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    @objc private func handleSafetyEvent() {
        revealItems(immediate: true)
        panelModel.applicationSetDidChange()
    }

    @objc private func handleApplicationSetChange() {
        panelModel.applicationSetDidChange()
    }

    @objc private func handleHubClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            toggleVisibility()
            return
        }

        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.buttonNumber == 1 {
            showContextMenu(from: sender)
            return
        }

        togglePanel()
    }

    private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        showPanelIfNeeded()
    }

    private func showPanelIfNeeded() {
        guard !popover.isShown, let button = hubItem.button else { return }
        permissionCoordinator.recheckPermission()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu(from sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: L(state.visibility == .revealed ? "statusMenu.hideItems" : "statusMenu.revealItems"), action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(withTitle: L("settings.rescan"), action: #selector(runScan), keyEquivalent: "")
        menu.addItem(withTitle: L("statusMenu.settings"), action: #selector(presentSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("statusMenu.restore"), action: #selector(restoreMenuBar), keyEquivalent: "")
        menu.addItem(withTitle: L("statusMenu.quit"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
    }

    @objc private func toggleVisibility() {
        state.visibility == .revealed ? hideItems() : revealItems()
    }

    @objc private func toggleSetupMarker() {
        setupMarkerVisible.toggle()
        revealItems(immediate: true)
        updateSpacerAppearance()
    }

    @objc private func checkPermission() {
        permissionCoordinator.recheckPermission()
        if !popover.isShown { togglePanel() }
    }

    @objc private func requestPermission() {
        panelModel.requestPermission()
        if !popover.isShown { togglePanel() }
    }

    @objc private func runScan() {
        panelModel.refresh()
    }

    private func observeDiagnostics() {
        let controller = panelModel.catalogController
        controller.$isScanning
            .sink { [weak self, weak controller] isScanning in
                guard let self else { return }
                if isScanning {
                    diagnosticScanStartedAt = Date()
                } else if let startedAt = diagnosticScanStartedAt {
                    diagnosticScanStartedAt = nil
                    diagnosticsController.record(
                        domain: "scan",
                        scanCount: controller?.runtimeSnapshots.count ?? 0,
                        durationMilliseconds: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                    )
                }
            }
            .store(in: &diagnosticSubscriptions)

        controller.$errors
            .dropFirst()
            .sink { [weak self] errors in
                guard let self else { return }
                if errors.saveMessage != nil {
                    diagnosticsController.record(domain: "persistence", errorCode: "persistenceFailure")
                }
                if !errors.scanMessages.isEmpty || !errors.scanWarnings.isEmpty {
                    diagnosticsController.record(domain: "scan", errorCode: "scanFailure")
                }
            }
            .store(in: &diagnosticSubscriptions)

        controller.$lastActionOutcome
            .compactMap { $0 }
            .sink { [weak self] outcome in
                guard let self else { return }
                let errorCode: String?
                switch outcome {
                case .pressed, .openedHost: errorCode = nil
                case .unavailable: errorCode = "unavailable"
                case .failed(.launchFailed): errorCode = "launchFailed"
                case .failed(.accessibility(let error)): errorCode = error.rawValue
                }
                diagnosticsController.record(domain: "action", errorCode: errorCode)
            }
            .store(in: &diagnosticSubscriptions)
    }

    @objc private func restoreMenuBar() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.wasHidden)
        revealItems(immediate: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("statusMenu.settings"), action: #selector(presentSettings), keyEquivalent: ",")
        appMenu.addItem(withTitle: L("statusMenu.manage"), action: #selector(presentManagement), keyEquivalent: "m")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("statusMenu.quit"), action: #selector(quit), keyEquivalent: "q")
        for item in appMenu.items { item.target = self }
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func presentSettings() {
        if settingsWindowController == nil {
            let environment = SettingsEnvironment(
                controller: panelModel.catalogController,
                panelModel: panelModel,
                registerHotKey: { [weak self] descriptor in
                    guard let self else { return .systemError(OSStatus(paramErr)) }
                    let result = hotKeyController.register(descriptor)
                    panelModel.hotKeyAvailable = result == .registered
                    return result
                },
                showManagement: { [weak self] in self?.presentManagement() },
                restoreMenuBar: { [weak self] in self?.restoreMenuBar() },
                exportDiagnostics: { [weak self] in self?.diagnosticsController.presentExportPanel() }
                , applyPreferences: { [weak self] preferences in self?.applyPreferences(preferences) }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(environment: environment)))
            window.title = L("statusMenu.settingsWindowTitle")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("MenuHub.SettingsWindow")
            window.setContentSize(NSSize(width: 720, height: 520))
            settingsWindowController = NSWindowController(window: window)
        }
        showWindow(settingsWindowController, centeredOnInvokingScreen: true)
    }

    @objc private func presentManagement() { showManagement(selecting: nil) }

    private func showManagement(selecting itemID: String?) {
        if let itemID { managementModel.selectedItemID = itemID }
        if managementWindowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: ManagementWindow(model: managementModel)
            ))
            window.title = L("statusMenu.managementWindowTitle")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("MenuHub.ManagementWindow")
            window.setContentSize(NSSize(width: 760, height: 520))
            managementWindowController = NSWindowController(window: window)
        }
        showWindow(managementWindowController)
    }

    private func registerPersistedHotKeyWhenLoaded() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<100 where panelModel.operationState == .loading {
                try? await Task.sleep(for: .milliseconds(20))
            }
            let descriptor = HotKeyDescriptor(panelModel.catalogController.document.preferences.hotKey)
            panelModel.hotKeyAvailable = hotKeyController.register(descriptor) == .registered
            applyPreferences(panelModel.catalogController.document.preferences)
        }
    }

    private func applyPreferences(_ preferences: Preferences) {
        LocalizationController.apply(preferences.language)
        configureMainMenu()
        settingsWindowController?.window?.title = L("statusMenu.settingsWindowTitle")
        managementWindowController?.window?.title = L("statusMenu.managementWindowTitle")
        popover.behavior = preferences.closeOnFocusLoss ? .transient : .applicationDefined
        UserDefaults.standard.set(preferences.restoreHiddenState, forKey: DefaultsKey.restoreHidden)
        if !preferences.restoreHiddenState {
            UserDefaults.standard.set(false, forKey: DefaultsKey.wasHidden)
        }
        switch preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func showWindow(_ controller: NSWindowController?, centeredOnInvokingScreen: Bool = false) {
        let invokingScreen = hubItem.button?.window?.screen ?? NSScreen.main
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller?.showWindow(nil)
        if centeredOnInvokingScreen,
           let window = controller?.window,
           let visibleFrame = invokingScreen?.visibleFrame {
            window.setFrameOrigin(MenuHubWindowPlacement.centeredOrigin(
                windowFrame: window.frame,
                visibleFrame: visibleFrame
            ))
        }
        controller?.window?.makeKeyAndOrderFront(nil)
    }

    private func hideItems() {
        var next = state
        next.hideItems()
        UserDefaults.standard.set(true, forKey: DefaultsKey.wasHidden)
        animateWidth(to: presentationWidth(for: next))
        state = next
    }

    private func revealItems(immediate: Bool = false) {
        var next = state
        next.revealForSafety()
        let targetWidth = presentationWidth(for: next)
        if immediate {
            animationTask?.cancel()
            spacerItem.length = targetWidth
        } else {
            animateWidth(to: targetWidth)
        }
        state = next
        UserDefaults.standard.set(false, forKey: DefaultsKey.wasHidden)
    }

    private func animateWidth(to target: Double) {
        animationTask?.cancel()
        let start = spacerItem.length
        animationTask = Task { @MainActor [weak self] in
            for step in 1...12 {
                guard !Task.isCancelled else { return }
                self?.spacerItem.length = start + ((target - start) * (Double(step) / 12))
                try? await Task.sleep(for: .milliseconds(15))
            }
        }
    }

    private func updateSpacerAppearance() {
        guard let button = spacerItem.button else { return }
        spacerItem.length = presentationWidth(for: state)
        button.title = setupMarkerVisible ? "⇆" : ""
        button.toolTip = setupMarkerVisible ? L("statusMenu.markerHelp") : nil
        button.isEnabled = setupMarkerVisible
        button.setAccessibilityLabel(L(setupMarkerVisible ? "accessibility.setupDivider" : "accessibility.hiddenSpacer"))
    }

    private func presentationWidth(for state: SpacerState) -> Double {
        state.presentationWidth(
            setupMarkerVisible: setupMarkerVisible,
            minimumMarkerWidth: SpacerPresentation.minimumMarkerWidth
        )
    }

    private func maximumSafeSpacerWidth() -> Double {
        guard let screen = NSScreen.main else { return 320 }
        return max(80, min(600, screen.visibleFrame.width * 0.45))
    }

    @objc private func presentOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(
            model: panelModel,
            hotKeyAvailable: panelModel.hotKeyAvailable,
            onShowSetupMarker: { [weak self] in
                guard let self else { return }
                setupMarkerVisible = true
                revealItems(immediate: true)
                updateSpacerAppearance()
            },
            onTestHide: { [weak self] in self?.hideItems() },
            onRestore: { [weak self] in self?.restoreMenuBar() },
            onComplete: { [weak self] in
                UserDefaults.standard.set(true, forKey: DefaultsKey.hasCompletedOnboarding)
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = L("common.appName")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === onboardingWindow else { return }
        onboardingWindow = nil
    }
}
