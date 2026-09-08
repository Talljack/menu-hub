import XCTest
@testable import MenuHubCore

final class CatalogMutationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testDeletingGroupKeepsItemAndOnlyRemovesMembership() {
        let group = GroupRecord(name: "Work")
        var document = CatalogDocument(items: [item(groups: [group.id])], groups: [group], preferences: .default)

        document.deleteGroup(id: group.id)

        XCTAssertEqual(document.items.count, 1)
        XCTAssertEqual(document.items[0].groupIDs, [])
        XCTAssertEqual(document.groups, [])
    }

    func testCreateRenameAndReorderGroups() {
        var document = CatalogDocument.empty
        let first = document.createGroup(name: "  First ")
        let second = document.createGroup(name: "Second")

        XCTAssertTrue(document.renameGroup(id: second.id, name: "  Renamed  "))
        document.reorderGroups(groupIDs: [second.id, first.id])

        XCTAssertEqual(document.groups.first(where: { $0.id == first.id })?.name, "First")
        XCTAssertEqual(document.groups.first(where: { $0.id == second.id })?.name, "Renamed")
        XCTAssertEqual(document.groups.sorted { $0.manualOrder < $1.manualOrder }.map(\.id), [second.id, first.id])
    }

    func testAliasIsTrimmedAndWhitespaceClearsIt() {
        var document = CatalogDocument(items: [item()], groups: [], preferences: .default)
        XCTAssertTrue(document.setAlias("  Clock  ", forItemID: "item"))
        XCTAssertEqual(document.items[0].alias, "Clock")
        XCTAssertTrue(document.setAlias(" \n ", forItemID: "item"))
        XCTAssertNil(document.items[0].alias)
    }

    func testMembershipAllowsMultipleGroupsWithoutDuplicates() {
        let first = GroupRecord(name: "One")
        let second = GroupRecord(name: "Two")
        var document = CatalogDocument(items: [item()], groups: [first, second], preferences: .default)

        XCTAssertTrue(document.setMembership(true, itemID: "item", groupID: first.id))
        XCTAssertTrue(document.setMembership(true, itemID: "item", groupID: second.id))
        XCTAssertFalse(document.setMembership(true, itemID: "item", groupID: second.id))
        XCTAssertEqual(document.items[0].groupIDs, [first.id, second.id])
    }

    func testManualOrderingNormalizesKnownItemsAndAppendsOthers() {
        var document = CatalogDocument(
            items: [item(id: "a", order: 7), item(id: "b", order: 2), item(id: "c", order: 1)],
            groups: [], preferences: .default
        )

        document.reorderItems(itemIDs: ["b", "a", "missing", "b"])

        XCTAssertEqual(document.items.sorted { $0.manualOrder < $1.manualOrder }.map(\.id), ["b", "a", "c"])
        XCTAssertEqual(document.items.map(\.manualOrder).sorted(), [0, 1, 2])
    }

    func testFavoriteIgnoreAndSuccessfulInvocationMutateExistingItemOnly() {
        var document = CatalogDocument(items: [item()], groups: [], preferences: .default)
        XCTAssertTrue(document.setFavorite(true, forItemID: "item"))
        XCTAssertTrue(document.setIgnored(true, forItemID: "item"))
        XCTAssertTrue(document.recordSuccessfulInvocation(forItemID: "item", at: now))
        XCTAssertFalse(document.recordSuccessfulInvocation(forItemID: "missing", at: now))
        XCTAssertTrue(document.items[0].isFavorite)
        XCTAssertTrue(document.items[0].isIgnored)
        XCTAssertEqual(document.items[0].successfulInvocations, [now])
    }

    func testRecordSuccessfulInvocationRejectsFutureAndNonFiniteDatesButRetainsRealRapidEvents() {
        var record = item()
        XCTAssertTrue(record.recordSuccessfulInvocation(at: now, now: now))
        XCTAssertTrue(record.recordSuccessfulInvocation(at: now.addingTimeInterval(5), now: now.addingTimeInterval(5)))
        XCTAssertFalse(record.recordSuccessfulInvocation(at: now.addingTimeInterval(1), now: now))
        XCTAssertFalse(record.recordSuccessfulInvocation(at: Date(timeIntervalSinceReferenceDate: .infinity), now: now))
        XCTAssertEqual(record.successfulInvocations.count, 2)
    }

    func testReconcilePreservesUserFieldsAndHistoryWhileRefreshingObservedFields() {
        let group = GroupRecord(name: "Pinned")
        var existing = item(groups: [group.id])
        existing.alias = "My Item"
        existing.isFavorite = true
        existing.isIgnored = true
        existing.successfulInvocations = [now.addingTimeInterval(-30)]
        existing.lastError = .staleElement
        var document = CatalogDocument(items: [existing], groups: [group], preferences: .default)

        let snapshot = makeSnapshot(processName: "New Host", title: "New Name", actions: ["AXPress"])
        let result = CatalogReconciler.reconcile(&document, snapshots: [snapshot], at: now, canLaunchHost: { _ in true })

        XCTAssertEqual(document.items[0].alias, "My Item")
        XCTAssertTrue(document.items[0].isFavorite)
        XCTAssertTrue(document.items[0].isIgnored)
        XCTAssertEqual(document.items[0].groupIDs, [group.id])
        XCTAssertEqual(document.items[0].successfulInvocations, [now.addingTimeInterval(-30)])
        XCTAssertEqual(document.items[0].hostName, "New Host")
        XCTAssertEqual(document.items[0].identity.originalName, "New Name")
        XCTAssertEqual(document.items[0].capability, .full)
        XCTAssertEqual(document.items[0].lastSeenAt, now)
        XCTAssertNil(document.items[0].lastError)
        XCTAssertEqual(result.runtimeSnapshots["item"], snapshot)
    }

    func testReconcileDuplicateIdentityFailsClosedDeterministically() {
        var original = CatalogDocument(items: [item()], groups: [], preferences: .default)
        original.items[0].lastError = .staleElement
        var forward = original
        var reversed = original
        let first = makeSnapshot(path: [1])
        let second = makeSnapshot(path: [1], positionX: 80)

        let firstResult = CatalogReconciler.reconcile(&forward, snapshots: [first, second], at: now, canLaunchHost: { _ in true })
        let secondResult = CatalogReconciler.reconcile(&reversed, snapshots: [second, first], at: now, canLaunchHost: { _ in true })

        XCTAssertEqual(forward, original)
        XCTAssertEqual(reversed, original)
        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(firstResult.duplicateStableIDs, [first.menuBarItemIdentity.stableID])
        XCTAssertTrue(firstResult.runtimeSnapshots.isEmpty)
    }

    func testReconcileStableIdentityUpdatesExistingRecordWithoutChangingID() {
        var document = CatalogDocument.empty
        let first = makeSnapshot(positionX: 10)
        _ = CatalogReconciler.reconcile(&document, snapshots: [first], at: now, canLaunchHost: { _ in true })
        let stableID = document.items[0].id
        let moved = makeSnapshot(positionX: 500)

        _ = CatalogReconciler.reconcile(&document, snapshots: [moved], at: now.addingTimeInterval(60), canLaunchHost: { _ in true })

        XCTAssertEqual(document.items.count, 1)
        XCTAssertEqual(document.items[0].id, stableID)
        XCTAssertEqual(document.items[0].identity.position?.x, 500)
    }

    func testReconcileDynamicTitleKeepsRecordIDAndUserData() {
        let group = GroupRecord(name: "Pinned")
        var existing = MenuBarItemRecord(
            id: "lark-count", identity: .init(bundleIdentifier: "com.lark.helper", originalName: "3", axIdentifier: nil, path: [2, 4]),
            hostName: "Lark Helper", alias: "Unread", capability: .full, isFavorite: true,
            groupIDs: [group.id], manualOrder: 7, lastSeenAt: now.addingTimeInterval(-20),
            successfulInvocations: [now.addingTimeInterval(-10)]
        )
        existing.lastError = .staleElement
        var document = CatalogDocument(items: [existing], groups: [group], preferences: .default)
        let updated = makeSnapshot(title: "6", bundleIdentifier: "com.lark.helper", actions: ["AXPress"], path: [2, 4], positionX: 90, identifier: nil)

        let result = CatalogReconciler.reconcile(&document, snapshots: [updated], at: now, canLaunchHost: { _ in true })

        XCTAssertEqual(document.items.count, 1)
        XCTAssertEqual(document.items[0].id, "lark-count")
        XCTAssertEqual(document.items[0].identity.originalName, "6")
        XCTAssertEqual(document.items[0].alias, "Unread")
        XCTAssertTrue(document.items[0].isFavorite)
        XCTAssertEqual(document.items[0].groupIDs, [group.id])
        XCTAssertEqual(document.items[0].manualOrder, 7)
        XCTAssertEqual(document.items[0].successfulInvocations, [now.addingTimeInterval(-10)])
        XCTAssertEqual(result.runtimeSnapshots["lark-count"], updated)
    }

    func testReconcileBadgeDisappearingIntoHostNameKeepsWeChatRecordID() {
        let existing = MenuBarItemRecord(
            id: "wechat-badge",
            identity: .init(
                processIdentifier: 42,
                bundleIdentifier: "com.tencent.xinWeChat",
                originalName: "1",
                axIdentifier: nil,
                path: [0]
            ),
            hostName: "WeChat",
            capability: .full,
            lastSeenAt: now.addingTimeInterval(-10)
        )
        var document = CatalogDocument(items: [existing], groups: [], preferences: .default)
        let withoutBadge = makeSnapshot(
            processName: "WeChat",
            title: nil,
            bundleIdentifier: "com.tencent.xinWeChat",
            path: [0],
            identifier: nil
        )

        let result = CatalogReconciler.reconcile(
            &document,
            snapshots: [withoutBadge],
            at: now,
            canLaunchHost: { _ in true }
        )

        XCTAssertEqual(document.items.count, 1)
        XCTAssertEqual(document.items[0].id, "wechat-badge")
        XCTAssertEqual(document.items[0].identity.originalName, "WeChat")
        XCTAssertEqual(result.runtimeSnapshots["wechat-badge"], withoutBadge)
    }

    func testReconcileBadgeToHostFallbackRequiresSameProcessGeneration() {
        let existing = MenuBarItemRecord(
            id: "old-wechat",
            identity: .init(
                processIdentifier: 41,
                bundleIdentifier: "com.tencent.xinWeChat",
                originalName: "1",
                axIdentifier: nil,
                path: [0]
            ),
            hostName: "WeChat",
            capability: .full,
            lastSeenAt: now.addingTimeInterval(-10)
        )
        var document = CatalogDocument(items: [existing], groups: [], preferences: .default)
        let restartedWithoutBadge = makeSnapshot(
            processName: "WeChat",
            title: nil,
            bundleIdentifier: "com.tencent.xinWeChat",
            path: [0],
            identifier: nil
        )

        let result = CatalogReconciler.reconcile(
            &document,
            snapshots: [restartedWithoutBadge],
            at: now,
            canLaunchHost: { _ in true }
        )

        XCTAssertEqual(document.items.count, 2)
        XCTAssertEqual(document.items.first(where: { $0.id == "old-wechat" })?.identity.originalName, "1")
        XCTAssertNil(result.runtimeSnapshots["old-wechat"])
    }

    func testDynamicStatusTransitionRejectsUnrelatedTextAtSamePath() {
        XCTAssertTrue(DynamicStatusTitle.canTransition(from: "3", to: "6"))
        XCTAssertTrue(DynamicStatusTitle.canTransition(from: "Unread (3)", to: "Unread (6)"))
        XCTAssertTrue(DynamicStatusTitle.canTransition(from: "1", to: "WeChat", knownHostNames: ["WeChat"]))
        XCTAssertTrue(DynamicStatusTitle.canTransition(from: "WeChat", to: "99+", knownHostNames: ["WeChat"]))
        XCTAssertFalse(DynamicStatusTitle.canTransition(from: "1", to: "Settings", knownHostNames: ["WeChat"]))
        XCTAssertFalse(DynamicStatusTitle.canTransition(from: "Sync", to: "VPN"))
        XCTAssertFalse(DynamicStatusTitle.canTransition(from: "Mode 1", to: "Other 2"))

        var existing = item()
        existing.id = "sync-record"
        existing.identity.axIdentifier = nil
        existing.identity.originalName = "Sync"
        existing.alias = "Keep Me"
        var document = CatalogDocument(items: [existing], groups: [], preferences: .default)
        let unrelated = makeSnapshot(title: "VPN", identifier: nil)

        _ = CatalogReconciler.reconcile(&document, snapshots: [unrelated], at: now, canLaunchHost: { _ in true })

        XCTAssertEqual(document.items.count, 2)
        XCTAssertEqual(document.items.first(where: { $0.id == "sync-record" })?.alias, "Keep Me")
        XCTAssertEqual(document.items.first(where: { $0.id == "sync-record" })?.identity.originalName, "Sync")
    }

    func testReconcileDynamicTitleConsolidatesHistoricalDuplicatesRegardlessOfOrder() {
        let firstRecord = MenuBarItemRecord(
            id: "old-3", identity: .init(bundleIdentifier: "com.lark.helper", originalName: "3", axIdentifier: nil, path: [2, 4]),
            hostName: "Lark Helper", capability: .full, lastSeenAt: now
        )
        let duplicateRecord = MenuBarItemRecord(
            id: "old-4", identity: .init(bundleIdentifier: "com.lark.helper", originalName: "4", axIdentifier: nil, path: [2, 4]),
            hostName: "Lark Helper", capability: .full, lastSeenAt: now
        )
        let incoming = makeSnapshot(title: "6", bundleIdentifier: "com.lark.helper", path: [2, 4], identifier: nil)
        var forward = CatalogDocument(items: [firstRecord, duplicateRecord], groups: [], preferences: .default)
        var reversed = CatalogDocument(items: [duplicateRecord, firstRecord], groups: [], preferences: .default)

        let first = CatalogReconciler.reconcile(&forward, snapshots: [incoming], at: now, canLaunchHost: { _ in true })
        let second = CatalogReconciler.reconcile(&reversed, snapshots: [incoming], at: now, canLaunchHost: { _ in true })

        XCTAssertEqual(forward.items.count, 1)
        XCTAssertEqual(reversed.items.count, 1)
        XCTAssertEqual(forward.items[0].id, "old-3")
        XCTAssertEqual(reversed.items[0].id, "old-3")
        XCTAssertEqual(forward.items[0].identity.originalName, "6")
        XCTAssertEqual(reversed.items[0].identity.originalName, "6")
        XCTAssertEqual(first.runtimeSnapshots["old-3"], incoming)
        XCTAssertEqual(second.runtimeSnapshots["old-3"], incoming)
        XCTAssertEqual(first.runtimeSnapshots.keys.sorted(), second.runtimeSnapshots.keys.sorted())
    }

    func testReconcileDynamicTitleCleansEarlierMalformedBadgeVariantsAtSamePath() {
        let records = ["2@·17", "3", "4", "5"].enumerated().map { index, title in
            MenuBarItemRecord(
                id: "old-\(index)",
                identity: .init(bundleIdentifier: "com.lark.helper", originalName: title, axIdentifier: nil, path: [0]),
                hostName: "Lark Helper", capability: .full, manualOrder: index,
                lastSeenAt: now.addingTimeInterval(TimeInterval(index))
            )
        }
        var document = CatalogDocument(items: records, groups: [], preferences: .default)
        let incoming = makeSnapshot(title: "6", bundleIdentifier: "com.lark.helper", path: [0], identifier: nil)

        _ = CatalogReconciler.reconcile(&document, snapshots: [incoming], at: now.addingTimeInterval(10), canLaunchHost: { _ in true })

        XCTAssertEqual(document.items.count, 1)
        XCTAssertEqual(document.items[0].identity.originalName, "6")
    }

    func testReconcileFiltersSelfInvisibleAndUnnamedControlCenterSnapshots() {
        var document = CatalogDocument.empty
        let selfSnapshot = makeSnapshot(bundleIdentifier: "com.local.MenuHub")
        let invisible = makeSnapshot(width: 0)
        let unnamedControlCenter = makeSnapshot(processName: "Control Center", title: nil)

        let result = CatalogReconciler.reconcile(
            &document,
            snapshots: [selfSnapshot, invisible, unnamedControlCenter],
            at: now,
            canLaunchHost: { _ in true }
        )

        XCTAssertTrue(document.items.isEmpty)
        XCTAssertTrue(result.runtimeSnapshots.isEmpty)
    }

    func testLaunchOnlyRequiresNonemptyBundleAndKnownLaunchTarget() {
        var noBundle = CatalogDocument.empty
        var unknown = CatalogDocument.empty
        var known = CatalogDocument.empty
        let missingBundle = makeSnapshot(bundleIdentifier: nil, actions: [])
        let bundled = makeSnapshot(bundleIdentifier: "com.example.host", actions: [])

        _ = CatalogReconciler.reconcile(&noBundle, snapshots: [missingBundle], at: now, canLaunchHost: { _ in true })
        _ = CatalogReconciler.reconcile(&unknown, snapshots: [bundled], at: now, canLaunchHost: { _ in false })
        _ = CatalogReconciler.reconcile(&known, snapshots: [bundled], at: now, canLaunchHost: { $0 == "com.example.host" })

        XCTAssertEqual(noBundle.items[0].capability, .unavailable)
        XCTAssertEqual(unknown.items[0].capability, .unavailable)
        XCTAssertEqual(known.items[0].capability, .launchOnly)
    }

    private func item(id: String = "item", groups: [UUID] = [], order: Int = 0) -> MenuBarItemRecord {
        MenuBarItemRecord(
            id: id,
            identity: .init(bundleIdentifier: "com.example.host", originalName: "Item", axIdentifier: "item", path: [1]),
            hostName: "Host", capability: .full, groupIDs: groups, manualOrder: order, lastSeenAt: now
        )
    }

    private func makeSnapshot(
        processName: String = "Host", title: String? = "Item", bundleIdentifier: String? = "com.example.host",
        actions: [String] = ["AXPress"], path: [Int] = [1], positionX: Double = 10,
        width: Double = 20, identifier: String? = "item"
    ) -> AccessibilitySnapshot {
        AccessibilitySnapshot(
            processIdentifier: 42, processName: processName, bundleIdentifier: bundleIdentifier,
            title: title, role: "AXMenuBarItem", subrole: nil, identifier: identifier,
            positionX: positionX, positionY: 0, width: width, height: 20,
            actions: actions, accessibilityPath: path
        )
    }
}
