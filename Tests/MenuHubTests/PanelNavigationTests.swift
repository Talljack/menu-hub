import AppKit
import XCTest
@testable import MenuHub
@testable import MenuHubCore

@MainActor
final class PanelNavigationTests: XCTestCase {
    func testDisplayTitleAlwaysLeadsWithResolvedHostName() {
        XCTAssertEqual(makeItem(host: "WeChat", item: "WeChat").primaryTitle, "WeChat")
        XCTAssertEqual(makeItem(host: "飞书", item: "6").primaryTitle, "飞书 — 6")
        XCTAssertEqual(makeItem(host: "飞书", item: "6", alias: "未读").primaryTitle, "飞书 — 未读")
        XCTAssertTrue(makeItem(host: "Example", item: "Status").primaryTitle.hasPrefix("Example"))
        XCTAssertTrue(makeItem(host: "", item: "Status").primaryTitle.hasPrefix("example"))
    }

    func testOutermostApplicationURLWalksOutOfNestedHelpers() {
        let helper = URL(fileURLWithPath: "/Applications/Lark.app/Contents/Frameworks/Lark Helper.app/Contents/MacOS/Lark Helper")
        XCTAssertEqual(
            HostApplicationResolver.outermostApplicationURL(containing: helper)?.path,
            "/Applications/Lark.app"
        )
        XCTAssertEqual(
            HostApplicationResolver.outermostApplicationURL(containing: URL(fileURLWithPath: "/Applications/WeChat.app"))?.path,
            "/Applications/WeChat.app"
        )
    }

    func testResolverUsesLocalizedOuterBundleMetadataSeam() {
        let outerURL = URL(fileURLWithPath: "/Applications/Lark.app")
        let resolver = HostApplicationResolver(
            executableURLForPID: { _ in outerURL.appendingPathComponent("Contents/Frameworks/Lark Helper.app/Contents/MacOS/Lark Helper") },
            metadataForApplicationURL: { url in
                XCTAssertEqual(url.standardizedFileURL.path, outerURL.standardizedFileURL.path)
                return HostApplicationMetadata(displayName: "飞书", icon: nil)
            }
        )

        let metadata = resolver.metadata(for: makeSnapshot())

        XCTAssertEqual(metadata?.displayName, "飞书")
    }

    func testResolverCachesBundleMetadataUntilApplicationLifecycleInvalidation() {
        let outerURL = URL(fileURLWithPath: "/Applications/Lark.app")
        var lookupCount = 0
        let resolver = HostApplicationResolver(
            executableURLForPID: { _ in outerURL },
            metadataForApplicationURL: { _ in
                lookupCount += 1
                return HostApplicationMetadata(displayName: "飞书", icon: nil)
            }
        )

        _ = resolver.metadata(for: makeSnapshot())
        _ = resolver.metadata(for: makeSnapshot())
        XCTAssertEqual(lookupCount, 1)

        resolver.invalidateAll()
        _ = resolver.metadata(for: makeSnapshot())
        XCTAssertEqual(lookupCount, 2)
    }

