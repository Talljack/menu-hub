import Foundation
import XCTest
@testable import MenuHubCore

private let smartGroupTestNow = Date(timeIntervalSince1970: 2_000_000_000)

final class SmartGroupEngineTests: XCTestCase {
    func testRecentIncludesFourteenDayCutoffExcludesOlderAndFutureTimestamps() {
        let engine = SmartGroupEngine(now: { smartGroupTestNow })
        let cutoff = smartGroupTestNow.addingTimeInterval(-14 * 24 * 60 * 60)
        let items = [
            makeItem(id: "cutoff", invocations: [cutoff]),
            makeItem(id: "older", invocations: [cutoff.addingTimeInterval(-0.001)]),
            makeItem(id: "future", invocations: [smartGroupTestNow.addingTimeInterval(1)]),
        ]

        XCTAssertEqual(engine.recentItems(in: items).map(\.id), ["cutoff"])
    }

    func testRecentUsesLatestValidTimestampSortsDescendingAndLimitsToEight() {
        let engine = SmartGroupEngine(now: { smartGroupTestNow })
        let items = (0..<10).reversed().map { index in
            makeItem(
                id: String(index),
                invocations: [
                    smartGroupTestNow.addingTimeInterval(-Double(index + 100)),
                    smartGroupTestNow.addingTimeInterval(-Double(index)),
                ].reversed()
            )
        }

        XCTAssertEqual(engine.recentItems(in: items).map(\.id), (0..<8).map(String.init))
    }

    func testRecentBreaksTimestampTiesByNameThenStableID() {
        let engine = SmartGroupEngine(now: { smartGroupTestNow })
        let timestamp = smartGroupTestNow.addingTimeInterval(-60)
        let items = [
            makeItem(id: "z", name: "Beta", invocations: [timestamp]),
            makeItem(id: "b", name: "Alpha", invocations: [timestamp]),
            makeItem(id: "a", name: "Alpha", invocations: [timestamp]),
        ]

        XCTAssertEqual(engine.recentItems(in: items).map(\.id), ["a", "b", "z"])
    }

    func testFrequentUsesRollingThirtyDaysAndRequiresThreeDeduplicatedInvocations() {
        let engine = SmartGroupEngine(now: { smartGroupTestNow })
        let cutoff = smartGroupTestNow.addingTimeInterval(-30 * 24 * 60 * 60)
        let included = makeItem(id: "included", invocations: [cutoff, cutoff.addingTimeInterval(30), smartGroupTestNow])
        let onlyTwo = makeItem(id: "two", invocations: [cutoff, smartGroupTestNow])
        let outside = makeItem(
            id: "outside",
            invocations: [cutoff.addingTimeInterval(-1), cutoff, smartGroupTestNow]
        )

        XCTAssertEqual(engine.frequentItems(in: [onlyTwo, outside, included]).map(\.id), ["included"])
    }

    func testFrequentSortsUnorderedTimestampsAndCollapsesConsecutiveIntervalsUnderThirtySeconds() {
        let engine = SmartGroupEngine(now: { smartGroupTestNow })
        let base = smartGroupTestNow.addingTimeInterval(-300)
        let included = makeItem(
            id: "included",
            invocations: [base.addingTimeInterval(59), base, base.addingTimeInterval(29), base.addingTimeInterval(89)]
        )
        let collapsedToTwo = makeItem(
            id: "collapsed",
            invocations: [base.addingTimeInterval(58), base.addingTimeInterval(29), base]
        )

        XCTAssertEqual(engine.frequentItems(in: [collapsedToTwo, included]).map(\.id), ["included"])
    }

    func testExactlyThirtySecondsCountsAsAnotherInvocation() {
        let engine = SmartGroupEngine(now: { smartGroupTestNow })
        let base = smartGroupTestNow.addingTimeInterval(-100)
        let item = makeItem(id: "boundary", invocations: [
            base, base.addingTimeInterval(30), base.addingTimeInterval(60),
        ])

        XCTAssertEqual(engine.frequentItems(in: [item]).map(\.id), ["boundary"])
    }

    func testFrequentDeduplicationComparesAgainstLastRetainedInvocation() {
        let engine = SmartGroupEngine(now: { smartGroupTestNow })
        let base = smartGroupTestNow.addingTimeInterval(-100)
        let item = makeItem(
            id: "retained",
            invocations: [0, 20, 40, 60, 80].map { base.addingTimeInterval($0) }
        )

        XCTAssertEqual(engine.frequentItems(in: [item]).map(\.id), ["retained"])
    }

    func testFrequentSortsByCountThenLastInvocationThenNameAndID() {
        let engine = SmartGroupEngine(now: { smartGroupTestNow })
        func times(_ offsets: [TimeInterval]) -> [Date] {
            offsets.map { smartGroupTestNow.addingTimeInterval($0) }
        }
        let items = [
            makeItem(id: "three", name: "First", invocations: times([-300, -200, -100])),
            makeItem(id: "older", name: "Older", invocations: times([-400, -300, -200, -100])),
            makeItem(id: "z", name: "Beta", invocations: times([-310, -210, -110, -10])),
            makeItem(id: "b", name: "Alpha", invocations: times([-310, -210, -110, -10])),
            makeItem(id: "a", name: "Alpha", invocations: times([-310, -210, -110, -10])),
        ]

        XCTAssertEqual(engine.frequentItems(in: items).map(\.id), ["a", "b", "z", "older", "three"])
    }

    func testFutureTimestampsAreIgnoredByFrequentGroupAndInputIsNotMutated() {
        let engine = SmartGroupEngine(now: { smartGroupTestNow })
        let original = makeItem(id: "future", invocations: [
            smartGroupTestNow.addingTimeInterval(-60),
            smartGroupTestNow.addingTimeInterval(-30),
            smartGroupTestNow.addingTimeInterval(1),
        ])
        let items = [original]

        XCTAssertTrue(engine.frequentItems(in: items).isEmpty)
        XCTAssertEqual(items, [original])
    }

    func testEngineIsSendable() {
        assertSendable(SmartGroupEngine(now: { smartGroupTestNow }))
    }

    private func assertSendable<T: Sendable>(_: T) {}

    private func makeItem(
        id: String,
        name: String? = nil,
        invocations: [Date]
    ) -> MenuBarItemRecord {
        MenuBarItemRecord(
            id: id,
            identity: MenuBarItemIdentity(
                bundleIdentifier: "com.example.\(id)",
                originalName: name ?? id,
                axIdentifier: id,
                path: [0]
            ),
            hostName: "Host",
            capability: .full,
            lastSeenAt: .distantPast,
            successfulInvocations: invocations
        )
    }
}
