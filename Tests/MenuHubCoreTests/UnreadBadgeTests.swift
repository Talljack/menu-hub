import XCTest
@testable import MenuHubCore

final class UnreadBadgeTests: XCTestCase {
    func testParserAcceptsOnlyWholeNumericTitles() {
        XCTAssertEqual(UnreadCountParser.parse("14"), .exact(14))
        XCTAssertEqual(UnreadCountParser.parse(" ９ "), .exact(9))
        XCTAssertEqual(UnreadCountParser.parse("99+"), .atLeast99)

        for value in ["", "•", "3 unread", "Battery 83%", "12:30", "-1", "2@·17", "2+"] {
            XCTAssertNil(UnreadCountParser.parse(value), value)
        }
    }

    func testAutomaticClassificationIncludesApprovedChatAppsAndRejectsSystemMonitors() {
        XCTAssertTrue(ChatApplicationClassifier.isChat(bundleIdentifier: "com.larksuite.feishu", hostName: "Feishu"))
        XCTAssertTrue(ChatApplicationClassifier.isChat(bundleIdentifier: "com.tencent.xinWeChat", hostName: "WeChat"))
        XCTAssertTrue(ChatApplicationClassifier.isChat(bundleIdentifier: "com.tinyspeck.slackmacgap", hostName: "Slack"))
        XCTAssertTrue(ChatApplicationClassifier.isChat(bundleIdentifier: nil, hostName: "Telegram"))
        XCTAssertFalse(ChatApplicationClassifier.isChat(bundleIdentifier: "com.apple.controlcenter", hostName: "Battery"))
        XCTAssertFalse(ChatApplicationClassifier.isChat(bundleIdentifier: "com.bjango.istatmenus", hostName: "iStat Menus"))
        XCTAssertFalse(ChatApplicationClassifier.isChat(bundleIdentifier: "com.example.fake", hostName: "Slack Helper Tool"))
    }

    func testAggregatorUsesOverridesDeduplicatesAndSaturates() {
        let lark = record(id: "lark", bundleID: "com.larksuite.feishu", hostName: "Feishu")
        let duplicateLark = record(id: "lark", bundleID: "com.larksuite.feishu", hostName: "Feishu")
        let battery = record(id: "battery", bundleID: "com.apple.controlcenter", hostName: "Battery")
        let timer = record(id: "timer", bundleID: "com.example.timer", hostName: "Timer", preference: .include)
        let ignoredChat = record(id: "wechat", bundleID: "com.tencent.xinWeChat", hostName: "WeChat", ignored: true)
        let qq = record(id: "qq", bundleID: "com.tencent.qq", hostName: "QQ")
        let snapshots = [
            "lark": snapshot(bundleID: "com.larksuite.feishu", processName: "Feishu", title: "14"),
            "battery": snapshot(bundleID: "com.apple.controlcenter", processName: "Control Center", title: "83"),
            "timer": snapshot(bundleID: "com.example.timer", processName: "Timer", title: "5"),
            "wechat": snapshot(bundleID: "com.tencent.xinWeChat", processName: "WeChat", title: "7"),
            "qq": snapshot(bundleID: "com.tencent.qq", processName: "QQ", title: "99+")
        ]

        XCTAssertEqual(
            UnreadBadgeAggregator.presentation(
                records: [lark, duplicateLark, battery, timer, ignoredChat, qq],
                snapshots: snapshots
            ),
            .overflow
        )
    }

    func testAggregatorHonorsExcludeAndPresenceOnlyContributesNothing() {
        let excluded = record(
            id: "lark",
            bundleID: "com.larksuite.feishu",
            hostName: "Feishu",
            preference: .exclude
        )
        let presenceOnly = record(id: "wechat", bundleID: "com.tencent.xinWeChat", hostName: "WeChat")
        let snapshots = [
            "lark": snapshot(bundleID: "com.larksuite.feishu", processName: "Feishu", title: "12"),
            "wechat": snapshot(bundleID: "com.tencent.xinWeChat", processName: "WeChat", title: "•")
        ]

        XCTAssertEqual(
            UnreadBadgeAggregator.presentation(records: [excluded, presenceOnly], snapshots: snapshots),
            .hidden
        )
    }

    private func record(
        id: String,
        bundleID: String,
        hostName: String,
        preference: UnreadBadgePreference = .automatic,
        ignored: Bool = false
    ) -> MenuBarItemRecord {
        MenuBarItemRecord(
            id: id,
            identity: MenuBarItemIdentity(
                bundleIdentifier: bundleID,
                originalName: hostName,
                axIdentifier: id,
                path: [0]
            ),
            hostName: hostName,
            hostBundleIdentifier: bundleID,
            capability: .full,
            lastSeenAt: Date(timeIntervalSince1970: 1),
            isIgnored: ignored,
            unreadBadgePreference: preference
        )
    }

    private func snapshot(bundleID: String, processName: String, title: String) -> AccessibilitySnapshot {
        AccessibilitySnapshot(
            processIdentifier: 42,
            processName: processName,
            bundleIdentifier: bundleID,
            title: title,
            role: "AXMenuBarItem",
            subrole: "AXMenuExtra",
            identifier: nil,
            positionX: nil,
            positionY: nil,
            width: nil,
            height: nil,
            actions: [kAXPressAction as String],
            accessibilityPath: [0]
        )
    }
}
