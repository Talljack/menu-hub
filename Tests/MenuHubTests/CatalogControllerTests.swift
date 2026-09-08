import XCTest
@testable import MenuHub
@testable import MenuHubCore

@MainActor
final class CatalogControllerTests: XCTestCase {
    func testWorkspaceLaunchKnowledgeRequiresNonemptyBundleAndResolvedApplicationURL() {
        let url = URL(fileURLWithPath: "/Applications/Example.app")
        XCTAssertFalse(WorkspaceLaunchKnowledge.canLaunch(bundleIdentifier: " ", resolve: { _ in url }))
        XCTAssertFalse(WorkspaceLaunchKnowledge.canLaunch(bundleIdentifier: "com.example.missing", resolve: { _ in nil }))
        XCTAssertTrue(WorkspaceLaunchKnowledge.canLaunch(bundleIdentifier: " com.example.known ", resolve: { $0 == "com.example.known" ? url : nil }))
    }

    func testPendingScanReconcilesIntoLatestMutatedDocument() async {
        let initial = testDocument()
        let store = FakeCatalogStore(loadResults: [initial])
        let accessibility = ControlledAccessibility()
        let controller = makeController(store: store, accessibility: accessibility)
        await controller.load()

        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await controller.setAlias("Renamed", itemID: "item")
        await controller.setFavorite(true, itemID: "item")
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await scan.value

        XCTAssertEqual(controller.document.items[0].alias, "Renamed")
        XCTAssertTrue(controller.document.items[0].isFavorite)
        XCTAssertEqual(controller.document.items[0].lastSeenAt, testNow)
    }

