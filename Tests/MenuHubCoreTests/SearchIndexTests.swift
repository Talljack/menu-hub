import Foundation
import XCTest
@testable import MenuHubCore

final class SearchIndexTests: XCTestCase {
    func testExactAliasRanksAheadOfExactOriginalName() {
        let alias = makeItem(id: "alias", originalName: "Unrelated", alias: "Sync")
        let name = makeItem(id: "name", originalName: "Sync")

        let results = SearchIndex.search("sync", in: [name, alias])

        XCTAssertEqual(results.map(\.item.id), ["alias", "name"])
        XCTAssertEqual(results.map(\.matchedField), [.alias, .name])
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }

    func testMatchCategoriesHaveStrictPriority() {
        let groupID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let items = [
            makeItem(id: "group", originalName: "Calendar", groupIDs: [groupID]),
            makeItem(id: "host", originalName: "Battery", hostName: "Sync Host"),
            makeItem(id: "substring", originalName: "Async Task"),
            makeItem(id: "word", originalName: "Cloud Sync Agent"),
            makeItem(id: "prefix", originalName: "Sync Center"),
            makeItem(id: "exact", originalName: "Sync"),
            makeItem(id: "alias", originalName: "Other", alias: "Sync"),
        ]
        let groups = [GroupRecord(id: groupID, name: "Sync Tools")]

        let results = SearchIndex.search("sync", in: items, groups: groups)

        XCTAssertEqual(results.map(\.item.id), [
            "alias", "exact", "prefix", "word", "substring", "host", "group",
        ])
        XCTAssertEqual(results.map(\.matchedField), [
            .alias, .name, .name, .name, .name, .host, .group,
        ])
        XCTAssertEqual(results.map(\.score), results.map(\.score).sorted(by: >))
    }

    func testQueryAndFieldsUseUnicodeFoldingAndCollapsedWhitespace() {
        let item = makeItem(id: "unicode", originalName: "cafe status")

        let results = SearchIndex.search("  ＣＡＦÉ\u{00a0}\n STATUS  ", in: [item])

        XCTAssertEqual(results.map(\.item.id), ["unicode"])
        XCTAssertEqual(results.first?.matchedField, .name)
    }

    func testGroupNameCanMatchThroughMembership() {
        let matchingGroup = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let otherGroup = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let included = makeItem(id: "included", originalName: "Battery", groupIDs: [matchingGroup])
        let excluded = makeItem(id: "excluded", originalName: "Clock", groupIDs: [otherGroup])

        let results = SearchIndex.search(
            "productivity",
            in: [excluded, included],
            groups: [
                GroupRecord(id: matchingGroup, name: "Productivity"),
                GroupRecord(id: otherGroup, name: "Utilities"),
            ]
        )

        XCTAssertEqual(results.map(\.item.id), ["included"])
        XCTAssertEqual(results.first?.matchedField, .group)
    }

    func testDuplicateGroupIDsUseFirstNameWithoutCrashing() {
        let groupID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let item = makeItem(id: "member", originalName: "Battery", groupIDs: [groupID])

        let results = SearchIndex.search(
            "productivity",
            in: [item],
            groups: [
                GroupRecord(id: groupID, name: "Productivity"),
                GroupRecord(id: groupID, name: "Utilities"),
            ]
        )

        XCTAssertEqual(results.map(\.item.id), ["member"])
        XCTAssertEqual(results.first?.matchedField, .group)
    }

    func testTiesUseFavoriteManualOrderDisplayNameThenStableID() {
        let items = [
            makeItem(id: "z", originalName: "Tool Zebra", isFavorite: false, manualOrder: 0),
            makeItem(id: "b", originalName: "Tool Same", isFavorite: true, manualOrder: 2),
            makeItem(id: "a", originalName: "Tool Same", isFavorite: true, manualOrder: 2),
            makeItem(id: "c", originalName: "Tool Alpha", isFavorite: true, manualOrder: 2),
            makeItem(id: "d", originalName: "Tool Delta", isFavorite: true, manualOrder: 1),
        ]

        let results = SearchIndex.search("tool", in: items)

        XCTAssertEqual(results.map(\.item.id), ["d", "c", "a", "b", "z"])
    }

