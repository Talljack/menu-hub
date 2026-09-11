import AppKit
import Combine
import Foundation
import MenuHubCore

protocol CatalogStoring: Sendable {
    func load() async throws -> CatalogDocument
    func save(_ document: CatalogDocument) async throws
    func clear() async throws
}

extension CatalogStoring {
    func clear() async throws { try await save(.empty) }
}

extension CatalogStore: CatalogStoring {
    func clear() async throws { try clearAll() }
}

struct CatalogControllerErrors: Equatable {
    var loadMessage: String?
    var saveMessage: String?
    var scanMessages: [String] = []
    var scanWarnings: [String] = []
    var actionFailure: ActionFailure?
}

enum ScanIssuePresentationPolicy {
    static func partition(
        _ issues: [AccessibilityScanIssue]
    ) -> (blocking: [String], warnings: [String]) {
        var blocking: [String] = []
        var warnings: [String] = []
        for issue in issues {
            switch issue {
            case .permissionDenied, .targetUnresponsive(process: nil):
                blocking.append(issue.message)
            case .traversalLimit, .targetUnresponsive(process: .some), .processFailure:
                warnings.append(issue.message)
            }
        }
        return (blocking, warnings)
    }
}

struct DeletedGroupSnapshot: Equatable, Sendable {
    let group: GroupRecord
    let originalIndex: Int
    let memberItemIDs: [String]
}

enum WorkspaceLaunchKnowledge {
    static func canLaunch(bundleIdentifier: String, resolve: (String) -> URL?) -> Bool {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty && resolve(normalized) != nil
    }
}

final class WorkspaceApplicationLauncher: ApplicationLaunching, @unchecked Sendable {
    func launch(bundleIdentifier: String) async -> Bool {
        await MainActor.run {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return false }
            return NSWorkspace.shared.open(url)
        }
    }
}

fileprivate struct CatalogSaveFailure: Error { let message: String }

private actor SerialCatalogSaver {
    private let store: any CatalogStoring
    private var tail: Task<Result<Void, CatalogSaveFailure>, Never>?

    init(store: any CatalogStoring) { self.store = store }

    fileprivate func enqueue(_ document: CatalogDocument) async -> Result<Void, CatalogSaveFailure> {
        let predecessor = tail
        let store = store
        let task = Task<Result<Void, CatalogSaveFailure>, Never> {
            if let predecessor { _ = await predecessor.value }
            do {
                try await store.save(document)
                return .success(())
            } catch {
                return .failure(CatalogSaveFailure(message: String(describing: error)))
            }
        }
        tail = task
        return await task.value
    }

    fileprivate func clear() async -> Result<Void, CatalogSaveFailure> {
        let predecessor = tail
        let store = store
        let task = Task<Result<Void, CatalogSaveFailure>, Never> {
            if let predecessor { _ = await predecessor.value }
            do {
                try await store.clear()
                return .success(())
            } catch {
                return .failure(CatalogSaveFailure(message: String(describing: error)))
            }
        }
        tail = task
        return await task.value
    }
}

@MainActor
final class CatalogController: ObservableObject {
    @Published private(set) var document: CatalogDocument = .empty
    @Published private(set) var runtimeSnapshots: [String: AccessibilitySnapshot] = [:]
    @Published private(set) var hostIcons: [String: NSImage] = [:]
    @Published private(set) var hasCompletedScan = false
    @Published private(set) var errors = CatalogControllerErrors()
    @Published private(set) var isScanning = false
    @Published private(set) var lastActionOutcome: ActionOutcome?
    @Published private(set) var permissionEvent: PermissionEvent?
    @Published private(set) var lastRefreshAt: Date?

    private let store: any CatalogStoring
    private let saver: SerialCatalogSaver
    private let accessibility: any AccessibilityServing
    private let executor: ActionExecutor
    private let now: @Sendable () -> Date
    private let launchKnowledge: ((String) -> Bool)?
    private let hostMetadataResolver: any HostMetadataResolving
    private let scanPersistenceDelay: Duration
    private var epoch = 0
    private var scanGeneration = 0
    private var revision = 0
    private var pendingScanPersistenceTask: Task<Void, Never>?

    init(
        store: any CatalogStoring,
        accessibility: any AccessibilityServing,
        launcher: any ApplicationLaunching,
        now: @escaping @Sendable () -> Date = Date.init,
        canLaunchHost: ((String) -> Bool)? = nil,
        hostMetadataResolver: any HostMetadataResolving = HostApplicationResolver(),
        scanPersistenceDelay: Duration = .zero
    ) {
        self.store = store
        self.saver = SerialCatalogSaver(store: store)
        self.accessibility = accessibility
        self.executor = ActionExecutor(accessibility: accessibility, launcher: launcher)
        self.now = now
        self.launchKnowledge = canLaunchHost
        self.hostMetadataResolver = hostMetadataResolver
        self.scanPersistenceDelay = scanPersistenceDelay
    }