    func testPendingLoadCannotOverwriteMutationOrItsPersistedSnapshot() async {
        let store = FakeCatalogStore(controlLoads: true)
        let controller = makeController(store: store, accessibility: ControlledAccessibility())
        await controller.reset(to: testDocument())
        let load = Task { await controller.load() }
        await store.waitForLoadRequests(1)

        await controller.setAlias("newer mutation", itemID: "item")
        await store.completeLoad(0, with: testDocument(alias: "stale load"))
        await load.value

        XCTAssertEqual(controller.document.items[0].alias, "newer mutation")
        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted?.items[0].alias, "newer mutation")
    }

    func testPendingLoadCannotOverwriteCompletedScanOrItsPersistedSnapshot() async {
        let store = FakeCatalogStore(controlLoads: true)
        let accessibility = ControlledAccessibility()
        let controller = makeController(store: store, accessibility: accessibility)
        await controller.reset(to: testDocument())
        let load = Task { await controller.load() }
        await store.waitForLoadRequests(1)
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)

        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(title: "Scanned")], errors: []))
        await scan.value
        await store.completeLoad(0, with: testDocument(alias: "stale load"))
        await load.value

        XCTAssertEqual(controller.document.items[0].identity.originalName, "Scanned")
        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted?.items[0].identity.originalName, "Scanned")
    }

    func testLaunchOnlyPersistedItemInvokesLauncherWithoutRuntimeSnapshot() async {
        var document = testDocument()
        document.items[0].capability = .launchOnly
        let launcher = RecordingLauncher()
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [document]), accessibility: ControlledAccessibility(),
            launcher: launcher, now: { testNow }, canLaunchHost: { $0 == "com.example.host" }
        )
        await controller.load()

        let outcome = await controller.invoke(itemID: "item")

        XCTAssertEqual(outcome, .openedHost)
        let launched = await launcher.bundleIdentifiers
        XCTAssertEqual(launched, ["com.example.host"])
    }

    func testFullPersistedItemFallsBackToKnownLauncherWithoutRuntimeSnapshot() async {
        let launcher = RecordingLauncher()
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [testDocument()]), accessibility: ControlledAccessibility(),
            launcher: launcher, now: { testNow }, canLaunchHost: { $0 == "com.example.host" }
        )
        await controller.load()

        let outcome = await controller.invoke(itemID: "item")

        XCTAssertEqual(outcome, .openedHost)
        XCTAssertEqual(controller.document.items[0].capability, .full)
        let launched = await launcher.bundleIdentifiers
        XCTAssertEqual(launched, ["com.example.host"])
    }

    func testStaleLoadFailureDoesNotPublishAfterMutation() async {
        let store = FakeCatalogStore(controlLoads: true)
        let controller = makeController(store: store, accessibility: ControlledAccessibility())
        await controller.reset(to: testDocument())
        let load = Task { await controller.load() }
        await store.waitForLoadRequests(1)
        await controller.setFavorite(true, itemID: "item")

        await store.completeLoadFailure(0)
        await load.value

        XCTAssertNil(controller.errors.loadMessage)
        XCTAssertTrue(controller.document.items[0].isFavorite)
    }

    func testNewerLoadWinsAndClearsRuntimeSnapshots() async {
        let store = FakeCatalogStore(controlLoads: true)
        let accessibility = ControlledAccessibility()
        let controller = makeController(store: store, accessibility: accessibility)
        let first = Task { await controller.load() }
        await store.waitForLoadRequests(1)
        let second = Task { await controller.load() }
        await store.waitForLoadRequests(2)

        await store.completeLoad(1, with: testDocument(alias: "new"))
        await second.value
        await store.completeLoad(0, with: testDocument(alias: "old"))
        await first.value

        XCTAssertEqual(controller.document.items[0].alias, "new")
        XCTAssertTrue(controller.runtimeSnapshots.isEmpty)
    }

    func testNewLoadInvalidatesPendingScan() async {
        let store = FakeCatalogStore(loadResults: [testDocument(alias: "loaded")])
        let accessibility = ControlledAccessibility()
        let controller = makeController(store: store, accessibility: accessibility)
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await controller.load()
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await scan.value

        XCTAssertEqual(controller.document.items[0].alias, "loaded")
        XCTAssertTrue(controller.runtimeSnapshots.isEmpty)
    }

    func testNewerScanWinsWhenScansCompleteOutOfOrder() async {
        let store = FakeCatalogStore(loadResults: [testDocument()])
        let accessibility = ControlledAccessibility()
        let controller = makeController(store: store, accessibility: accessibility)
        await controller.load()
        let first = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        let second = Task { await controller.scan() }
        await accessibility.waitForScanRequests(2)

        await accessibility.completeScan(1, with: .init(snapshots: [testSnapshot(title: "New")], errors: []))
        await second.value
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(title: "Old")], errors: []))
        await first.value

        XCTAssertEqual(controller.document.items[0].identity.originalName, "New")
        XCTAssertEqual(controller.runtimeSnapshots["item"]?.title, "New")
    }

    func testKnownItemRefreshUpdatesDynamicTitleWithoutStartingFullScan() async {
        let store = FakeCatalogStore()
        let accessibility = ControlledAccessibility()
        let controller = makeController(store: store, accessibility: accessibility)
        let initialScan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(title: "3")], errors: []))
        await initialScan.value
        await accessibility.setRefreshResult(.init(snapshots: [testSnapshot(title: "6")], errors: []))

        await controller.refreshKnownItems()

        XCTAssertEqual(controller.document.items[0].identity.originalName, "6")
        XCTAssertEqual(controller.runtimeSnapshots[controller.document.items[0].id]?.title, "6")
        let scanCount = await accessibility.scanRequestCount
        let refreshCount = await accessibility.refreshRequestCount
        XCTAssertEqual(scanCount, 1)
        XCTAssertEqual(refreshCount, 1)
    }

    func testKnownItemRefreshUpdatesPathStableBadgeWithoutAXIdentifier() async {
        func badge(_ title: String) -> AccessibilitySnapshot {
            AccessibilitySnapshot(
                processIdentifier: 42, processName: "Lark Helper", bundleIdentifier: "com.lark.helper",
                title: title, role: "AXMenuBarItem", subrole: nil, identifier: nil,
                positionX: 10, positionY: 0, width: 20, height: 20,
                actions: ["AXPress"], accessibilityPath: [2, 4]
            )
        }
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher(),
            hostMetadataResolver: ClassifyingHostMetadataResolver(systemBundles: [])
        )
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [badge("3")], errors: []))
        await scan.value
        await accessibility.setRefreshResult(.init(snapshots: [badge("6")], errors: []))

        await controller.refreshKnownItems()

        XCTAssertEqual(controller.document.items.count, 1)
        XCTAssertEqual(controller.document.items[0].hostName, "Lark Helper")
        XCTAssertEqual(controller.document.items[0].identity.originalName, "6")
        XCTAssertEqual(controller.runtimeSnapshots[controller.document.items[0].id]?.title, "6")
    }

    func testKnownItemRefreshUpdatesDisappearingWeChatBadgeAndRemainsInvokable() async throws {
        func weChat(_ title: String?) -> AccessibilitySnapshot {
            AccessibilitySnapshot(
                processIdentifier: 937,
                processName: "WeChat",
                bundleIdentifier: "com.tencent.xinWeChat",
                title: title,
                role: "AXMenuBarItem",
                subrole: nil,
                identifier: nil,
                positionX: 995,
                positionY: 4.5,
                width: 40,
                height: 24,
                actions: ["AXPress"],
                accessibilityPath: [0]
            )
        }
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(
            store: FakeCatalogStore(),
            accessibility: accessibility,
            launcher: FakeLauncher(),
            canLaunchHost: { $0 == "com.tencent.xinWeChat" },
            hostMetadataResolver: ClassifyingHostMetadataResolver(systemBundles: [])
        )
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [weChat("1")], errors: []))
        await scan.value
        let itemID = try XCTUnwrap(controller.document.items.first?.id)
        await accessibility.setRefreshResult(.init(snapshots: [weChat(nil)], errors: []))

        await controller.refreshKnownItems()
        let outcome = await controller.invoke(itemID: itemID)
        let pressRequestCount = await accessibility.pressRequestCount

        XCTAssertEqual(controller.document.items.count, 1)
        XCTAssertEqual(controller.document.items[0].identity.originalName, "WeChat")
        XCTAssertEqual(outcome, .pressed)
        XCTAssertEqual(pressRequestCount, 1)
    }

    func testKnownItemRefreshRejectsReusedPIDAndPathFromAnotherBundle() async {
        func snapshot(process: String, bundle: String, title: String?) -> AccessibilitySnapshot {
            AccessibilitySnapshot(
                processIdentifier: 937,
                processName: process,
                bundleIdentifier: bundle,
                title: title,
                role: "AXMenuBarItem",
                subrole: nil,
                identifier: nil,
                positionX: 995,
                positionY: 4.5,
                width: 40,
                height: 24,
                actions: ["AXPress"],
                accessibilityPath: [0]
            )
        }
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(
            store: FakeCatalogStore(),
            accessibility: accessibility,
            launcher: FakeLauncher(),
            hostMetadataResolver: ClassifyingHostMetadataResolver(systemBundles: [])
        )
        let original = snapshot(process: "WeChat", bundle: "com.tencent.xinWeChat", title: "1")
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [original], errors: []))
        await scan.value
        let reusedPID = snapshot(process: "Other", bundle: "com.example.other", title: nil)
        await accessibility.setRefreshResult(.init(snapshots: [reusedPID], errors: []))

        await controller.refreshKnownItems()

        XCTAssertEqual(controller.document.items.count, 1)
        XCTAssertEqual(controller.document.items[0].identity.bundleIdentifier, "com.tencent.xinWeChat")
        XCTAssertEqual(controller.document.items[0].identity.originalName, "1")
        XCTAssertEqual(controller.runtimeSnapshots.values.first, original)
    }

    func testOlderLightweightRefreshCannotOverwriteNewerFullScan() async {
        let accessibility = ControlledAccessibility(controlRefresh: true)
        let controller = makeController(store: FakeCatalogStore(), accessibility: accessibility)
        let initialScan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(title: "Initial")], errors: []))
        await initialScan.value

        let olderRefresh = Task { await controller.refreshKnownItems() }
        await accessibility.waitForRefreshRequests(1)
        let newerScan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(2)
        await accessibility.completeScan(1, with: .init(snapshots: [testSnapshot(title: "Newest")], errors: []))
        await newerScan.value
        await accessibility.completeRefresh(0, with: .init(snapshots: [testSnapshot(title: "Stale")], errors: []))
        await olderRefresh.value

        XCTAssertEqual(controller.document.items[0].identity.originalName, "Newest")
        XCTAssertEqual(controller.runtimeSnapshots.values.first?.title, "Newest")
    }

    func testScanPersistenceCanBeDebouncedAndFlushed() async {
        let store = FakeCatalogStore()
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(
            store: store, accessibility: accessibility, launcher: FakeLauncher(), now: { testNow },
            scanPersistenceDelay: .seconds(30)
        )
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await scan.value

        let savesBeforeFlush = await store.saveRequestCount
        XCTAssertEqual(savesBeforeFlush, 0)
        await controller.flushPendingScanPersistence()
        let savesAfterFlush = await store.saveRequestCount
        XCTAssertEqual(savesAfterFlush, 1)
    }

    func testResetInvalidatesPendingScan() async {
        let store = FakeCatalogStore()
        let accessibility = ControlledAccessibility()
        let controller = makeController(store: store, accessibility: accessibility)
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await controller.reset(to: testDocument(alias: "reset"))
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(title: "Old")], errors: []))
        await scan.value

        XCTAssertEqual(controller.document.items[0].alias, "reset")
        XCTAssertTrue(controller.runtimeSnapshots.isEmpty)
    }

    func testSerialSavePipelineCannotLetOlderSaveOverwriteNewerSave() async {
        let store = FakeCatalogStore(loadResults: [testDocument()], controlSaves: true)
        let controller = makeController(store: store, accessibility: ControlledAccessibility())
        await controller.load()

        let first = Task { await controller.setAlias("first", itemID: "item") }
        await store.waitForSaveRequests(1)
        let second = Task { await controller.setAlias("second", itemID: "item") }
        let olderSaveWasBypassed = await store.reachesSaveRequestCount(2, within: .milliseconds(50))
        XCTAssertFalse(olderSaveWasBypassed)
        await store.completeSave(0)
        await store.waitForSaveRequests(2)
        await store.completeSave(1)
        await first.value
        await second.value

        let persistedAlias = await store.lastPersisted?.items[0].alias
        XCTAssertEqual(persistedAlias, "second")
    }

    func testActionAndSaveFailuresRemainIndependentlyObservable() async {
        let store = FakeCatalogStore(loadResults: [testDocument()], saveError: FakeFailure.save)
        let accessibility = ControlledAccessibility(pressResult: .failure(.permissionDenied))
        let controller = makeController(store: store, accessibility: accessibility)
        await controller.load()
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await scan.value

        let outcome = await controller.invoke(itemID: "item")

        XCTAssertEqual(outcome, .failed(.accessibility(.permissionDenied)))
        XCTAssertNotNil(controller.errors.saveMessage)
        XCTAssertEqual(controller.errors.actionFailure, .accessibility(.permissionDenied))
        XCTAssertEqual(controller.lastActionOutcome, outcome)
    }

    func testUpdatingPreferencesPersistsCompletedMutation() async {
        let store = FakeCatalogStore(loadResults: [testDocument()])
        let controller = makeController(store: store, accessibility: ControlledAccessibility())
        await controller.load()

        await controller.updatePreferences { preferences in
            preferences.appearance = .dark
            preferences.automaticScanning = false
        }

        XCTAssertEqual(controller.document.preferences.appearance, .dark)
        XCTAssertFalse(controller.document.preferences.automaticScanning)
        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted?.preferences.appearance, .dark)
        XCTAssertFalse(persisted?.preferences.automaticScanning ?? true)
    }

    func testScanKeepsUserApplicationsAndPurgesObservedSystemStatusComponents() async {
        let systemRecord = MenuBarItemRecord(
            id: "old-system",
            identity: .init(
                bundleIdentifier: "com.apple.controlcenter", originalName: "Battery",
                axIdentifier: "battery", path: [0]
            ),
            hostName: "Control Center", capability: .full, lastSeenAt: testNow
        )
        let initial = CatalogDocument(items: [systemRecord], groups: [], preferences: .default)
        let store = FakeCatalogStore(loadResults: [initial])
        let accessibility = ControlledAccessibility()
        let resolver = ClassifyingHostMetadataResolver(systemBundles: ["com.apple.controlcenter"])
        let controller = CatalogController(
            store: store, accessibility: accessibility, launcher: FakeLauncher(), now: { testNow },
            canLaunchHost: { _ in true }, hostMetadataResolver: resolver
        )
        await controller.load()

        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        let system = AccessibilitySnapshot(
            processIdentifier: 10, processName: "Control Center", bundleIdentifier: "com.apple.controlcenter",
            title: "Battery", role: "AXMenuBarItem", subrole: nil, identifier: "battery",
            positionX: 10, positionY: 0, width: 20, height: 20, actions: ["AXPress"], accessibilityPath: [0]
        )
        let user = AccessibilitySnapshot(
            processIdentifier: 20, processName: "Lark Helper", bundleIdentifier: "com.electron.lark.helper",
            title: "6", role: "AXMenuBarItem", subrole: nil, identifier: "lark-status",
            positionX: 30, positionY: 0, width: 20, height: 20, actions: ["AXPress"], accessibilityPath: [0]
        )
        await accessibility.completeScan(0, with: .init(snapshots: [system, user], errors: []))
        await scan.value

        XCTAssertEqual(controller.document.items.map(\.identity.bundleIdentifier), ["com.electron.lark.helper"])
        XCTAssertEqual(controller.runtimeSnapshots.values.map(\.bundleIdentifier), ["com.electron.lark.helper"])
        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted?.items.map(\.identity.bundleIdentifier), ["com.electron.lark.helper"])
    }

    func testProcessSpecificScanIssueIsAQuietPartialWarningWhenUsefulItemsWereFound() async {
        let accessibility = ControlledAccessibility()
        let controller = makeController(
            store: FakeCatalogStore(loadResults: [testDocument()]),
            accessibility: accessibility
        )
        await controller.load()

        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(
            snapshots: [testSnapshot()],
            issues: [AccessibilityScanIssue.processFailure(
                processIdentifier: 99,
                process: "Unrelated Helper",
                error: .targetUnresponsive
            )]
        ))
        await scan.value

        XCTAssertTrue(controller.errors.scanMessages.isEmpty)
        XCTAssertEqual(controller.errors.scanWarnings.count, 1)

        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized)
        XCTAssertNil(model.statusMessageKey)
        XCTAssertEqual(model.items.map(\.id), ["item"])
    }

    func testGlobalScanFailureRemainsActionableInThePanel() async {
        let accessibility = ControlledAccessibility()
        let controller = makeController(
            store: FakeCatalogStore(loadResults: [testDocument()]),
            accessibility: accessibility
        )
        await controller.load()

        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(
            snapshots: [],
            issues: [.targetUnresponsive(process: nil)]
        ))
        await scan.value

        XCTAssertEqual(controller.errors.scanMessages.count, 1)
        XCTAssertTrue(controller.errors.scanWarnings.isEmpty)

        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized)
        XCTAssertEqual(model.statusMessageKey, .scanFailed)
    }

    func testDeleteAndRestoreGroupPreservesMembershipAndOrder() async {
        let first = GroupRecord(name: "Work", manualOrder: 0)
        let second = GroupRecord(name: "Personal", manualOrder: 1)
        var document = testDocument()
        document.groups = [first, second]
        document.items[0].groupIDs = [first.id, second.id]
        let store = FakeCatalogStore(loadResults: [document])
        let controller = makeController(store: store, accessibility: ControlledAccessibility())
        await controller.load()

        let deletion = await controller.deleteGroupForUndo(id: first.id)
        XCTAssertEqual(deletion?.group, first)
        XCTAssertFalse(controller.document.items[0].groupIDs.contains(first.id))

        if let deletion { await controller.restoreDeletedGroup(deletion) }
        XCTAssertEqual(controller.document.groups.sorted { $0.manualOrder < $1.manualOrder }, [first, second])
        XCTAssertTrue(controller.document.items[0].groupIDs.contains(first.id))
        let persisted = await store.lastPersisted
        XCTAssertTrue(persisted?.items[0].groupIDs.contains(first.id) == true)
    }

    private func makeController(store: FakeCatalogStore, accessibility: ControlledAccessibility) -> CatalogController {
        CatalogController(store: store, accessibility: accessibility, launcher: FakeLauncher(), now: { testNow })
    }
}

