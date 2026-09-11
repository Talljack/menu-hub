import AppKit
import ServiceManagement
import XCTest
@testable import MenuHub
@testable import MenuHubCore

@MainActor
final class ManagementSettingsTests: XCTestCase {
    func testManagementSearchMatchesHostAliasOriginalAndBundleName() async {
        var document = CatalogDocument.empty
        let group = GroupRecord(name: "研发", manualOrder: 0)
        document.groups = [group]
        document.items = [
            makeRecord(id: "lark", host: "飞书", original: "6", alias: "工作消息", bundle: "com.larksuite.helper"),
            makeRecord(id: "wechat", host: "WeChat", original: "WeChat", alias: nil, bundle: "com.tencent.xinWeChat")
        ]
        let controller = CatalogController(
            store: FakeCatalogStore(loadResults: [document]), accessibility: ControlledAccessibility(),
            launcher: FakeLauncher(), canLaunchHost: { _ in false }
        )
        await controller.load()
        let model = ManagementModel(controller: controller)

        document.items[0].groupIDs = [group.id]
        await controller.reset(to: document)

        for query in ["飞书", "工作", "6", "larksuite", "研发"] {
            model.query = query
            XCTAssertEqual(model.filteredItems.map(\.id), ["lark"])
        }
    }

    func testLaunchAtLoginStatusMapsEveryServiceState() {
        XCTAssertEqual(LaunchAtLoginStatus(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginStatus(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LaunchAtLoginStatus(.notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginStatus(.notFound), .unavailable)
    }

    func testShortcutValidationRejectsBareKeysAndAllowsOptionM() {
        XCTAssertFalse(ShortcutRecorderPolicy.isValid(keyCode: 46, modifiers: []))
        XCTAssertTrue(ShortcutRecorderPolicy.isValid(keyCode: 46, modifiers: [.option]))
        XCTAssertEqual(ShortcutRecorderPolicy.label(keyCode: 46, modifiers: [.option]), "⌥M")
    }

    func testFilteredManagementResultsCannotBeReorderedAgainstGlobalSlots() async {
        var document = CatalogDocument.empty
        document.items = [
            makeRecord(id: "a", host: "Alpha", original: "A", alias: nil, bundle: "a"),
            makeRecord(id: "b", host: "Beta", original: "B", alias: nil, bundle: "b")
        ]
        let store = FakeCatalogStore(loadResults: [document])
        let controller = CatalogController(store: store, accessibility: ControlledAccessibility(), launcher: FakeLauncher())
        await controller.load()
        let model = ManagementModel(controller: controller)
        model.query = "Alpha"

        XCTAssertFalse(model.canReorder)
        model.move(from: IndexSet(integer: 0), to: 1)
        await Task.yield()
        XCTAssertEqual(controller.document.items.map(\.id), ["a", "b"])
    }

    func testRestoreHiddenRequiresPreferenceLastHiddenAndCleanPreviousExit() {
        XCTAssertTrue(RestoreHiddenStartupPolicy.shouldRestore(
            preferenceEnabled: true, lastVisibilityHidden: true, previousRunEndedUnexpectedly: false
        ))
        XCTAssertFalse(RestoreHiddenStartupPolicy.shouldRestore(
            preferenceEnabled: false, lastVisibilityHidden: true, previousRunEndedUnexpectedly: false
        ))
        XCTAssertFalse(RestoreHiddenStartupPolicy.shouldRestore(
            preferenceEnabled: true, lastVisibilityHidden: false, previousRunEndedUnexpectedly: false
        ))
        XCTAssertFalse(RestoreHiddenStartupPolicy.shouldRestore(
            preferenceEnabled: true, lastVisibilityHidden: true, previousRunEndedUnexpectedly: true
        ))
    }

    func testSettingsWindowOriginIsCenteredInsideInvokingScreenVisibleFrame() {
        let visibleFrame = NSRect(x: 1440, y: 40, width: 1920, height: 1040)
        let windowFrame = NSRect(x: 0, y: 0, width: 720, height: 520)

        let origin = MenuHubWindowPlacement.centeredOrigin(
            windowFrame: windowFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 2040, accuracy: 0.001)
        XCTAssertEqual(origin.y, 300, accuracy: 0.001)
    }

    func testStatusItemAutosaveNamesAreStableAndDistinct() {
        XCTAssertEqual(StatusItemIdentity.primaryAutosaveName, "com.local.MenuHub.primary")
        XCTAssertEqual(StatusItemIdentity.spacerAutosaveName, "com.local.MenuHub.spacer")
        XCTAssertNotEqual(StatusItemIdentity.primaryAutosaveName, StatusItemIdentity.spacerAutosaveName)
    }

    func testControllerPersistsUnreadBadgeOverride() async {
        let document = CatalogDocument(
            items: [makeRecord(id: "timer", host: "Timer", original: "5", alias: nil, bundle: "com.example.timer")],
            groups: [],
            preferences: .default
        )
        let store = FakeCatalogStore(loadResults: [document])
        let controller = CatalogController(
            store: store, accessibility: ControlledAccessibility(), launcher: FakeLauncher()
        )
        await controller.load()

        await controller.setUnreadBadgePreference(.include, itemID: "timer")

        XCTAssertEqual(controller.document.items[0].unreadBadgePreference, .include)
        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted?.items[0].unreadBadgePreference, .include)
    }

    private func makeRecord(id: String, host: String, original: String, alias: String?, bundle: String) -> MenuBarItemRecord {
        MenuBarItemRecord(
            id: id,
            identity: .init(bundleIdentifier: bundle, originalName: original, axIdentifier: id, path: [0]),
            hostName: host, alias: alias, capability: .full, lastSeenAt: Date()
        )
    }
}
