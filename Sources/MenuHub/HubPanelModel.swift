import AppKit
import Combine
import MenuHubCore

protocol PanelLiveUpdateCancellation: AnyObject, Sendable {
    func cancel()
}

@MainActor
protocol PanelLiveUpdateScheduling {
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> any PanelLiveUpdateCancellation
}

private final class TaskPanelLiveUpdateCancellation: PanelLiveUpdateCancellation, @unchecked Sendable {
    let task: Task<Void, Never>
    init(task: Task<Void, Never>) { self.task = task }
    func cancel() { task.cancel() }
}

@MainActor
private struct SystemPanelLiveUpdateScheduler: PanelLiveUpdateScheduling {
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> any PanelLiveUpdateCancellation {
        let nanoseconds = UInt64(max(interval, 0.1) * 1_000_000_000)
        let task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { break }
                action()
            }
        }
        return TaskPanelLiveUpdateCancellation(task: task)
    }
}

struct HubPanelItem: Identifiable, Equatable {
    let record: MenuBarItemRecord
    let snapshot: AccessibilitySnapshot?
    let effectiveLaunchOnly: Bool
    let hostIcon: NSImage?
    var id: String { record.id }
    var name: String { primaryTitle }
    var hostName: String { record.hostName }
    var primaryTitle: String {
        let processFallback = snapshot.map(\.processName) ?? ""
        let bundleFallback = record.identity.bundleIdentifier.split(separator: ".").last.map(String.init) ?? ""
        let host = firstNonempty([record.hostName, processFallback, bundleFallback, L("panel.unknownApp")])
        let item = normalized(record.displayName, fallback: record.identity.originalName)
        return host.localizedStandardCompare(item) == .orderedSame ? host : "\(host) — \(item)"
    }
    var secondaryTitle: String {
        if effectiveLaunchOnly { return L("panel.openApp") }
        if canPress { return L("panel.press") }
        return L(snapshot == nil ? "panel.currentlyUnavailable" : "panel.unavailable")
    }
    var canPress: Bool { snapshot != nil && (record.capability == .full || record.capability == .actionable) }
    var isLaunchOnly: Bool { effectiveLaunchOnly }
    var canInvoke: Bool { effectiveLaunchOnly || canPress }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.record == rhs.record && lhs.snapshot == rhs.snapshot && lhs.effectiveLaunchOnly == rhs.effectiveLaunchOnly
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func firstNonempty(_ values: [String]) -> String {
        values.lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? L("panel.unknownApp")
    }

}

struct PanelGroupSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let items: [MenuBarItemRecord]
}

struct PanelSnapshot: Equatable, Sendable {
    var favorites: [MenuBarItemRecord]
    var recent: [MenuBarItemRecord]
    var frequent: [MenuBarItemRecord]
    var customGroups: [PanelGroupSnapshot]
    var all: [MenuBarItemRecord]
    var search: [MenuBarItemRecord]
    static let empty = Self(favorites: [], recent: [], frequent: [], customGroups: [], all: [], search: [])
}

enum PanelOperationState: Equatable {
    case idle
    case loading
    case scanning
    case invoking(itemID: String)
}

enum PanelMonitoringMode: Equatable {
    case stopped
    case background
    case foreground

    var interval: TimeInterval? {
        switch self {
        case .stopped: nil
        case .background: 5
        case .foreground: 1
        }
    }
}

enum PanelContentState: Equatable {
    case loading, scanning, empty, content

    static func resolve(
        operation: PanelOperationState,
        hasCompletedScan: Bool,
        itemCount: Int
    ) -> Self {
        if operation == .loading { return .loading }
        if operation == .scanning, itemCount == 0 { return .scanning }
        if hasCompletedScan, itemCount == 0 { return .empty }
        return .content
    }
}

enum PanelStatusMessageKey: Equatable {
    case noItems
    case loadFailed
    case saveFailed
    case scanFailed
    case permissionDenied
    case staleItem
    case actionUnsupported
    case targetUnresponsive
    case launchFailed
    case actionFailed
    case unavailable
    case permissionResetUnavailable
    case settingsUnavailable
}