enum FakeFailure: Error { case save }

actor FakeCatalogStore: CatalogStoring {
    private var loadResults: [CatalogDocument]
    private let controlLoads: Bool
    private let controlSaves: Bool
    private let saveError: Error?
    private var loadContinuations: [Int: CheckedContinuation<CatalogDocument, Error>] = [:]
    private var saveContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var saveRequestCount = 0
    private(set) var lastPersisted: CatalogDocument?
    private var nextLoad = 0

    init(loadResults: [CatalogDocument] = [], controlLoads: Bool = false, controlSaves: Bool = false, saveError: Error? = nil) {
        self.loadResults = loadResults
        self.controlLoads = controlLoads
        self.controlSaves = controlSaves
        self.saveError = saveError
    }

    func load() async throws -> CatalogDocument {
        if !controlLoads { return loadResults.removeFirst() }
        let id = nextLoad
        nextLoad += 1
        return try await withCheckedThrowingContinuation { loadContinuations[id] = $0 }
    }

    func save(_ document: CatalogDocument) async throws {
        let id = saveRequestCount
        saveRequestCount += 1
        if controlSaves { await withCheckedContinuation { saveContinuations[id] = $0 } }
        if let saveError { throw saveError }
        lastPersisted = document
    }

    func completeLoad(_ id: Int, with document: CatalogDocument) { loadContinuations.removeValue(forKey: id)?.resume(returning: document) }
    func completeLoadFailure(_ id: Int) { loadContinuations.removeValue(forKey: id)?.resume(throwing: FakeFailure.save) }
    func completeSave(_ id: Int) { saveContinuations.removeValue(forKey: id)?.resume() }

    func waitForLoadRequests(_ count: Int) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while nextLoad < count, ContinuousClock.now < deadline { await Task.yield() }
        if nextLoad < count { XCTFail("Timed out waiting for \(count) load requests") }
    }

    func waitForSaveRequests(_ count: Int) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while saveRequestCount < count, ContinuousClock.now < deadline { await Task.yield() }
        if saveRequestCount < count { XCTFail("Timed out waiting for \(count) save requests") }
    }

    func reachesSaveRequestCount(_ count: Int, within duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while saveRequestCount < count, ContinuousClock.now < deadline { await Task.yield() }
        return saveRequestCount >= count
    }
}