    func testUserApplicationPolicyKeepsUserAppsAndRejectsSystemStatusComponents() {
        let lark = URL(fileURLWithPath: "/Applications/Lark.app")
        let larkHelper = lark.appendingPathComponent("Contents/Frameworks/Lark Helper.app")
        XCTAssertTrue(HostApplicationResolver.isUserOpenedApplication(processURL: larkHelper, outerApplicationURL: lark))
        XCTAssertTrue(HostApplicationResolver.isUserOpenedApplication(processURL: lark, outerApplicationURL: lark))

        let controlCenter = URL(fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app")
        XCTAssertFalse(HostApplicationResolver.isUserOpenedApplication(processURL: controlCenter, outerApplicationURL: controlCenter))

        let passwords = URL(fileURLWithPath: "/System/Applications/Passwords.app")
        let passwordsExtra = passwords.appendingPathComponent("Contents/Library/LoginItems/PasswordsMenuBarExtra.app")
        XCTAssertFalse(HostApplicationResolver.isUserOpenedApplication(processURL: passwordsExtra, outerApplicationURL: passwords))
        XCTAssertTrue(HostApplicationResolver.isUserOpenedApplication(processURL: passwords, outerApplicationURL: passwords))
    }

    func testKeyboardReducerHandlesNavigationCommandsAndEscapePriority() {
        let router = PanelKeyboardRouter()
        XCTAssertEqual(router.action(for: .downArrow, hasSearchText: false), .selectNext)
        XCTAssertEqual(router.action(for: .upArrow, hasSearchText: false), .selectPrevious)
        XCTAssertEqual(router.action(for: .returnKey, hasSearchText: false), .invokeSelection)
        XCTAssertEqual(router.action(for: .commandReturn, hasSearchText: false), .openHost)
        XCTAssertEqual(router.action(for: .commandK, hasSearchText: false), .openActionMenu)
        XCTAssertEqual(router.action(for: .commandF, hasSearchText: false), .focusSearch)
        XCTAssertEqual(router.action(for: .commandDigit(1), hasSearchText: false), .invokeFavorite(0))
        XCTAssertEqual(router.action(for: .commandDigit(9), hasSearchText: false), .invokeFavorite(8))
        XCTAssertEqual(router.action(for: .escape, hasSearchText: true), .clearSearch)
        XCTAssertEqual(router.action(for: .escape, hasSearchText: false), .closePanel)
    }

    func testScrollLayoutReservesScrollerAndActionGutters() {
        XCTAssertGreaterThanOrEqual(HubPanelLayout.scrollContentTrailingGutter, 16)
        XCTAssertGreaterThanOrEqual(HubPanelLayout.rowActionTrailingPadding, 8)
        XCTAssertEqual(HubPanelLayout.scrollAccessibilityIdentifier, "hub.items.scroll")
    }

    func testScrollEdgeStateOnlyShowsAvailableDirections() {
        XCTAssertEqual(ScrollEdgeState.resolve(contentHeight: 600, viewportHeight: 300, contentOffset: 0), .init(canScrollUp: false, canScrollDown: true))
        XCTAssertEqual(ScrollEdgeState.resolve(contentHeight: 600, viewportHeight: 300, contentOffset: -150), .init(canScrollUp: true, canScrollDown: true))
        XCTAssertEqual(ScrollEdgeState.resolve(contentHeight: 600, viewportHeight: 300, contentOffset: -300), .init(canScrollUp: true, canScrollDown: false))
        XCTAssertEqual(ScrollEdgeState.resolve(contentHeight: 250, viewportHeight: 300, contentOffset: 0), .none)
    }

    func testAccessibilityPresentationDescribesEveryDynamicRowState() {
        let previousLanguage = LocalizationController.languagePreference
        LocalizationController.apply(.simplifiedChinese)
        defer { LocalizationController.apply(previousLanguage) }

        let title = "飞书 — 6"
        XCTAssertEqual(HubItemAccessibilityPresentation.resolve(title: title, capability: "点击", state: .idle).value, "可点击")
        XCTAssertEqual(HubItemAccessibilityPresentation.resolve(title: title, capability: "点击", state: .invoking).value, "正在执行")
        XCTAssertEqual(HubItemAccessibilityPresentation.resolve(title: title, capability: "点击", state: .succeeded).value, "已完成")
        XCTAssertEqual(HubItemAccessibilityPresentation.resolve(title: title, capability: "点击", state: .failed).value, "操作失败")
        let unavailable = HubItemAccessibilityPresentation.resolve(title: title, capability: "不可用", state: .unavailable)
        XCTAssertEqual(unavailable.value, "不可用")
        XCTAssertTrue(unavailable.help.contains("重新扫描"))
        XCTAssertTrue(unavailable.label.contains(title))
    }

    func testPressedAppearanceHasPriorityAndRespectsReduceMotion() {
        XCTAssertEqual(HubRowAppearance.resolve(selected: true, hovered: true, pressed: true, reduceMotion: false), .init(layer: .pressed, scale: 0.995))
        XCTAssertEqual(HubRowAppearance.resolve(selected: true, hovered: true, pressed: false, reduceMotion: false).layer, .selected)
        XCTAssertEqual(HubRowAppearance.resolve(selected: false, hovered: true, pressed: false, reduceMotion: false).layer, .hovered)
        XCTAssertEqual(HubRowAppearance.resolve(selected: false, hovered: false, pressed: true, reduceMotion: true).scale, 1)
    }

    func testPresentationIDsAreUniquePerSectionAndAllIsCanonical() {
        XCTAssertEqual(HubItemPresentationID(sectionID: "favorites", itemID: "item").rawValue, "favorites:item")
        XCTAssertNotEqual(HubItemPresentationID(sectionID: "recent", itemID: "item"), HubItemPresentationID(sectionID: "all", itemID: "item"))
        XCTAssertEqual(HubItemPresentationID.canonical(itemID: "item").rawValue, "all:item")
    }

    func testCanonicalPresentationUsesSingleQueryAwareSectionRule() {
        XCTAssertEqual(HubPanelPresentationContext.canonicalSectionID(query: ""), "all")
        XCTAssertEqual(HubPanelPresentationContext.canonicalSectionID(query: "  \n "), "all")
        XCTAssertEqual(HubPanelPresentationContext.canonicalSectionID(query: "lark"), "search")
        XCTAssertEqual(HubPanelPresentationContext.canonicalPresentationID(itemID: "item", query: " ").rawValue, "all:item")
        XCTAssertEqual(HubPanelPresentationContext.canonicalPresentationID(itemID: "item", query: " 6 ").rawValue, "search:item")
    }

    func testKeyboardEventContextProtectsIMEAndModifiedArrows() {
        let router = PanelKeyboardRouter()
        XCTAssertNil(router.command(for: .init(keyCode: 36, characters: "\r", modifiers: [], hasMarkedText: true)))
        XCTAssertNil(router.command(for: .init(keyCode: 53, characters: nil, modifiers: [], hasMarkedText: true)))
        XCTAssertNil(router.command(for: .init(keyCode: 126, characters: nil, modifiers: [.shift], hasMarkedText: false)))
        XCTAssertNil(router.command(for: .init(keyCode: 125, characters: nil, modifiers: [.option], hasMarkedText: false)))
        XCTAssertEqual(router.command(for: .init(keyCode: 126, characters: nil, modifiers: [], hasMarkedText: false)), .upArrow)
        XCTAssertEqual(router.command(for: .init(keyCode: 40, characters: "k", modifiers: [.command], hasMarkedText: false)), .commandK)
    }

    func testPanelBackgroundModeNeverStacksMaterialWhenTransparencyIsReduced() {
        XCTAssertEqual(HubPanelBackgroundMode.resolve(reduceTransparency: true), .solid)
        XCTAssertEqual(HubPanelBackgroundMode.resolve(reduceTransparency: false), .material)
    }

    func testGridProjectionCompactsUnavailableCatalogRecordsWithoutLeavingEmptyCells() {
        let first = makeItem(host: "WeChat", item: "wechat")
        let second = makeItem(host: "PopClip", item: "popclip")
        let unavailable = makeItem(host: "Stopped", item: "stopped").record

        XCTAssertEqual(
            HubGridProjection.items(
                records: [first.record, unavailable, first.record, second.record],
                availableItems: [first, second]
            ).map(\.id),
            ["wechat", "popclip"]
        )
    }

    func testRowOwnedActionMenuStateAcceptsExternalRequestAndDismissesLocally() {
        var state = HubItemActionMenuState()
        state.applyExternalRequest(false)
        XCTAssertFalse(state.isPresented)
        state.applyExternalRequest(true)
        XCTAssertTrue(state.isPresented)
        state.dismiss()
        XCTAssertFalse(state.isPresented)
    }

    private func makeItem(host: String, item: String, alias: String? = nil) -> HubPanelItem {
        let record = MenuBarItemRecord(
            id: item, identity: .init(bundleIdentifier: "com.example", originalName: item, axIdentifier: item, path: [0]),
            hostName: host, alias: alias, capability: .full, lastSeenAt: Date()
        )
        return HubPanelItem(record: record, snapshot: nil, effectiveLaunchOnly: false, hostIcon: nil)
    }

    private func makeSnapshot() -> AccessibilitySnapshot {
        AccessibilitySnapshot(
            processIdentifier: 42, processName: "Lark Helper", bundleIdentifier: "com.lark.helper", title: "6",
            role: "AXMenuBarItem", subrole: nil, identifier: nil, positionX: 0, positionY: 0,
            width: 20, height: 20, actions: ["AXPress"], accessibilityPath: [2, 4]
        )
    }
}
