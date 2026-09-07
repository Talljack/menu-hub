import Foundation

public enum SearchMatchedField: String, Equatable, Sendable {
    case alias
    case name
    case host
    case group
}

public struct SearchResult: Equatable, Sendable {
    public let item: MenuBarItemRecord
    public let score: Int
    public let matchedField: SearchMatchedField?

    public init(item: MenuBarItemRecord, score: Int, matchedField: SearchMatchedField?) {
        self.item = item
        self.score = score
        self.matchedField = matchedField
    }
}

public enum SearchIndex {
    public static let defaultLimit = 12

    /// Searches items using their fields and group memberships.
    /// If `groups` contains duplicate IDs, the first name in input order is used.
    public static func search(
        _ query: String,
        in items: [MenuBarItemRecord],
        groups: [GroupRecord] = [],
        limit: Int = defaultLimit
    ) -> [SearchResult] {
        var groupNamesByID: [UUID: String] = [:]
        for group in groups where groupNamesByID[group.id] == nil {
            groupNamesByID[group.id] = group.name
        }
        return search(query, in: items, groupNamesByID: groupNamesByID, limit: limit)
    }

    public static func search(
        _ query: String,
        in items: [MenuBarItemRecord],
        groupNamesByID: [UUID: String],
        limit: Int = defaultLimit
    ) -> [SearchResult] {
        guard limit > 0 else { return [] }
        let normalizedQuery = normalize(query)

        let results: [SearchResult]
        if normalizedQuery.isEmpty {
            results = items.map { SearchResult(item: $0, score: 0, matchedField: nil) }
        } else {
            results = items.compactMap { item in
                bestMatch(
                    for: item,
                    query: normalizedQuery,
                    groupNamesByID: groupNamesByID
                )
            }
        }

        return Array(results.sorted(by: resultComesFirst).prefix(limit))
    }

    public static func items(
        matching query: String,
        in items: [MenuBarItemRecord],
        groups: [GroupRecord] = [],
        limit: Int = defaultLimit
    ) -> [MenuBarItemRecord] {
        search(query, in: items, groups: groups, limit: limit).map(\.item)
    }

    private static func bestMatch(
        for item: MenuBarItemRecord,
        query: String,
        groupNamesByID: [UUID: String]
    ) -> SearchResult? {
        var candidates: [(score: Int, field: SearchMatchedField)] = []

        if let alias = item.alias, !normalize(alias).isEmpty {
            let normalizedAlias = normalize(alias)
            if normalizedAlias == query {
                candidates.append((700, .alias))
            } else if let score = nameMatchScore(normalizedAlias, query: query) {
                candidates.append((score, .alias))
            }
        }

        let normalizedOriginalName = normalize(item.identity.originalName)
        if normalizedOriginalName == query {
            candidates.append((600, .name))
        } else if let score = nameMatchScore(normalizedOriginalName, query: query) {
            candidates.append((score, .name))
        }

        if normalize(item.hostName).contains(query) {
            candidates.append((200, .host))
        }

        if item.groupIDs.contains(where: { groupID in
            groupNamesByID[groupID].map { normalize($0).contains(query) } ?? false
        }) {
            candidates.append((100, .group))
        }

        guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }
        return SearchResult(item: item, score: best.score, matchedField: best.field)
    }

    private static func nameMatchScore(_ value: String, query: String) -> Int? {
        if value.hasPrefix(query) { return 500 }
        if value.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 400 }
        if value.contains(query) { return 300 }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func resultComesFirst(_ lhs: SearchResult, _ rhs: SearchResult) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.item.isFavorite != rhs.item.isFavorite { return lhs.item.isFavorite }
        if lhs.item.manualOrder != rhs.item.manualOrder {
            return lhs.item.manualOrder < rhs.item.manualOrder
        }
        let nameComparison = lhs.item.displayName.localizedStandardCompare(rhs.item.displayName)
        if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
        return lhs.item.id < rhs.item.id
    }
}