actor ControlledAccessibility: AccessibilityServing {
    private var scans: [Int: CheckedContinuation<AccessibilityScanResult, Never>] = [:]
    private var scanCount = 0
    private var refreshCount = 0
    private var refreshResult = AccessibilityScanResult(snapshots: [], errors: [])
    private var refreshContinuations: [Int: CheckedContinuation<AccessibilityScanResult, Never>] = [:]
    private let controlRefresh: Bool
    private let pressResult: Result<Void, AccessibilityDomainError>
    private let controlPress: Bool
    private var pressContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var pressRequestIDs: [String] = []

    init(
        pressResult: Result<Void, AccessibilityDomainError> = .success(()),
        controlPress: Bool = false,
        controlRefresh: Bool = false
    ) {
        self.pressResult = pressResult
        self.controlPress = controlPress
        self.controlRefresh = controlRefresh
    }

    func scan() async -> AccessibilityScanResult {
        let id = scanCount
        scanCount += 1
        return await withCheckedContinuation { scans[id] = $0 }
    }

    func refresh(_ snapshots: [AccessibilitySnapshot]) async -> AccessibilityScanResult {
        let id = refreshCount
        refreshCount += 1
        if controlRefresh {
            return await withCheckedContinuation { refreshContinuations[id] = $0 }
        }
        return refreshResult
    }

    func setRefreshResult(_ result: AccessibilityScanResult) { refreshResult = result }

    func press(_ snapshot: AccessibilitySnapshot) async -> Result<Void, AccessibilityDomainError> {
        let id = snapshot.identifier ?? ""
        pressRequestIDs.append(id)
        if controlPress { await withCheckedContinuation { pressContinuations[id] = $0 } }
        return pressResult
    }
    func completeScan(_ id: Int, with result: AccessibilityScanResult) { scans.removeValue(forKey: id)?.resume(returning: result) }
    func completeRefresh(_ id: Int, with result: AccessibilityScanResult) {
        refreshContinuations.removeValue(forKey: id)?.resume(returning: result)
    }
    func waitForScanRequests(_ count: Int) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while scanCount < count, ContinuousClock.now < deadline { await Task.yield() }
        if scanCount < count { XCTFail("Timed out waiting for \(count) scan requests") }
    }
    var scanRequestCount: Int { scanCount }
    var refreshRequestCount: Int { refreshCount }
    func waitForRefreshRequests(_ count: Int) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while refreshCount < count, ContinuousClock.now < deadline { await Task.yield() }
        if refreshCount < count { XCTFail("Timed out waiting for \(count) refresh requests") }
    }
    var pressRequestCount: Int { pressRequestIDs.count }
    func waitForPressRequest() async { await waitForPressRequests(1) }
    func waitForPressRequests(_ count: Int) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while pressRequestIDs.count < count, ContinuousClock.now < deadline { await Task.yield() }
        if pressRequestIDs.count < count { XCTFail("Timed out waiting for \(count) press requests") }
    }
    func completePress(id: String? = nil) {
        let target = id ?? pressRequestIDs.first ?? ""
        pressContinuations.removeValue(forKey: target)?.resume()
    }
}

