import XCTest
@testable import MenuHub
@testable import MenuHubCore

@MainActor
final class HubPanelModelTests: XCTestCase {
    func testPanelSnapshotProjectsEverySectionAndSearch() async {
        let group = GroupRecord(name: "Work")
        let document = panelDocument(group: group)
        let store = FakeCatalogStore(loadResults: [document])
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(store: store, accessibility: accessibility, launcher: FakeLauncher(), now: { testNow })
        await controller.load()
        let model = HubPanelModel(controller: controller, now: { testNow }, initialPermissionState: .authorized)

        XCTAssertEqual(model.snapshot.favorites.map(\.id), ["favorite"])
        XCTAssertEqual(model.snapshot.recent.map(\.id), ["recent", "frequent"])
        XCTAssertEqual(model.snapshot.frequent.map(\.id), ["frequent"])
        XCTAssertEqual(model.snapshot.customGroups.first?.items.map(\.id), ["recent"])
        XCTAssertEqual(model.snapshot.all.map(\.id), ["favorite", "recent", "frequent"])

        model.query = "needle"
        XCTAssertEqual(model.snapshot.search.map(\.id), ["recent"])
        model.selectNext()
        XCTAssertEqual(model.selectionID, "recent")
        model.clearSearch()
        XCTAssertNil(model.selectionID)
        XCTAssertEqual(model.query, "")
    }