@MainActor
protocol PermissionEffectHandling: AnyObject {
    func requestSystemPrompt()
    func openAccessibilitySettings()
    func confirmAccessibilityReset() -> Bool
    func requestAccessibilityReset() -> Bool
    func requestAccessibilityReset(completion: @escaping @MainActor (Bool) -> Void)
    func cancelAccessibilityReset()
}

extension PermissionEffectHandling {
    func confirmAccessibilityReset() -> Bool { false }
    func requestAccessibilityReset(completion: @escaping @MainActor (Bool) -> Void) {
        completion(requestAccessibilityReset())
    }
    func cancelAccessibilityReset() {}
}

@MainActor
final class HubPanelModel: ObservableObject {
    @Published var query = "" { didSet { rebuildSnapshot() } }
    @Published var selectionID: String?
    @Published private(set) var permissionState: PermissionState
    @Published private(set) var operationState: PanelOperationState = .idle
    @Published private(set) var statusMessageKey: PanelStatusMessageKey?
    @Published var hotKeyAvailable = true
    @Published private(set) var snapshot: PanelSnapshot = .empty
    @Published var actionMenuPresentationID: HubItemPresentationID?
    @Published private(set) var lastFailedItemID: String?
    @Published private(set) var lastSucceededItemID: String?
    @Published private(set) var unreadBadgePresentation: UnreadBadgePresentation = .hidden

    // Compatibility surface for the phase-0 view. The published states above are authoritative.
    @Published private(set) var items: [HubPanelItem] = []
    @Published private(set) var recentIDs: [String] = []
    var permissionGranted: Bool { permissionState == .authorized }
    /// Every non-authorized permission state retains launcher fallback; no parallel flag is persisted.
    var isLauncherMode: Bool { permissionState != .authorized }
    var isScanning: Bool { operationState == .scanning }
    var panelSnapshot: PanelSnapshot { snapshot }
    var lastRefreshAt: Date? { controller.lastRefreshAt }
    var contentState: PanelContentState {
        .resolve(
            operation: operationState,
            hasCompletedScan: controller.hasCompletedScan,
            itemCount: items.count
        )
    }
    var statusMessage: String? {
        get { statusMessageKey.map(Self.localizedMessage) }
        set { if newValue == nil { statusMessageKey = nil } }
    }
    var onSuccessfulInvocation: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenManagement: ((String?) -> Void)?
    var catalogController: CatalogController { controller }

    private let controller: CatalogController
    private let now: @Sendable () -> Date
    private let permissionEffectHandler: any PermissionEffectHandling
    private let liveUpdateScheduler: any PanelLiveUpdateScheduling
    private let accessibilityTrustProvider: @MainActor () -> Bool
    private let runningUserApplicationBundleIdentifiers: (@MainActor () -> Set<String>)?
    private let failureFeedbackDuration: Duration
    private var subscriptions = Set<AnyCancellable>()
    private var invocationGeneration = 0
    private var invocationTask: Task<Void, Never>?
    private var liveUpdateCancellation: (any PanelLiveUpdateCancellation)?
    private(set) var monitoringMode: PanelMonitoringMode = .stopped
    private var liveUpdatesActive: Bool { monitoringMode != .stopped }
    private var liveScanGeneration = 0
    private var inFlightLiveScanTask: Task<Void, Never>?
    private var successFeedbackTask: Task<Void, Never>?
    private var failureFeedbackTask: Task<Void, Never>?
    private var pendingRepairReason: PermissionRepairReason?
    private var manualScanTask: Task<Void, Never>?
    private var manualScanGeneration = 0
    private var nextFullDiscoveryAt: Date?
    private var lastAutomaticScanningPreference: Bool?

    deinit {
        invocationTask?.cancel()
        liveUpdateCancellation?.cancel()
        inFlightLiveScanTask?.cancel()
        successFeedbackTask?.cancel()
        failureFeedbackTask?.cancel()
        manualScanTask?.cancel()
    }

