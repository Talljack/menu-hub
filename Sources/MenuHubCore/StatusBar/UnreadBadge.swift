import Foundation

public enum UnreadBadgePreference: String, Codable, CaseIterable, Equatable, Sendable {
    case automatic
    case include
    case exclude
}

public enum UnreadCountValue: Equatable, Sendable {
    case exact(Int)
    case atLeast99
}

public enum UnreadBadgePresentation: Equatable, Sendable {
    case hidden
    case count(Int)
    case overflow

    public var label: String? {
        switch self {
        case .hidden:
            nil
        case let .count(value):
            String(min(max(value, 1), 99))
        case .overflow:
            "99+"
        }
    }
}

public enum UnreadCountParser {
    public static func parse(_ title: String?) -> UnreadCountValue? {
        guard let title else { return nil }
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let isOverflow = value.hasSuffix("+")
        let digits = isOverflow ? String(value.dropLast()) : value
        guard !digits.isEmpty else { return nil }

        let normalizedDigits = digits.compactMap { character -> String? in
            character.wholeNumberValue.map(String.init)
        }.joined()
        guard normalizedDigits.count == digits.count,
              let count = Int(normalizedDigits) else { return nil }

        if isOverflow {
            return count == 99 ? .atLeast99 : nil
        }
        return .exact(count)
    }
}

public enum ChatApplicationClassifier {
    private static let bundleIdentifiers: Set<String> = [
        "com.alibaba.dingtalkmac",
        "com.discord.discord",
        "com.hnc.discord",
        "com.kakao.kakaotalkmac",
        "com.larksuite.feishu",
        "com.larksuite.lark",
        "com.mattermost.desktop",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.tencent.qq",
        "com.tencent.weworkmac",
        "com.tencent.xinwechat",
        "com.viber.osx",
        "im.riot.app",
        "jp.naver.line.mac",
        "net.whatsapp.whatsapp",
        "org.telegram.desktop",
        "org.whispersystems.signal-desktop",
        "org.zulip.zulip",
        "ph.telegra.telegraph",
        "ru.keepcoder.telegram",
        "us.zoom.xos"
    ]

    private static let hostNames: Set<String> = [
        "dingtalk", "discord", "element", "feishu", "kakaotalk", "lark", "line",
        "mattermost", "microsoft teams", "qq", "signal", "slack", "teams", "telegram",
        "viber", "wechat", "wecom", "whatsapp", "zoom workplace", "zulip",
        "企业微信", "微信", "钉钉", "飞书"
    ]

    public static func isChat(bundleIdentifier: String?, hostName: String) -> Bool {
        if let bundleIdentifier {
            let normalizedBundleID = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if bundleIdentifiers.contains(normalizedBundleID) { return true }
        }
        return hostNames.contains(normalizedHostName(hostName))
    }

    private static func normalizedHostName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public enum UnreadBadgeAggregator {
    public static func presentation(
        records: [MenuBarItemRecord],
        snapshots: [String: AccessibilitySnapshot]
    ) -> UnreadBadgePresentation {
        var seen = Set<String>()
        var total = 0

        for record in records where !record.isIgnored && seen.insert(record.id).inserted {
            guard let snapshot = snapshots[record.id], shouldInclude(record: record, snapshot: snapshot),
                  let unread = UnreadCountParser.parse(snapshot.title) else { continue }
            switch unread {
            case .atLeast99:
                return .overflow
            case let .exact(value):
                guard value > 0 else { continue }
                let (sum, overflow) = total.addingReportingOverflow(value)
                if overflow || sum >= 100 { return .overflow }
                total = sum
            }
        }

        return total > 0 ? .count(total) : .hidden
    }

    private static func shouldInclude(record: MenuBarItemRecord, snapshot: AccessibilitySnapshot) -> Bool {
        switch record.unreadBadgePreference {
        case .include:
            true
        case .exclude:
            false
        case .automatic:
            ChatApplicationClassifier.isChat(
                bundleIdentifier: record.hostBundleIdentifier ?? snapshot.bundleIdentifier ?? record.identity.bundleIdentifier,
                hostName: record.hostName.isEmpty ? snapshot.processName : record.hostName
            )
        }
    }
}