    func testLegacyProjectionIncludesPersistedLauncherAndFailsClosedForPressWithoutSnapshot() async {
        var launcher = panelItem(id: "launcher", name: "Launcher", order: 0)
        launcher.capability = .launchOnly
        let pressOnly = panelItem(id: "press", name: "Press", order: 1)
        let document = CatalogDocument(items: [launcher, pressOnly], groups: [], preferences: .default)
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [document]), accessibility: ControlledAccessibility(),
            launcher: FakeLauncher(), now: { testNow }, canLaunchHost: { $0 == "com.example.launcher" }
        )
        await controller.load()

        let model = HubPanelModel(controller: controller, now: { testNow }, initialPermissionState: .denied)

        XCTAssertEqual(model.items.map(\.id), ["launcher", "press"])
        XCTAssertTrue(model.items[0].canInvoke)
        XCTAssertFalse(model.items[1].canInvoke)
        XCTAssertTrue(model.isLauncherMode)
    }

    func testAuthorizedPanelAfterScanOnlyShowsCurrentlyRunningItems() async {
        let document = twoItemDocument()
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [document]), accessibility: accessibility,
            launcher: FakeLauncher(), now: { testNow }, canLaunchHost: { _ in true },
            hostMetadataResolver: FakeHostMetadataResolver(name: "User App")
        )
        await controller.load()
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(id: "a")], errors: []))
        await scan.value

        let model = HubPanelModel(controller: controller, now: { testNow }, initialPermissionState: .authorized)

        XCTAssertEqual(model.items.map(\.id), ["a"])
        XCTAssertEqual(model.snapshot.all.map(\.id), ["a"])
    }

    func testDeniedPanelCanStillLimitCatalogToCurrentlyRunningUserApplications() async {
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [twoItemDocument()]),
            accessibility: ControlledAccessibility(), launcher: FakeLauncher(),
            canLaunchHost: { _ in true }
        )
        await controller.load()

        let model = HubPanelModel(
            controller: controller, initialPermissionState: .denied,
            runningUserApplicationBundleIdentifiers: { ["com.example.a"] }
        )

        XCTAssertEqual(model.items.map(\.id), ["a"])
        XCTAssertEqual(model.snapshot.all.map(\.id), ["a"])
    }

    func testDeniedPanelShowsOneFreshestRecordPerRunningApplication() async {
        var older = panelItem(id: "older", name: "3", order: 0)
        older.identity.bundleIdentifier = "com.example.helper"
        older.hostBundleIdentifier = "com.example.app"
        older.lastSeenAt = testNow.addingTimeInterval(-60)
        var current = panelItem(id: "current", name: "6", order: 1)
        current.identity.bundleIdentifier = "com.example.helper"
        current.hostBundleIdentifier = "com.example.app"
        current.lastSeenAt = testNow
        let document = CatalogDocument(items: [older, current], groups: [], preferences: .default)
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [document]), accessibility: ControlledAccessibility(),
            launcher: FakeLauncher(), canLaunchHost: { _ in true }
        )
        await controller.load()

        let model = HubPanelModel(
            controller: controller, initialPermissionState: .denied,
            runningUserApplicationBundleIdentifiers: { ["com.example.app", "com.example.helper"] }
        )

        XCTAssertEqual(model.items.map(\.id), ["current"])
        XCTAssertEqual(model.items.first?.primaryTitle, "Host — 6")
    }

    func testDeniedFullRecordUsesEffectiveLauncherWhenKnownAndDisablesUnknownBundle() async {
        let knownLauncher = RecordingLauncher()
        let knownController = CatalogController(
            store: FakeCatalogStore(loadResults: [testDocument()]), accessibility: ControlledAccessibility(),
            launcher: knownLauncher, now: { testNow }, canLaunchHost: { $0 == "com.example.host" }
        )
        await knownController.load()
        let knownModel = HubPanelModel(controller: knownController, initialPermissionState: .denied)

        XCTAssertTrue(knownModel.items[0].canInvoke)
        XCTAssertTrue(knownModel.items[0].isLaunchOnly)
        let outcome = await knownController.invoke(itemID: "item")
        XCTAssertEqual(outcome, .openedHost)
        XCTAssertEqual(knownController.document.items[0].capability, .full)

        let unknownController = CatalogController(
            store: FakeCatalogStore(loadResults: [testDocument()]), accessibility: ControlledAccessibility(),
            launcher: FakeLauncher(), canLaunchHost: { _ in false }
        )
        await unknownController.load()
        let unknownModel = HubPanelModel(controller: unknownController, initialPermissionState: .denied)
        XCTAssertFalse(unknownModel.items[0].canInvoke)
    }

    func testPublishedOperationAndPermissionStatesFollowControllerEvents() async {
        let store = FakeCatalogStore(loadResults: [testDocument()])
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(store: store, accessibility: accessibility, launcher: FakeLauncher(), now: { testNow })
        await controller.load()
        let model = HubPanelModel(controller: controller, now: { testNow }, initialPermissionState: .authorized)

        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        XCTAssertEqual(model.operationState, .scanning)
        await accessibility.completeScan(0, with: .init(snapshots: [], issues: [.permissionDenied]))
        await scan.value

        XCTAssertEqual(model.operationState, .idle)
        XCTAssertEqual(model.permissionState, .repairRequired(reason: .operationDenied))
        XCTAssertEqual(model.statusMessageKey, .permissionDenied)
        XCTAssertTrue(model.statusMessage?.isEmpty == false)
    }

    func testOperationStateTracksInvocationUntilActionCompletes() async {
        let store = FakeCatalogStore(loadResults: [testDocument()])
        let accessibility = ControlledAccessibility(controlPress: true)
        let controller = CatalogController(store: store, accessibility: accessibility, launcher: FakeLauncher(), now: { testNow })
        await controller.load()
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await scan.value
        let model = HubPanelModel(controller: controller, now: { testNow }, initialPermissionState: .authorized)

        model.invoke(model.items[0])
        await accessibility.waitForPressRequest()
        XCTAssertEqual(model.operationState, .invoking(itemID: "item"))
        await accessibility.completePress()
        let becameIdle = await waitUntil { model.operationState == .idle }
        XCTAssertTrue(becameIdle)

        XCTAssertNil(model.statusMessageKey)
    }

    func testNewInvocationCancelsOldPresentationAndOnlyNewestCompletionPublishes() async {
        let document = twoItemDocument()
        let store = FakeCatalogStore(loadResults: [document])
        let accessibility = ControlledAccessibility(controlPress: true)
        let controller = CatalogController(store: store, accessibility: accessibility, launcher: FakeLauncher(), now: { testNow })
        await controller.load()
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(id: "a"), testSnapshot(id: "b")], errors: []))
        await scan.value
        let model = HubPanelModel(controller: controller, now: { testNow }, initialPermissionState: .authorized)

        model.invoke(model.items.first { $0.id == "a" }!)
        await accessibility.waitForPressRequests(1)
        model.invoke(model.items.first { $0.id == "b" }!)
        await accessibility.waitForPressRequests(2)
        await accessibility.completePress(id: "a")
        await Task.yield()
        XCTAssertEqual(model.operationState, .invoking(itemID: "b"))
        await accessibility.completePress(id: "b")
        let becameIdle = await waitUntil { model.operationState == .idle }
        XCTAssertTrue(becameIdle)

        XCTAssertEqual(controller.lastActionOutcome, .pressed)
        XCTAssertNil(controller.errors.actionFailure)
        XCTAssertEqual(controller.document.items.first { $0.id == "a" }?.successfulInvocations.count, 0)
        XCTAssertEqual(controller.document.items.first { $0.id == "b" }?.successfulInvocations.count, 1)
    }

    func testPermissionEffectsAreConsumedOnlyAfterExplicitStateMachineEventsAndInOrder() async {
        let effects = FakePermissionEffectHandler(resetAvailable: false)
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher(), now: { testNow })
        let model = HubPanelModel(
            controller: controller, now: { testNow }, initialPermissionState: .unknown,
            permissionEffectHandler: effects
        )

        model.requestPermission()
        XCTAssertEqual(model.permissionState, .explanation(.systemPrompt))
        XCTAssertEqual(effects.calls, [])
        model.acceptPermissionExplanation()
        XCTAssertEqual(effects.calls, [.systemPrompt])
        model.applicationBecameActive(isTrusted: true)
        await accessibility.waitForScanRequests(1)
        XCTAssertEqual(model.permissionState, .authorized)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))

        model.applicationBecameActive(isTrusted: false)
        model.confirmPermissionRepair()
        XCTAssertEqual(effects.calls, [.systemPrompt, .reset])
        XCTAssertEqual(model.statusMessageKey, .permissionResetUnavailable)
        XCTAssertEqual(model.permissionState, .repairRequired(reason: .trustRevoked))
        model.permissionResetCompleted()
        XCTAssertEqual(effects.calls, [.systemPrompt, .reset])
    }

    func testSettingsExplanationAndSkipConsumeTheExpectedEffects() {
        let effects = FakePermissionEffectHandler()
        let controller = CatalogController(store: FakeCatalogStore(), accessibility: ControlledAccessibility(), launcher: FakeLauncher())
        let model = HubPanelModel(controller: controller, initialPermissionState: .denied, permissionEffectHandler: effects)

        model.requestPermission()
        XCTAssertEqual(effects.calls, [])
        model.acceptPermissionExplanation()
        XCTAssertEqual(effects.calls, [.settings])

        let skipped = HubPanelModel(controller: controller, initialPermissionState: .unknown, permissionEffectHandler: effects)
        skipped.requestPermission()
        skipped.skipPermissionExplanation()
        XCTAssertEqual(skipped.permissionState, .denied)
        XCTAssertEqual(effects.calls, [.settings])
    }

    func testLiveUpdatesScanImmediatelyThenUseLightweightRefreshAndStopCleanly() async {
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher(), now: { testNow }
        )
        let model = HubPanelModel(
            controller: controller, now: { testNow }, initialPermissionState: .authorized,
            liveUpdateScheduler: scheduler
        )

        model.startLiveUpdates()
        await accessibility.waitForScanRequests(1)
        scheduler.fire()
        await Task.yield()
        XCTAssertEqual(scheduler.scheduledCount, 1)

        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        let becameIdle = await waitUntil { !controller.isScanning }
        XCTAssertTrue(becameIdle)
        let deadline = ContinuousClock.now + .seconds(1)
        var refreshCount = await accessibility.refreshRequestCount
        while refreshCount < 1, ContinuousClock.now < deadline {
            scheduler.fire()
            await Task.yield()
            refreshCount = await accessibility.refreshRequestCount
        }
        XCTAssertEqual(refreshCount, 1)
        let fullScanCount = await accessibility.scanRequestCount
        XCTAssertEqual(fullScanCount, 1)

        model.stopLiveUpdates()
        XCTAssertTrue(scheduler.isCancelled)
        scheduler.fire()
        XCTAssertTrue(scheduler.isCancelled)
    }

    func testBackgroundMonitoringUsesFiveSecondKnownRefreshAndPublishesUnreadTotal() async {
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher(),
            hostMetadataResolver: FakeHostMetadataResolver(
                name: "Feishu", bundleIdentifier: "com.larksuite.feishu"
            )
        )
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .authorized, liveUpdateScheduler: scheduler
        )
        let initial = unreadSnapshot(title: "2")

        model.startBackgroundUpdates()
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [initial], errors: []))
        let initialBadgePublished = await waitUntil { model.unreadBadgePresentation == .count(2) }
        XCTAssertTrue(initialBadgePublished)
        XCTAssertEqual(scheduler.intervals, [5])

        await accessibility.setRefreshResult(.init(snapshots: [unreadSnapshot(title: "6")], errors: []))
        let deadline = ContinuousClock.now + .seconds(1)
        var refreshCount = await accessibility.refreshRequestCount
        while refreshCount < 1, ContinuousClock.now < deadline {
            scheduler.fire()
            await Task.yield()
            refreshCount = await accessibility.refreshRequestCount
        }
        XCTAssertEqual(refreshCount, 1)
        let refreshedBadgePublished = await waitUntil { model.unreadBadgePresentation == .count(6) }
        XCTAssertTrue(refreshedBadgePublished)
        let scanCount = await accessibility.scanRequestCount
        XCTAssertEqual(scanCount, 1)
    }

    func testPanelVisibilityChangesMonitoringCadenceWithoutExtraDiscovery() async {
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher()
        )
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .authorized, liveUpdateScheduler: scheduler
        )

        model.startBackgroundUpdates()
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [], errors: []))
        _ = await waitUntil { !controller.isScanning }
        model.panelDidAppear()
        model.panelDidDisappear()

        XCTAssertEqual(scheduler.intervals, [5, 1, 5])
        let scanCount = await accessibility.scanRequestCount
        XCTAssertEqual(scanCount, 1)
    }

    func testDisablingAutomaticScanningClearsUnreadBadgeAndStopsMonitoring() async {
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher(),
            hostMetadataResolver: FakeHostMetadataResolver(
                name: "Feishu", bundleIdentifier: "com.larksuite.feishu"
            )
        )
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .authorized, liveUpdateScheduler: scheduler
        )

        model.startBackgroundUpdates()
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [unreadSnapshot(title: "4")], errors: []))
        let badgePublished = await waitUntil { model.unreadBadgePresentation == .count(4) }
        XCTAssertTrue(badgePublished)
        await controller.updatePreferences { $0.automaticScanning = false }

        XCTAssertEqual(model.unreadBadgePresentation, .hidden)
        XCTAssertTrue(scheduler.isCancelled)
    }

    func testAutomaticScanningPreferenceAppliesWhilePanelIsAlreadyOpen() async {
        var document = testDocument()
        document.preferences.automaticScanning = false
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher()
        )
        await controller.reset(to: document)
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .authorized, liveUpdateScheduler: scheduler
        )

        model.startLiveUpdates()
        XCTAssertEqual(scheduler.scheduledCount, 0)
        await controller.updatePreferences { $0.automaticScanning = true }
        await accessibility.waitForScanRequests(1)
        XCTAssertEqual(scheduler.scheduledCount, 1)

        await controller.updatePreferences { $0.automaticScanning = false }
        XCTAssertTrue(scheduler.isCancelled)
        await accessibility.completeScan(0, with: .init(snapshots: [], errors: []))
    }

    func testFullDiscoveryUsesWallClockDeadlineInsteadOfSuccessfulTickCount() async {
        let clock = LockedPanelClock(testNow)
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher(), now: { clock.value }
        )
        let model = HubPanelModel(
            controller: controller, now: { clock.value }, initialPermissionState: .authorized,
            liveUpdateScheduler: scheduler
        )

        model.startLiveUpdates()
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        let initialScanFinished = await waitUntil { !controller.isScanning }
        XCTAssertTrue(initialScanFinished)

        clock.advance(by: 21)
        let deadline = ContinuousClock.now + .seconds(1)
        var scanCount = await accessibility.scanRequestCount
        while scanCount < 2, ContinuousClock.now < deadline {
            scheduler.fire()
            await Task.yield()
            scanCount = await accessibility.scanRequestCount
        }
        let refreshCount = await accessibility.refreshRequestCount
        XCTAssertEqual(scanCount, 2)
        XCTAssertEqual(refreshCount, 0)
        await accessibility.completeScan(1, with: .init(snapshots: [testSnapshot()], errors: []))
    }

    func testTerminationPreparationFlushesDebouncedScanPersistence() async {
        let store = FakeCatalogStore()
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(
            store: store, accessibility: accessibility, launcher: FakeLauncher(),
            scanPersistenceDelay: .seconds(30)
        )
        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized)
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await scan.value

        await model.prepareForTermination()

        let saveCount = await store.saveRequestCount
        XCTAssertEqual(saveCount, 1)
    }

    func testPanelContentStateDistinguishesLoadingScanningAndCompletedEmpty() {
        XCTAssertEqual(PanelContentState.resolve(operation: .loading, hasCompletedScan: false, itemCount: 0), .loading)
        XCTAssertEqual(PanelContentState.resolve(operation: .scanning, hasCompletedScan: false, itemCount: 0), .scanning)
        XCTAssertEqual(PanelContentState.resolve(operation: .idle, hasCompletedScan: true, itemCount: 0), .empty)
        XCTAssertEqual(PanelContentState.resolve(operation: .idle, hasCompletedScan: true, itemCount: 1), .content)
    }

    func testDeniedPanelDoesNotScheduleAccessibilityPolling() {
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(store: FakeCatalogStore(), accessibility: ControlledAccessibility(), launcher: FakeLauncher())
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .denied, liveUpdateScheduler: scheduler,
            accessibilityTrustProvider: { false }
        )

        model.startLiveUpdates()

        XCTAssertEqual(scheduler.scheduledCount, 0)
    }

    func testScanReplacesHelperHostNameWithResolvedOuterApplicationName() async {
        let accessibility = ControlledAccessibility()
        let resolver = FakeHostMetadataResolver(name: "飞书")
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher(), now: { testNow },
            hostMetadataResolver: resolver
        )
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(title: "6")], errors: []))
        await scan.value

        XCTAssertEqual(controller.document.items[0].hostName, "飞书")
        XCTAssertEqual(controller.document.items[0].identity.bundleIdentifier, "com.example.host")
        XCTAssertEqual(controller.document.items[0].identity.originalName, "6")
    }

    func testOpenSettingsUsesCallbackAndFallbackPublishesFeedback() async {
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [testDocument()]), accessibility: ControlledAccessibility(), launcher: FakeLauncher()
        )
        await controller.load()
        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized)
        var opened = false
        model.onOpenSettings = { opened = true }

        model.openSettings()

        XCTAssertTrue(opened)
        model.onOpenSettings = nil
        model.openSettings(sendStandardAction: { false })
        XCTAssertEqual(model.statusMessageKey, .settingsUnavailable)
    }

    func testFailedInvocationMarksOnlyCurrentRowAndNewAttemptClearsIt() async {
        let accessibility = ControlledAccessibility(pressResult: .failure(.targetUnresponsive))
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [testDocument()]), accessibility: accessibility,
            launcher: FakeLauncher(), now: { testNow }
        )
        await controller.load()
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await scan.value
        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized)

        model.invoke(model.items[0])
        let failed = await waitUntil { model.lastFailedItemID == "item" }

        XCTAssertTrue(failed)
        XCTAssertEqual(model.statusMessageKey, .targetUnresponsive)
        model.invoke(model.items[0])
        XCTAssertNil(model.lastFailedItemID)
    }

    func testFailedInvocationFeedbackClearsAfterConfiguredDuration() async {
        let accessibility = ControlledAccessibility(pressResult: .failure(.targetUnresponsive))
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [testDocument()]), accessibility: accessibility,
            launcher: FakeLauncher(), now: { testNow }
        )
        await controller.load()
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await scan.value
        let model = HubPanelModel(
            controller: controller,
            initialPermissionState: .authorized,
            failureFeedbackDuration: .milliseconds(10)
        )

        model.invoke(model.items[0])
        let failurePublished = await waitUntil { model.lastFailedItemID == "item" }
        XCTAssertTrue(failurePublished)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertNil(model.lastFailedItemID)
        XCTAssertNil(model.statusMessageKey)
        XCTAssertNil(controller.errors.actionFailure)
    }

    func testSuccessfulInvocationShowsRowFeedbackWhenClosePreferenceIsOff() async {
        var document = testDocument()
        document.preferences.closeAfterSuccessfulTrigger = false
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [document]), accessibility: accessibility,
            launcher: FakeLauncher(), now: { testNow }
        )
        await controller.load()
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await scan.value
        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized)
        var closed = false
        model.onSuccessfulInvocation = { closed = true }

        model.invoke(model.items[0])
        let succeeded = await waitUntil { model.lastSucceededItemID == "item" }

        XCTAssertTrue(succeeded)
        XCTAssertFalse(closed)
    }

    func testItemActionMutationsPersistAliasGroupMembershipAndIgnore() async {
        let group = GroupRecord(name: "Work")
        let store = FakeCatalogStore(loadResults: [CatalogDocument(items: testDocument().items, groups: [group], preferences: .default)])
        let controller = CatalogController(store: store, accessibility: ControlledAccessibility(), launcher: FakeLauncher())
        await controller.load()
        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized)
        let item = model.items[0]

        await model.setAlias("  New Alias  ", for: item)
        await model.setMembership(true, groupID: group.id, for: item)
        await model.setIgnored(true, for: item)

        XCTAssertEqual(controller.document.items[0].alias, "New Alias")
        XCTAssertEqual(controller.document.items[0].groupIDs, [group.id])
        XCTAssertTrue(controller.document.items[0].isIgnored)
        XCTAssertTrue(model.items.isEmpty)
        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted?.items[0].alias, "New Alias")
    }

    func testOuterHostBundleIsUsedForLaunchWithoutChangingAXIdentity() async {
        let accessibility = ControlledAccessibility()
        let launcher = RecordingLauncher()
        let resolver = FakeHostMetadataResolver(name: "飞书", bundleIdentifier: "com.electron.lark")
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: launcher,
            canLaunchHost: { $0 == "com.electron.lark" }, hostMetadataResolver: resolver
        )
        let scan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        let helper = AccessibilitySnapshot(
            processIdentifier: 42, processName: "Lark Helper", bundleIdentifier: "com.lark.helper", title: "6",
            role: "AXMenuBarItem", subrole: nil, identifier: nil, positionX: 0, positionY: 0,
            width: 20, height: 20, actions: ["AXPress"], accessibilityPath: [2, 4]
        )
        await accessibility.completeScan(0, with: .init(snapshots: [helper], errors: []))
        await scan.value

        XCTAssertEqual(controller.document.items[0].hostName, "飞书")
        XCTAssertEqual(controller.document.items[0].hostBundleIdentifier, "com.electron.lark")
        XCTAssertEqual(controller.document.items[0].identity.bundleIdentifier, "com.lark.helper")
        XCTAssertEqual(controller.document.items[0].capability, .full)
        _ = await controller.invoke(itemID: controller.document.items[0].id, forceLaunchHost: true)
        let launched = await launcher.bundleIdentifiers
        XCTAssertEqual(launched, ["com.electron.lark"])
    }

    func testStoppingLiveUpdatesCancelsPendingScanWithoutPublishingOrSaving() async {
        let initial = testDocument(alias: "before")
        let store = FakeCatalogStore(loadResults: [initial])
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(store: store, accessibility: accessibility, launcher: FakeLauncher())
        await controller.load()
        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized, liveUpdateScheduler: scheduler)

        model.startLiveUpdates()
        await accessibility.waitForScanRequests(1)
        model.stopLiveUpdates()
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(title: "changed")], errors: []))
        _ = await waitUntil { !controller.isScanning }

        XCTAssertEqual(controller.document, initial)
        let persisted = await store.lastPersisted
        XCTAssertNil(persisted)
    }

    func testRapidLiveUpdateReopenStartsOneReplacementScan() async {
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher())
        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized, liveUpdateScheduler: scheduler)

        model.startLiveUpdates()
        await accessibility.waitForScanRequests(1)
        model.stopLiveUpdates()
        model.startLiveUpdates()
        await accessibility.waitForScanRequests(2)
        await accessibility.completeScan(0, with: .init(snapshots: [], errors: []))
        await accessibility.completeScan(1, with: .init(snapshots: [], errors: []))
        _ = await waitUntil { !controller.isScanning }

        XCTAssertEqual(scheduler.scheduledCount, 2)
    }

    func testLiveTickDoesNotOverlapPendingManualScan() async {
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher())
        let model = HubPanelModel(controller: controller, initialPermissionState: .authorized, liveUpdateScheduler: scheduler)
        model.startLiveUpdates()
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [], errors: []))
        let initialFinished = await waitUntil { !controller.isScanning }
        XCTAssertTrue(initialFinished)

        model.refresh()
        await accessibility.waitForScanRequests(2)
        scheduler.fire()
        await accessibility.completeScan(1, with: .init(snapshots: [], errors: []))

        let manualFinished = await waitUntil { !controller.isScanning }
        XCTAssertTrue(manualFinished)
    }

    func testManualRefreshRechecksTrustAndDoesNotStartAXScanAfterRevocation() async {
        let trust = PanelTrustValue(false)
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher())
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .authorized,
            accessibilityTrustProvider: { trust.value }
        )

        model.refresh()
        await Task.yield()

        XCTAssertEqual(model.permissionState, .repairRequired(reason: .trustRevoked))
        let scanCount = await accessibility.scanRequestCount
        XCTAssertEqual(scanCount, 0)
    }

    func testRevocationCancelsPendingManualScanWithoutPublishingOrSaving() async {
        let initial = testDocument(alias: "before")
        let store = FakeCatalogStore(loadResults: [initial])
        let accessibility = ControlledAccessibility()
        let controller = CatalogController(store: store, accessibility: accessibility, launcher: FakeLauncher())
        await controller.load()
        let trust = PanelTrustValue(true)
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .authorized,
            accessibilityTrustProvider: { trust.value }
        )

        model.refresh()
        await accessibility.waitForScanRequests(1)
        trust.value = false
        model.applicationBecameActive(isTrusted: false)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot(title: "changed")], errors: []))
        await Task.yield()

        XCTAssertEqual(controller.document, initial)
        let persisted = await store.lastPersisted
        XCTAssertNil(persisted)
        XCTAssertEqual(model.permissionState, .repairRequired(reason: .trustRevoked))
    }

    func testRevocationCancelsPendingAXPressAndPreventsSuccessPersistence() async {
        let initial = testDocument()
        let store = FakeCatalogStore(loadResults: [initial])
        let accessibility = ControlledAccessibility(controlPress: true)
        let controller = CatalogController(store: store, accessibility: accessibility, launcher: FakeLauncher())
        await controller.load()
        let setupScan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await setupScan.value
        let savesBeforePress = await store.saveRequestCount
        let trust = PanelTrustValue(true)
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .authorized,
            accessibilityTrustProvider: { trust.value }
        )

        model.invoke(model.items[0])
        await accessibility.waitForPressRequest()
        trust.value = false
        model.applicationBecameActive(isTrusted: false)
        await accessibility.completePress()
        await Task.yield()

        XCTAssertEqual(controller.document.items[0].successfulInvocations, [])
        let savesAfterPress = await store.saveRequestCount
        XCTAssertEqual(savesAfterPress, savesBeforePress)
        XCTAssertEqual(model.permissionState, .repairRequired(reason: .trustRevoked))
    }

    func testLiveTickRechecksTrustAndCancelsSchedulerBeforeAnotherScan() async {
        let trust = PanelTrustValue(true)
        let accessibility = ControlledAccessibility()
        let scheduler = ManualPanelLiveUpdateScheduler()
        let controller = CatalogController(store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher())
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .authorized,
            liveUpdateScheduler: scheduler, accessibilityTrustProvider: { trust.value }
        )
        model.startLiveUpdates()
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [], errors: []))
        _ = await waitUntil { !controller.isScanning }

        trust.value = false
        let revoked = await waitUntil {
            scheduler.fire()
            return model.permissionState != .authorized
        }

        let scanCount = await accessibility.scanRequestCount
        XCTAssertTrue(revoked)
        XCTAssertEqual(scanCount, 1)
        XCTAssertTrue(scheduler.isCancelled)
        XCTAssertEqual(model.permissionState, .repairRequired(reason: .trustRevoked))
    }

    func testRevokedPressFallsBackToKnownHostWithoutCallingAX() async {
        let accessibility = ControlledAccessibility()
        let launcher = RecordingLauncher()
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [testDocument()]), accessibility: accessibility,
            launcher: launcher, canLaunchHost: { $0 == "com.example.host" }
        )
        await controller.load()
        let setupScan = Task { await controller.scan() }
        await accessibility.waitForScanRequests(1)
        await accessibility.completeScan(0, with: .init(snapshots: [testSnapshot()], errors: []))
        await setupScan.value
        let trust = PanelTrustValue(false)
        let model = HubPanelModel(
            controller: controller, initialPermissionState: .authorized,
            accessibilityTrustProvider: { trust.value }
        )

        model.invoke(model.items[0])
        let opened = await waitUntil { model.operationState == .idle }

        XCTAssertTrue(opened)
        let pressCount = await accessibility.pressRequestCount
        let launchedBundles = await launcher.bundleIdentifiers
        XCTAssertEqual(pressCount, 0)
        XCTAssertEqual(launchedBundles, ["com.example.host"])
        XCTAssertEqual(model.permissionState, .repairRequired(reason: .trustRevoked))
    }

    private func panelDocument(group: GroupRecord) -> CatalogDocument {
        let frequentDates = [120.0, 80, 40].map { testNow.addingTimeInterval(-$0) }
        return CatalogDocument(items: [
            panelItem(id: "favorite", name: "Alpha", favorite: true, order: 0),
            panelItem(id: "recent", name: "Beta", alias: "Needle", groups: [group.id], order: 1,
                      invocations: [testNow.addingTimeInterval(-10)]),
            panelItem(id: "frequent", name: "Gamma", order: 2, invocations: frequentDates),
            panelItem(id: "ignored", name: "Ignored", ignored: true, order: 3),
        ], groups: [group], preferences: .default)
    }

    private func unreadSnapshot(title: String) -> AccessibilitySnapshot {
        AccessibilitySnapshot(
            processIdentifier: 88,
            processName: "Lark Helper",
            bundleIdentifier: "com.larksuite.feishu",
            title: title,
            role: "AXMenuBarItem",
            subrole: nil,
            identifier: "unread",
            positionX: 10,
            positionY: 0,
            width: 28,
            height: 20,
            actions: ["AXPress"],
            accessibilityPath: [1]
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        return condition()
    }

    private func waitUntilAsync(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        return await condition()
    }

    private func twoItemDocument() -> CatalogDocument {
        CatalogDocument(items: [
            panelItem(id: "a", name: "A", order: 0),
            panelItem(id: "b", name: "B", order: 1),
        ], groups: [], preferences: .default)
    }

    private func panelItem(
        id: String, name: String, alias: String? = nil, favorite: Bool = false,
        groups: [UUID] = [], ignored: Bool = false, order: Int,
        invocations: [Date] = []
    ) -> MenuBarItemRecord {
        MenuBarItemRecord(
            id: id,
            identity: .init(bundleIdentifier: "com.example.\(id)", originalName: name, axIdentifier: id, path: [order]),
            hostName: "Host", alias: alias, capability: .full, isFavorite: favorite,
            groupIDs: groups, manualOrder: order, lastSeenAt: testNow,
            successfulInvocations: invocations, isIgnored: ignored
        )
    }
}