    init(client: AccessibilityClient) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Menu Hub", isDirectory: true)
        controller = CatalogController(
            store: CatalogStore(directory: directory), accessibility: client,
            launcher: WorkspaceApplicationLauncher(), scanPersistenceDelay: .seconds(5)
        )
        now = Date.init
        permissionEffectHandler = SystemPermissionEffectHandler()
        liveUpdateScheduler = SystemPanelLiveUpdateScheduler()
        accessibilityTrustProvider = { AccessibilityClient.isTrusted() }
        runningUserApplicationBundleIdentifiers = { HostApplicationResolver.runningUserApplicationBundleIdentifiers() }
        failureFeedbackDuration = .seconds(3)
        permissionState = AccessibilityClient.isTrusted() ? .authorized : .unknown
        observeController()
        operationState = .loading
        Task { [weak self] in
            await self?.controller.load()
            guard let self else { return }
            if operationState == .loading { operationState = .idle }
            rebuildSnapshot()
            if liveUpdatesActive, controller.document.preferences.automaticScanning, permissionGranted,
               inFlightLiveScanTask == nil, !controller.isScanning {
                startLiveScan(fullDiscovery: true)
                scheduleLiveUpdatesIfNeeded()
            }
        }
    }

    init(
        controller: CatalogController,
        now: @escaping @Sendable () -> Date = Date.init,
        initialPermissionState: PermissionState = .unknown,
        permissionEffectHandler: any PermissionEffectHandling = SystemPermissionEffectHandler(),
        liveUpdateScheduler: any PanelLiveUpdateScheduling = SystemPanelLiveUpdateScheduler(),
        accessibilityTrustProvider: @escaping @MainActor () -> Bool = { true },
        runningUserApplicationBundleIdentifiers: (@MainActor () -> Set<String>)? = nil,
        failureFeedbackDuration: Duration = .seconds(3)
    ) {
        self.controller = controller
        self.now = now
        self.permissionState = initialPermissionState
        self.permissionEffectHandler = permissionEffectHandler
        self.liveUpdateScheduler = liveUpdateScheduler
        self.accessibilityTrustProvider = accessibilityTrustProvider
        self.runningUserApplicationBundleIdentifiers = runningUserApplicationBundleIdentifiers
        self.failureFeedbackDuration = failureFeedbackDuration
        observeController()
        rebuildSnapshot()
    }

    var filteredItems: [HubPanelItem] {
        let source = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? snapshot.all : snapshot.search
        let allowed = Set(source.map(\.id))
        return items.filter { allowed.contains($0.id) }
    }

    var recentItems: [HubPanelItem] {
        let recent = Set(snapshot.recent.map(\.id))
        return items.filter { recent.contains($0.id) }.sorted {
            (recentIDs.firstIndex(of: $0.id) ?? .max) < (recentIDs.firstIndex(of: $1.id) ?? .max)
        }
    }

    func refresh() {
        let wasAuthorized = permissionGranted
        guard revalidateAccessibilityTrust(), wasAuthorized else { return }
        startScan()
    }

    func startLiveUpdates() {
        stopLiveUpdates()
        monitoringMode = .foreground
        guard controller.document.preferences.automaticScanning else { return }
        let wasAuthorized = permissionGranted
        guard revalidateAccessibilityTrust(), wasAuthorized else { return }
        startLiveScan(fullDiscovery: true)
        scheduleLiveUpdatesIfNeeded()
    }

    func stopLiveUpdates() {
        monitoringMode = .stopped
        liveUpdateCancellation?.cancel()
        liveUpdateCancellation = nil
        liveScanGeneration += 1
        inFlightLiveScanTask?.cancel()
        inFlightLiveScanTask = nil
        nextFullDiscoveryAt = nil
        Task { [controller] in await controller.flushPendingScanPersistence() }
    }

    func startBackgroundUpdates() {
        guard monitoringMode == .stopped else {
            setMonitoringMode(.background)
            return
        }
        monitoringMode = .background
        guard controller.document.preferences.automaticScanning else {
            unreadBadgePresentation = .hidden
            return
        }
        let wasAuthorized = permissionGranted
        guard revalidateAccessibilityTrust(), wasAuthorized else {
            unreadBadgePresentation = .hidden
            return
        }
        if operationState != .loading, inFlightLiveScanTask == nil, !controller.isScanning {
            startLiveScan(fullDiscovery: true)
        }
        scheduleLiveUpdatesIfNeeded()
    }

    func panelDidAppear() {
        if monitoringMode == .stopped {
            monitoringMode = .foreground
            guard controller.document.preferences.automaticScanning, permissionGranted else { return }
            startLiveScan(fullDiscovery: true)
        } else {
            setMonitoringMode(.foreground)
        }
        scheduleLiveUpdatesIfNeeded()
    }

    func panelDidDisappear() {
        if monitoringMode == .stopped {
            startBackgroundUpdates()
        } else {
            setMonitoringMode(.background)
        }
    }

    func stopMonitoring() { stopLiveUpdates() }

    private func setMonitoringMode(_ mode: PanelMonitoringMode) {
        guard mode != monitoringMode else { return }
        liveUpdateCancellation?.cancel()
        liveUpdateCancellation = nil
        monitoringMode = mode
        if mode == .stopped {
            unreadBadgePresentation = .hidden
            return
        }
        scheduleLiveUpdatesIfNeeded()
    }

    private func scheduleLiveUpdatesIfNeeded() {
        guard liveUpdatesActive, permissionGranted, liveUpdateCancellation == nil,
              lastAutomaticScanningPreference ?? controller.document.preferences.automaticScanning,
              let interval = monitoringMode.interval else { return }
        liveUpdateCancellation = liveUpdateScheduler.schedule(every: interval) { [weak self] in
            guard let self, self.liveUpdatesActive, self.permissionGranted,
                  self.inFlightLiveScanTask == nil && !self.controller.isScanning else { return }
            if case .invoking = self.operationState { return }
            let fullDiscovery = self.monitoringMode == .foreground
                && (self.nextFullDiscoveryAt.map { self.now() >= $0 } ?? true)
            self.startLiveScan(fullDiscovery: fullDiscovery)
        }
    }

    private func startLiveScan(fullDiscovery: Bool) {
        guard liveUpdatesActive, revalidateAccessibilityTrust() else { return }
        if fullDiscovery { nextFullDiscoveryAt = now().addingTimeInterval(20) }
        liveScanGeneration += 1
        let generation = liveScanGeneration
        inFlightLiveScanTask?.cancel()
        inFlightLiveScanTask = Task { [weak self] in
            guard let self else { return }
            if fullDiscovery { await controller.scan() }
            else { await controller.refreshKnownItems() }
            guard liveUpdatesActive, generation == liveScanGeneration, !Task.isCancelled else { return }
            inFlightLiveScanTask = nil
        }
    }

    func applicationSetDidChange() {
        controller.applicationSetDidChange()
        guard liveUpdatesActive, permissionGranted,
              inFlightLiveScanTask == nil, !controller.isScanning else { return }
        startLiveScan(fullDiscovery: true)
    }

    private func startScan() {
        guard revalidateAccessibilityTrust() else { return }
        manualScanGeneration += 1
        let generation = manualScanGeneration
        manualScanTask?.cancel()
        manualScanTask = Task { [weak self] in
            guard let self else { return }
            await controller.scan()
            guard generation == manualScanGeneration, !Task.isCancelled else { return }
            manualScanTask = nil
        }
    }

    func requestPermission() {
        applyPermissionEvent(.featureRequested)
    }

    func acceptPermissionExplanation() { applyPermissionEvent(.explanationAccepted) }
    func skipPermissionExplanation() { applyPermissionEvent(.explanationSkipped) }
    func applicationBecameActive(isTrusted: Bool) { applyPermissionEvent(.applicationBecameActive(isTrusted: isTrusted)) }
    func confirmPermissionRepair() {
        guard permissionEffectHandler.confirmAccessibilityReset() else { return }
        if case let .repairRequired(reason) = permissionState { pendingRepairReason = reason }
        applyPermissionEvent(.repairConfirmed)
    }
    func permissionResetCompleted() { applyPermissionEvent(.resetCompleted) }

    func openAccessibilitySettings() {
        permissionEffectHandler.openAccessibilitySettings()
        applyPermissionEvent(.openedSettings)
    }

    func invoke(_ item: HubPanelItem) {
        if !item.isLaunchOnly, !revalidateAccessibilityTrust() {
            guard controller.canLaunchHost(for: item.record) else {
                statusMessageKey = .permissionDenied
                return
            }
            beginInvocation(itemID: item.id, forceLaunchHost: true)
            return
        }
        beginInvocation(itemID: item.id, forceLaunchHost: item.isLaunchOnly)
    }

    private func beginInvocation(itemID: String, forceLaunchHost: Bool) {
        suspendLiveScanningForInvocation()
        invocationTask?.cancel()
        invocationGeneration += 1
        let generation = invocationGeneration
        let controller = controller
        statusMessageKey = nil
        lastFailedItemID = nil
        lastSucceededItemID = nil
        failureFeedbackTask?.cancel()
        operationState = .invoking(itemID: itemID)
        invocationTask = Task { [weak self] in
            let outcome = await controller.invoke(itemID: itemID, forceLaunchHost: forceLaunchHost)
            guard let self else { return }
            guard generation == invocationGeneration, !Task.isCancelled else { return }
            operationState = controller.isScanning ? .scanning : .idle
            switch outcome {
            case .pressed, .openedHost: publishSuccess(for: itemID)
            case .failed(let failure): publishFailure(Self.messageKey(for: failure), itemID: itemID, generation: generation)
            case .unavailable: publishFailure(.unavailable, itemID: itemID, generation: generation)
            }
            resumeMonitoringAfterInvocation()
        }
    }

    func invokeSelection(forceLaunchHost: Bool) {
        guard let selectionID, let item = items.first(where: { $0.id == selectionID }), item.canInvoke else { return }
        if !forceLaunchHost { invoke(item); return }
        suspendLiveScanningForInvocation()
        invocationTask?.cancel()
        invocationGeneration += 1
        let generation = invocationGeneration
        operationState = .invoking(itemID: item.id)
        statusMessageKey = nil
        lastFailedItemID = nil
        lastSucceededItemID = nil
        failureFeedbackTask?.cancel()
        invocationTask = Task { [weak self, controller] in
            let outcome = await controller.invoke(itemID: item.id, forceLaunchHost: true)
            guard let self, generation == invocationGeneration, !Task.isCancelled else { return }
            operationState = controller.isScanning ? .scanning : .idle
            switch outcome {
            case .pressed, .openedHost: publishSuccess(for: item.id)
            case .failed(let failure): publishFailure(Self.messageKey(for: failure), itemID: item.id, generation: generation)
            case .unavailable: publishFailure(.unavailable, itemID: item.id, generation: generation)
            }
            resumeMonitoringAfterInvocation()
        }
    }

    func openHost(_ item: HubPanelItem) {
        selectionID = item.id
        invokeSelection(forceLaunchHost: true)
    }

    func toggleFavorite(_ item: HubPanelItem) {
        Task { [controller] in await controller.setFavorite(!item.record.isFavorite, itemID: item.id) }
    }

    func setAlias(_ alias: String?, for item: HubPanelItem) async {
        await controller.setAlias(alias, itemID: item.id)
        rebuildSnapshot()
    }

    func setMembership(_ member: Bool, groupID: UUID, for item: HubPanelItem) async {
        await controller.setMembership(member, itemID: item.id, groupID: groupID)
        rebuildSnapshot()
    }

    func setIgnored(_ ignored: Bool, for item: HubPanelItem) async {
        await controller.setIgnored(ignored, itemID: item.id)
        rebuildSnapshot()
        if ignored, selectionID == item.id { selectionID = nil }
        if ignored, actionMenuPresentationID?.rawValue.hasSuffix(":\(item.id)") == true { actionMenuPresentationID = nil }
    }

    func retestCapability() { refresh() }

    func canOpenHost(_ item: HubPanelItem) -> Bool { controller.canLaunchHost(for: item.record) }

    func openSettings(sendStandardAction: () -> Bool = {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }) {
        if let onOpenSettings { onOpenSettings(); return }
        if !sendStandardAction() { statusMessageKey = .settingsUnavailable }
    }

    func openManagement(itemID: String? = nil) { onOpenManagement?(itemID) }
    func rebuildSearchIndex() { rebuildSnapshot() }

    private func publishSuccess(for itemID: String) {
        failureFeedbackTask?.cancel()
        guard !controller.document.preferences.closeAfterSuccessfulTrigger else {
            onSuccessfulInvocation?()
            return
        }
        lastSucceededItemID = itemID
        successFeedbackTask?.cancel()
        successFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, self?.lastSucceededItemID == itemID else { return }
            self?.lastSucceededItemID = nil
        }
    }

    private func publishFailure(_ message: PanelStatusMessageKey, itemID: String, generation: Int) {
        statusMessageKey = message
        lastFailedItemID = itemID
        failureFeedbackTask?.cancel()
        let duration = failureFeedbackDuration
        failureFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled, generation == invocationGeneration,
                  lastFailedItemID == itemID else { return }
            lastFailedItemID = nil
            if statusMessageKey == message { statusMessageKey = nil }
            controller.clearActionFailure()
        }
    }

    private func suspendLiveScanningForInvocation() {
        liveScanGeneration += 1
        inFlightLiveScanTask?.cancel()
        inFlightLiveScanTask = nil
        controller.invalidateAccessibilityWork()
    }

    private func resumeMonitoringAfterInvocation() {
        guard liveUpdatesActive, permissionGranted, controller.document.preferences.automaticScanning,
              inFlightLiveScanTask == nil, !controller.isScanning else { return }
        startLiveScan(fullDiscovery: false)
    }

    func selectNext() { moveSelection(by: 1) }
    func selectPrevious() { moveSelection(by: -1) }
    func clearSearch() { query = ""; selectionID = nil }
    func cancelPendingInvocation() { invocationGeneration += 1; invocationTask?.cancel(); invocationTask = nil }
    func shutdown() {
        permissionEffectHandler.cancelAccessibilityReset()
        cancelAllAccessibilityWork()
    }

    func prepareForTermination() async {
        permissionEffectHandler.cancelAccessibilityReset()
        monitoringMode = .stopped
        unreadBadgePresentation = .hidden
        cancelAllAccessibilityWork()
        await controller.flushPendingScanPersistence()
    }

    private func applyPermissionEvent(_ event: PermissionEvent) {
        let wasAuthorized = permissionGranted
        let transition = permissionState.reduce(event)
        permissionState = transition.state
        if permissionGranted { scheduleLiveUpdatesIfNeeded() }
        else {
            unreadBadgePresentation = .hidden
            if wasAuthorized { cancelAllAccessibilityWork() }
        }
        rebuildSnapshot()
        for effect in transition.effects { consume(effect) }
    }

    private func revalidateAccessibilityTrust() -> Bool {
        let trusted = accessibilityTrustProvider()
        if !trusted {
            applyPermissionEvent(.applicationBecameActive(isTrusted: false))
            return false
        }
        guard permissionGranted else {
            applyPermissionEvent(.applicationBecameActive(isTrusted: true))
            return false
        }
        return true
    }

    private func cancelAllAccessibilityWork() {
        liveUpdateCancellation?.cancel()
        liveUpdateCancellation = nil
        liveScanGeneration += 1
        inFlightLiveScanTask?.cancel()
        inFlightLiveScanTask = nil
        manualScanGeneration += 1
        manualScanTask?.cancel()
        manualScanTask = nil
        invocationGeneration += 1
        invocationTask?.cancel()
        invocationTask = nil
        controller.invalidateAccessibilityWork()
        operationState = .idle
    }

    private func consume(_ effect: PermissionEffect) {
        switch effect {
        case .requestSystemPrompt:
            permissionEffectHandler.requestSystemPrompt()
        case .openSettings:
            permissionEffectHandler.openAccessibilitySettings()
        case .resetRequested:
            permissionEffectHandler.requestAccessibilityReset { [weak self] succeeded in
                guard let self, permissionState == .resetting else { return }
                if succeeded {
                    applyPermissionEvent(.resetCompleted)
                } else {
                    permissionState = .repairRequired(reason: pendingRepairReason ?? .operationDenied)
                    statusMessageKey = .permissionResetUnavailable
                }
            }
        case .scan:
            if liveUpdatesActive { startLiveScan(fullDiscovery: true) } else { refresh() }
        case .showExplanation, .setAuthorized, .setDenied, .enterLauncherMode, .offerRepair:
            break
        }
    }

    private func moveSelection(by offset: Int) {
        let visible = selectableRecords
        guard !visible.isEmpty else { selectionID = nil; return }
        let current = selectionID.flatMap { id in visible.firstIndex(where: { $0.id == id }) }
        let next = min(max((current ?? (offset > 0 ? -1 : visible.count)) + offset, 0), visible.count - 1)
        selectionID = visible[next].id
    }

    private var selectableRecords: [MenuBarItemRecord] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? snapshot.all : snapshot.search
    }

    private func observeController() {
        controller.$document.combineLatest(controller.$runtimeSnapshots)
            .sink { [weak self] document, runtimeSnapshots in
                guard let self else { return }
                self.rebuildSnapshot()
                self.rebuildUnreadBadge(document: document, runtimeSnapshots: runtimeSnapshots)
                let enabled = document.preferences.automaticScanning
                guard self.lastAutomaticScanningPreference != enabled else { return }
                self.lastAutomaticScanningPreference = enabled
                self.automaticScanningPreferenceDidChange(enabled)
            }
            .store(in: &subscriptions)
        controller.$isScanning
            .sink { [weak self] scanning in
                guard let self else { return }
                if case .invoking = self.operationState { return }
                self.operationState = scanning ? .scanning : (self.operationState == .loading ? .loading : .idle)
            }
            .store(in: &subscriptions)
        controller.$permissionEvent.compactMap { $0 }
            .sink { [weak self] in self?.applyPermissionEvent($0) }
            .store(in: &subscriptions)
        controller.$errors
            .sink { [weak self] in self?.apply(errors: $0) }
            .store(in: &subscriptions)
    }

    private func apply(errors: CatalogControllerErrors) {
        if errors.saveMessage != nil { statusMessageKey = .saveFailed }
        else if errors.loadMessage != nil { statusMessageKey = .loadFailed }
        else if !errors.scanMessages.isEmpty {
            statusMessageKey = errors.scanMessages.contains(where: { $0.localizedCaseInsensitiveContains("permission") })
                ? .permissionDenied : .scanFailed
        } else if let failure = errors.actionFailure { statusMessageKey = Self.messageKey(for: failure) }
        else { statusMessageKey = nil }
    }

    private func automaticScanningPreferenceDidChange(_ enabled: Bool) {
        guard liveUpdatesActive else { return }
        if enabled {
            guard permissionGranted, revalidateAccessibilityTrust() else { return }
            if inFlightLiveScanTask == nil, !controller.isScanning {
                startLiveScan(fullDiscovery: true)
            }
            scheduleLiveUpdatesIfNeeded()
        } else {
            unreadBadgePresentation = .hidden
            liveUpdateCancellation?.cancel()
            liveUpdateCancellation = nil
            liveScanGeneration += 1
            inFlightLiveScanTask?.cancel()
            inFlightLiveScanTask = nil
            nextFullDiscoveryAt = nil
            controller.invalidateAccessibilityWork()
            Task { [controller] in await controller.flushPendingScanPersistence() }
        }
    }

    private func rebuildUnreadBadge(
        document: CatalogDocument? = nil,
        runtimeSnapshots: [String: AccessibilitySnapshot]? = nil
    ) {
        let document = document ?? controller.document
        guard permissionGranted, document.preferences.automaticScanning else {
            unreadBadgePresentation = .hidden
            return
        }
        unreadBadgePresentation = UnreadBadgeAggregator.presentation(
            records: document.items,
            snapshots: runtimeSnapshots ?? controller.runtimeSnapshots
        )
    }

    private func rebuildSnapshot() {
        let document = controller.document
        var available = document.items.filter { !$0.isIgnored }.sorted(by: Self.itemOrder)
        if let runningUserApplicationBundleIdentifiers {
            let running = runningUserApplicationBundleIdentifiers()
            available = available.filter { record in
                let processBundle = record.identity.bundleIdentifier
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let hostBundle = record.hostBundleIdentifier?
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return running.contains(processBundle) || hostBundle.map(running.contains) == true
            }
        }
        if isLauncherMode {
            available = Self.freshestRecordPerHost(in: available).sorted(by: Self.itemOrder)
        }
        let visible: [MenuBarItemRecord]
        if permissionState == .authorized, controller.hasCompletedScan {
            let runningItemIDs = Set(controller.runtimeSnapshots.keys)
            visible = available.filter { runningItemIDs.contains($0.id) }
        } else {
            visible = available
        }
        let smart = SmartGroupEngine(now: now)
        snapshot = PanelSnapshot(
            favorites: visible.filter(\.isFavorite),
            recent: smart.recentItems(in: visible),
            frequent: smart.frequentItems(in: visible),
            customGroups: document.groups.sorted(by: Self.groupOrder).map { group in
                PanelGroupSnapshot(id: group.id, name: group.name, items: visible.filter { $0.groupIDs.contains(group.id) })
            },
            all: visible,
            search: SearchIndex.items(matching: query, in: visible, groups: document.groups)
        )
        recentIDs = snapshot.recent.map(\.id)
        items = visible.map { record in
            let runtime = controller.runtimeSnapshots[record.id]
            let effectiveLauncher = controller.canLaunchHost(for: record)
                && (isLauncherMode || runtime == nil || record.capability == .launchOnly)
            return HubPanelItem(
                record: record, snapshot: runtime, effectiveLaunchOnly: effectiveLauncher,
                hostIcon: controller.hostIcons[record.id]
            )
        }
        if let selectionID, !selectableRecords.contains(where: { $0.id == selectionID }) { self.selectionID = nil }
    }

    private static func itemOrder(_ lhs: MenuBarItemRecord, _ rhs: MenuBarItemRecord) -> Bool {
        if lhs.manualOrder != rhs.manualOrder { return lhs.manualOrder < rhs.manualOrder }
        let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
    }

    private static func freshestRecordPerHost(in records: [MenuBarItemRecord]) -> [MenuBarItemRecord] {
        Dictionary(grouping: records, by: { record in
            let host = record.hostBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (host.isEmpty ? record.identity.bundleIdentifier : host).lowercased()
        }).values.compactMap { candidates in
            candidates.max { lhs, rhs in
                if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt < rhs.lastSeenAt }
                if lhs.manualOrder != rhs.manualOrder { return lhs.manualOrder > rhs.manualOrder }
                return lhs.id > rhs.id
            }
        }
    }

    private static func groupOrder(_ lhs: GroupRecord, _ rhs: GroupRecord) -> Bool {
        lhs.manualOrder == rhs.manualOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.manualOrder < rhs.manualOrder
    }

    private static func messageKey(for failure: ActionFailure) -> PanelStatusMessageKey {
        switch failure {
        case .launchFailed: return .launchFailed
        case .accessibility(.permissionDenied): return .permissionDenied
        case .accessibility(.elementNotFound), .accessibility(.staleElement), .accessibility(.ambiguousMatch): return .staleItem
        case .accessibility(.actionUnsupported): return .actionUnsupported
        case .accessibility(.targetUnresponsive): return .targetUnresponsive
        case .accessibility(.unknown): return .actionFailed
        }
    }

    private static func localizedMessage(_ key: PanelStatusMessageKey) -> String {
        switch key {
        case .noItems: return L("error.noItems")
        case .loadFailed: return L("error.loadFailed")
        case .saveFailed: return L("error.saveFailed")
        case .scanFailed: return L("error.scanFailed")
        case .permissionDenied: return L("error.permissionDenied")
        case .staleItem: return L("error.staleItem")
        case .actionUnsupported: return L("error.actionUnsupported")
        case .targetUnresponsive: return L("error.targetUnresponsive")
        case .launchFailed: return L("error.launchFailed")
        case .actionFailed: return L("error.actionFailed")
        case .unavailable: return L("error.unavailable")
        case .permissionResetUnavailable: return L("error.permissionResetUnavailable")
        case .settingsUnavailable: return L("error.settingsUnavailable")
        }
    }
}