    func load() async {
        epoch += 1
        scanGeneration += 1
        let requestedEpoch = epoch
        let requestedRevision = revision
        isScanning = false
        do {
            let loaded = try await store.load()
            guard requestedEpoch == epoch, requestedRevision == revision, !Task.isCancelled else { return }
            document = loaded
            hasCompletedScan = false
            runtimeSnapshots = [:]
            hostIcons = [:]
            revision += 1
            errors.loadMessage = nil
        } catch {
            guard requestedEpoch == epoch, requestedRevision == revision, !Task.isCancelled else { return }
            errors.loadMessage = String(describing: error)
        }
    }

    func reset(to replacement: CatalogDocument = .empty) async {
        epoch += 1
        scanGeneration += 1
        isScanning = false
        document = replacement
        hasCompletedScan = false
        runtimeSnapshots = [:]
        hostIcons = [:]
        revision += 1
        await persist(revision: revision)
    }

    func clearLocalData() async {
        epoch += 1
        scanGeneration += 1
        isScanning = false
        document = .empty
        hasCompletedScan = false
        runtimeSnapshots = [:]
        hostIcons = [:]
        revision += 1
        let clearRevision = revision
        let result = await saver.clear()
        guard clearRevision == revision else { return }
        switch result {
        case .success: errors.saveMessage = nil
        case .failure(let failure): errors.saveMessage = failure.message
        }
    }