    func testEmptyQueryReturnsStableDefaultOrderAndHonorsLimit() {
        let items = [
            makeItem(id: "b", originalName: "Beta", manualOrder: 0),
            makeItem(id: "favorite", originalName: "Zulu", isFavorite: true, manualOrder: 99),
            makeItem(id: "a", originalName: "Alpha", manualOrder: 0),
        ]

        let results = SearchIndex.search(" \n ", in: items, limit: 2)

        XCTAssertEqual(results.map(\.item.id), ["favorite", "a"])
        XCTAssertEqual(results.map(\.score), [0, 0])
        XCTAssertEqual(results.map(\.matchedField), [nil, nil])
        XCTAssertTrue(SearchIndex.search("a", in: items, limit: 0).isEmpty)
        XCTAssertTrue(SearchIndex.search("a", in: items, limit: -1).isEmpty)
    }

    func testDefaultLimitIsTwelveAndItemsConvenienceReturnsRecords() {
        let items = (0..<15).map {
            makeItem(id: String($0), originalName: "Match \($0)", manualOrder: $0)
        }

        XCTAssertEqual(SearchIndex.search("match", in: items).count, 12)
        XCTAssertEqual(SearchIndex.items(matching: "match", in: items).map(\.id), (0..<12).map(String.init))
    }

    private func makeItem(
        id: String,
        originalName: String,
        hostName: String = "Host",
        alias: String? = nil,
        isFavorite: Bool = false,
        groupIDs: [UUID] = [],
        manualOrder: Int = 0
    ) -> MenuBarItemRecord {
        MenuBarItemRecord(
            id: id,
            identity: MenuBarItemIdentity(
                bundleIdentifier: "com.example.\(id)",
                originalName: originalName,
                axIdentifier: id,
                path: [0]
            ),
            hostName: hostName,
            alias: alias,
            capability: .full,
            isFavorite: isFavorite,
            groupIDs: groupIDs,
            manualOrder: manualOrder,
            lastSeenAt: .distantPast
        )
    }
}

final class SearchIndexPerformanceTests: XCTestCase {
    func testAverageSearchLatencyForHundredRecordsIsUnderSixteenMilliseconds() {
        let groups = (0..<10).map { index in
            GroupRecord(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                name: "Productivity Group \(index)"
            )
        }
        let items = (0..<100).map { index in
            MenuBarItemRecord(
                id: "performance-\(index)",
                identity: MenuBarItemIdentity(
                    bundleIdentifier: "com.example.performance.\(index)",
                    originalName: index.isMultiple(of: 4) ? "Cloud Sync Agent \(index)" : "Utility Item \(index)",
                    axIdentifier: "performance-\(index)",
                    path: [index / 10, index % 10]
                ),
                hostName: "Example Host \(index % 8)",
                alias: index.isMultiple(of: 9) ? "Sync Shortcut \(index)" : nil,
                capability: .full,
                isFavorite: index.isMultiple(of: 11),
                groupIDs: [groups[index % groups.count].id],
                manualOrder: index,
                lastSeenAt: .distantPast
            )
        }

        _ = SearchIndex.search("sync", in: items, groups: groups)
        let iterations = 200
        var observedResultCount = 0
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            observedResultCount += SearchIndex.search("sync", in: items, groups: groups).count
        }
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        let averageSeconds = elapsedSeconds / Double(iterations)

        XCTAssertGreaterThan(observedResultCount, 0)
        XCTAssertLessThan(
            averageSeconds,
            0.016,
            "Average 100-record search took \(averageSeconds * 1_000)ms; target is below 16ms"
        )
    }
}