@MainActor
private final class PanelTrustValue {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

private final class LockedPanelClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date
    init(_ value: Date) { stored = value }
    var value: Date { lock.withLock { stored } }
    func advance(by interval: TimeInterval) { lock.withLock { stored = stored.addingTimeInterval(interval) } }
}

@MainActor
private final class ManualPanelLiveUpdateScheduler: PanelLiveUpdateScheduling, PanelLiveUpdateCancellation, @unchecked Sendable {
    private var action: (() -> Void)?
    private(set) var scheduledCount = 0
    private(set) var isCancelled = false
    private(set) var intervals: [TimeInterval] = []

    func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> any PanelLiveUpdateCancellation {
        intervals.append(interval)
        scheduledCount += 1
        self.action = action
        isCancelled = false
        return self
    }

    func fire() { guard !isCancelled else { return }; action?() }
    nonisolated func cancel() {
        MainActor.assumeIsolated {
            isCancelled = true
            action = nil
        }
    }
}

@MainActor
private struct FakeHostMetadataResolver: HostMetadataResolving {
    let name: String
    var bundleIdentifier: String? = nil
    func metadata(for snapshot: AccessibilitySnapshot) -> HostApplicationMetadata? {
        HostApplicationMetadata(displayName: name, icon: nil, bundleIdentifier: bundleIdentifier, applicationURL: nil)
    }
}

@MainActor
final class FakePermissionEffectHandler: PermissionEffectHandling {
    enum Call: Equatable { case systemPrompt, settings, reset }
    private(set) var calls: [Call] = []
    let resetAvailable: Bool
    init(resetAvailable: Bool = true) { self.resetAvailable = resetAvailable }
    func requestSystemPrompt() { calls.append(.systemPrompt) }
    func openAccessibilitySettings() { calls.append(.settings) }
    func confirmAccessibilityReset() -> Bool { true }
    func requestAccessibilityReset() -> Bool { calls.append(.reset); return resetAvailable }
}
