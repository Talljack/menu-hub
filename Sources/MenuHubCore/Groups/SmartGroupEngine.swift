import Foundation

public struct SmartGroupEngine: Sendable {
    private static let recentInterval: TimeInterval = 14 * 24 * 60 * 60
    private static let frequentInterval: TimeInterval = 30 * 24 * 60 * 60
    private static let repeatedInvocationInterval: TimeInterval = 30
    private static let recentLimit = 8

    private let nowProvider: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.nowProvider = now
    }

    public func recentItems(in items: [MenuBarItemRecord]) -> [MenuBarItemRecord] {
        let now = nowProvider()
        let cutoff = now.addingTimeInterval(-Self.recentInterval)
        let candidates = items.compactMap { item -> (item: MenuBarItemRecord, last: Date)? in
            guard let last = validInvocations(for: item, from: cutoff, through: now).last else {
                return nil
            }
            return (item, last)
        }

        return candidates.sorted {
            if $0.last != $1.last { return $0.last > $1.last }
            return stableItemOrder($0.item, $1.item)
        }
        .prefix(Self.recentLimit)
        .map(\.item)
    }

    public func frequentItems(in items: [MenuBarItemRecord]) -> [MenuBarItemRecord] {
        let now = nowProvider()
        let cutoff = now.addingTimeInterval(-Self.frequentInterval)
        let candidates = items.compactMap { item -> FrequentCandidate? in
            let timestamps = validInvocations(for: item, from: cutoff, through: now)
            guard let lastInvocation = timestamps.last else { return nil }

            var count = 0
            var lastRetainedTimestamp: Date?
            for timestamp in timestamps {
                if lastRetainedTimestamp.map({ timestamp.timeIntervalSince($0) >= Self.repeatedInvocationInterval }) ?? true {
                    count += 1
                    lastRetainedTimestamp = timestamp
                }
            }
            guard count >= 3 else { return nil }
            return FrequentCandidate(item: item, count: count, lastInvocation: lastInvocation)
        }

        return candidates.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.lastInvocation != $1.lastInvocation {
                return $0.lastInvocation > $1.lastInvocation
            }
            return stableItemOrder($0.item, $1.item)
        }
        .map(\.item)
    }

    private func validInvocations(
        for item: MenuBarItemRecord,
        from cutoff: Date,
        through now: Date
    ) -> [Date] {
        item.successfulInvocations
            .filter { $0 >= cutoff && $0 <= now }
            .sorted()
    }

    private func stableItemOrder(_ lhs: MenuBarItemRecord, _ rhs: MenuBarItemRecord) -> Bool {
        let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
        return lhs.id < rhs.id
    }

    private struct FrequentCandidate {
        let item: MenuBarItemRecord
        let count: Int
        let lastInvocation: Date
    }
}