    func scan() async {
        scanGeneration += 1
        let generation = scanGeneration
        let requestedEpoch = epoch
        isScanning = true
        let scanResult = await accessibility.scan()
        guard generation == scanGeneration, requestedEpoch == epoch, !Task.isCancelled else {
            if generation == scanGeneration { isScanning = false }
            return
        }

        let classifiedSnapshots = scanResult.snapshots.map { snapshot in
            (snapshot: snapshot, metadata: hostMetadataResolver.metadata(for: snapshot))
        }
        let userSnapshots = classifiedSnapshots.compactMap { entry in
            entry.metadata?.isUserApplication == false ? nil : entry.snapshot
        }
        let excludedProcessBundles = Set(classifiedSnapshots.compactMap { entry -> String? in
            guard entry.metadata?.isUserApplication == false else { return nil }
            return entry.snapshot.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        if !excludedProcessBundles.isEmpty {
            document.items.removeAll { item in
                excludedProcessBundles.contains(
                    item.identity.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            }
        }

        let bundleIDs = Set(userSnapshots.compactMap { snapshot -> String? in
            guard let raw = snapshot.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            return canLaunch(bundleIdentifier: raw) ? raw : nil
        })
        let reconciliation = CatalogReconciler.reconcile(
            &document,
            snapshots: userSnapshots,
            at: now(),
            canLaunchHost: { bundleIDs.contains($0) }
        )
        hasCompletedScan = true
        runtimeSnapshots = reconciliation.runtimeSnapshots
        var resolvedIcons: [String: NSImage] = [:]
        for (itemID, snapshot) in reconciliation.runtimeSnapshots {
            guard let metadata = hostMetadataResolver.metadata(for: snapshot),
                  let index = document.items.firstIndex(where: { $0.id == itemID }) else { continue }
            document.items[index].hostName = metadata.displayName
            document.items[index].hostBundleIdentifier = metadata.bundleIdentifier
            if document.items[index].capability == .unavailable,
               let outerBundle = metadata.bundleIdentifier,
               canLaunch(bundleIdentifier: outerBundle) {
                document.items[index].capability = .launchOnly
            }
            resolvedIcons[itemID] = metadata.icon
        }
        hostIcons = resolvedIcons
        revision += 1
        let scanRevision = revision
        isScanning = false
        lastRefreshAt = now()
        let presentedIssues = ScanIssuePresentationPolicy.partition(scanResult.issues)
        errors.scanMessages = presentedIssues.blocking
        errors.scanWarnings = presentedIssues.warnings
        if scanResult.issues.contains(.permissionDenied) { permissionEvent = .operationDenied }
        await scheduleScanPersistence(revision: scanRevision)
    }

    func refreshKnownItems() async {
        scanGeneration += 1
        let generation = scanGeneration
        if isScanning { isScanning = false }
        let existing = runtimeSnapshots
        guard !existing.isEmpty else { return }
        let requestedEpoch = epoch
        let result = await accessibility.refresh(Array(existing.values))
        guard generation == scanGeneration, requestedEpoch == epoch, !Task.isCancelled else { return }
        var updated = runtimeSnapshots
        var changed = false
        for snapshot in result.snapshots {
            guard let pair = existing.first(where: {
                $0.value.processIdentifier == snapshot.processIdentifier
                    && $0.value.accessibilityPath == snapshot.accessibilityPath
                    && Self.normalizedBundleIdentifier($0.value.bundleIdentifier)
                        == Self.normalizedBundleIdentifier(snapshot.bundleIdentifier)
                    && !Self.normalizedBundleIdentifier(snapshot.bundleIdentifier).isEmpty
            }) else { continue }
            updated[pair.key] = snapshot
            guard let index = document.items.firstIndex(where: { $0.id == pair.key }) else { continue }
            let oldIdentity = document.items[index].identity
            let oldIdentifier = oldIdentity.axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let newTitle = snapshot.title ?? snapshot.processName
            let isSafeDynamicTransition = DynamicStatusTitle.canTransition(
                from: oldIdentity.originalName,
                to: newTitle,
                knownHostNames: [document.items[index].hostName, snapshot.processName]
            )
            if !oldIdentifier.isEmpty || isSafeDynamicTransition {
                document.items[index].identity.processIdentifier = snapshot.processIdentifier
                document.items[index].identity.bundleIdentifier = snapshot.bundleIdentifier ?? oldIdentity.bundleIdentifier
                document.items[index].identity.originalName = newTitle
                document.items[index].identity.axIdentifier = snapshot.identifier
                document.items[index].identity.path = snapshot.accessibilityPath
                document.items[index].identity.position = if let x = snapshot.positionX, let y = snapshot.positionY {
                    MenuBarItemPosition(x: x, y: y)
                } else { nil }
                document.items[index].lastSeenAt = now()
                changed = true
            }
        }
        runtimeSnapshots = updated
        lastRefreshAt = now()
        let presented = ScanIssuePresentationPolicy.partition(result.issues)
        errors.scanMessages = presented.blocking
        errors.scanWarnings = presented.warnings
        if result.issues.contains(.permissionDenied) { permissionEvent = .operationDenied }
        if changed {
            revision += 1
            await scheduleScanPersistence(revision: revision)
        }
    }

    func applicationSetDidChange() {
        hostMetadataResolver.invalidateAll()
    }

    func flushPendingScanPersistence() async {
        guard pendingScanPersistenceTask != nil else { return }
        pendingScanPersistenceTask?.cancel()
        pendingScanPersistenceTask = nil
        await persist(revision: revision)
    }

    func invalidateAccessibilityWork() {
        scanGeneration += 1
        isScanning = false
    }

    @discardableResult
    func createGroup(name: String) async -> GroupRecord {
        let group = document.createGroup(name: name)
        await mutationDidComplete()
        return group
    }

    func renameGroup(id: UUID, name: String) async { if document.renameGroup(id: id, name: name) { await mutationDidComplete() } }
    func deleteGroup(id: UUID) async { if document.deleteGroup(id: id) { await mutationDidComplete() } }
    @discardableResult
    func deleteGroupForUndo(id: UUID) async -> DeletedGroupSnapshot? {
        guard let originalIndex = document.groups.firstIndex(where: { $0.id == id }) else { return nil }
        let group = document.groups[originalIndex]
        let snapshot = DeletedGroupSnapshot(
            group: group,
            originalIndex: originalIndex,
            memberItemIDs: document.items.filter { $0.groupIDs.contains(id) }.map(\.id)
        )
        guard document.deleteGroup(id: id) else { return nil }
        await mutationDidComplete()
        return snapshot
    }

    func restoreDeletedGroup(_ snapshot: DeletedGroupSnapshot) async {
        guard !document.groups.contains(where: { $0.id == snapshot.group.id }) else { return }
        document.groups.insert(snapshot.group, at: min(snapshot.originalIndex, document.groups.count))
        let members = Set(snapshot.memberItemIDs)
        for index in document.items.indices where members.contains(document.items[index].id) {
            if !document.items[index].groupIDs.contains(snapshot.group.id) {
                document.items[index].groupIDs.append(snapshot.group.id)
            }
        }
        document.reorderGroups(groupIDs: document.groups.map(\.id))
        await mutationDidComplete()
    }

    func updatePreferences(_ mutation: (inout Preferences) -> Void) async {
        let previous = document.preferences
        mutation(&document.preferences)
        guard document.preferences != previous else { return }
        await mutationDidComplete()
    }
    func setAlias(_ alias: String?, itemID: String) async { if document.setAlias(alias, forItemID: itemID) { await mutationDidComplete() } }
    func setFavorite(_ favorite: Bool, itemID: String) async { if document.setFavorite(favorite, forItemID: itemID) { await mutationDidComplete() } }
    func setMembership(_ member: Bool, itemID: String, groupID: UUID) async { if document.setMembership(member, itemID: itemID, groupID: groupID) { await mutationDidComplete() } }
    func setIgnored(_ ignored: Bool, itemID: String) async { if document.setIgnored(ignored, forItemID: itemID) { await mutationDidComplete() } }
    func setUnreadBadgePreference(_ preference: UnreadBadgePreference, itemID: String) async {
        if document.setUnreadBadgePreference(preference, forItemID: itemID) { await mutationDidComplete() }
    }

    func reorderGroups(groupIDs: [UUID]) async { document.reorderGroups(groupIDs: groupIDs); await mutationDidComplete() }
    func reorderItems(itemIDs: [String]) async { document.reorderItems(itemIDs: itemIDs); await mutationDidComplete() }

    @discardableResult
    func invoke(itemID: String, forceLaunchHost: Bool = false) async -> ActionOutcome {
        guard let item = document.items.first(where: { $0.id == itemID }) else { return publish(.unavailable) }
        if forceLaunchHost || runtimeSnapshots[itemID] == nil {
            guard canLaunchHost(for: item) else { return publish(.unavailable) }
            var launcherItem = item
            launcherItem.capability = .launchOnly
            launcherItem.identity.bundleIdentifier = launchBundleIdentifier(for: item)
            let outcome = await executor.execute(launcherItem, snapshot: Self.placeholderSnapshot(for: item))
            guard !Task.isCancelled else { return outcome }
            return await record(outcome, forItemID: itemID)
        }
        let snapshot: AccessibilitySnapshot
        if let current = runtimeSnapshots[itemID] { snapshot = current }
        else { return publish(.unavailable) }

        let outcome = await executor.execute(item, snapshot: snapshot)
        guard !Task.isCancelled else { return outcome }
        return await record(outcome, forItemID: itemID)
    }

    func canLaunchHost(for item: MenuBarItemRecord) -> Bool {
        canLaunch(bundleIdentifier: launchBundleIdentifier(for: item))
    }

    private func launchBundleIdentifier(for item: MenuBarItemRecord) -> String {
        let outer = item.hostBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return outer.isEmpty ? item.identity.bundleIdentifier : outer
    }

    private func canLaunch(bundleIdentifier: String) -> Bool {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return launchKnowledge?(normalized)
            ?? WorkspaceLaunchKnowledge.canLaunch(bundleIdentifier: normalized) {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }
    }

    private static func normalizedBundleIdentifier(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func record(_ outcome: ActionOutcome, forItemID itemID: String) async -> ActionOutcome {
        switch outcome {
        case .pressed, .openedHost:
            let invocationDate = now()
            _ = document.recordSuccessfulInvocation(forItemID: itemID, at: invocationDate, now: invocationDate)
            _ = document.recordError(nil, forItemID: itemID)
            errors.actionFailure = nil
            await mutationDidComplete()
        case .failed(let failure):
            errors.actionFailure = failure
            if case .accessibility(let domainError) = failure {
                _ = document.recordError(domainError, forItemID: itemID)
                if domainError == .permissionDenied { permissionEvent = .operationDenied }
                await mutationDidComplete()
            }
        case .unavailable:
            break
        }
        return publish(outcome)
    }

    private func publish(_ outcome: ActionOutcome) -> ActionOutcome {
        lastActionOutcome = outcome
        return outcome
    }

    private func mutationDidComplete() async {
        pendingScanPersistenceTask?.cancel()
        pendingScanPersistenceTask = nil
        revision += 1
        await persist(revision: revision)
    }

    private func scheduleScanPersistence(revision savedRevision: Int) async {
        pendingScanPersistenceTask?.cancel()
        if scanPersistenceDelay == .zero {
            pendingScanPersistenceTask = nil
            await persist(revision: savedRevision)
            return
        }
        pendingScanPersistenceTask = Task { [weak self] in
            do { try await Task.sleep(for: self?.scanPersistenceDelay ?? .zero) }
            catch { return }
            guard let self, savedRevision == revision else { return }
            pendingScanPersistenceTask = nil
            await persist(revision: savedRevision)
        }
    }

    private func persist(revision savedRevision: Int) async {
        let result = await saver.enqueue(document)
        guard savedRevision == revision else { return }
        switch result {
        case .success: errors.saveMessage = nil
        case .failure(let failure): errors.saveMessage = failure.message
        }
    }

    private static func placeholderSnapshot(for item: MenuBarItemRecord) -> AccessibilitySnapshot {
        AccessibilitySnapshot(
            processIdentifier: item.identity.processIdentifier ?? 0, processName: item.hostName,
            bundleIdentifier: item.identity.bundleIdentifier, title: item.identity.originalName,
            role: nil, subrole: nil, identifier: item.identity.axIdentifier,
            positionX: item.identity.position?.x, positionY: item.identity.position?.y,
            width: nil, height: nil, actions: [], accessibilityPath: item.identity.path
        )
    }
}