struct FakeLauncher: ApplicationLaunching { func launch(bundleIdentifier: String) async -> Bool { true } }

@MainActor
private struct ClassifyingHostMetadataResolver: HostMetadataResolving {
    let systemBundles: Set<String>

    func metadata(for snapshot: AccessibilitySnapshot) -> HostApplicationMetadata? {
        let bundleIdentifier = snapshot.bundleIdentifier ?? ""
        return HostApplicationMetadata(
            displayName: snapshot.processName, icon: nil, bundleIdentifier: bundleIdentifier,
            applicationURL: nil, isUserApplication: !systemBundles.contains(bundleIdentifier)
        )
    }
}

actor RecordingLauncher: ApplicationLaunching {
    private(set) var bundleIdentifiers: [String] = []
    func launch(bundleIdentifier: String) async -> Bool { bundleIdentifiers.append(bundleIdentifier); return true }
}

let testNow = Date(timeIntervalSince1970: 20_000)

func testDocument(alias: String? = nil) -> CatalogDocument {
    CatalogDocument(items: [MenuBarItemRecord(
        id: "item",
        identity: .init(bundleIdentifier: "com.example.host", originalName: "Item", axIdentifier: "item", path: [1]),
        hostName: "Host", alias: alias, capability: .full, lastSeenAt: testNow.addingTimeInterval(-100)
    )], groups: [], preferences: .default)
}

func testSnapshot(title: String = "Item", id: String = "item") -> AccessibilitySnapshot {
    let bundleIdentifier = id == "item" ? "com.example.host" : "com.example.\(id)"
    return AccessibilitySnapshot(
        processIdentifier: 42, processName: "Host", bundleIdentifier: bundleIdentifier, title: title,
        role: "AXMenuBarItem", subrole: nil, identifier: id, positionX: 10, positionY: 0,
        width: 20, height: 20, actions: ["AXPress"], accessibilityPath: [id == "item" ? 1 : (id == "a" ? 0 : 1)]
    )
}
