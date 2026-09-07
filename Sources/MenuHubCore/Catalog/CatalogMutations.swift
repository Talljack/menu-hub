import Foundation

public extension CatalogDocument {
    @discardableResult
    mutating func createGroup(name: String) -> GroupRecord {
        let group = GroupRecord(name: name.trimmingCharacters(in: .whitespacesAndNewlines), manualOrder: groups.count)
        groups.append(group)
        return group
    }

    @discardableResult
    mutating func renameGroup(id: UUID, name: String) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        groups[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    mutating func reorderGroups(groupIDs: [UUID]) {
        let ordered = normalizedIDs(groupIDs, followedBy: groups.sorted(by: groupOrder).map(\.id))
        for (order, id) in ordered.enumerated() {
            groups[groups.firstIndex(where: { $0.id == id })!].manualOrder = order
        }
    }

    @discardableResult
    mutating func deleteGroup(id: UUID) -> Bool {
        guard groups.contains(where: { $0.id == id }) else { return false }
        groups.removeAll { $0.id == id }
        for index in items.indices { items[index].groupIDs.removeAll { $0 == id } }
        reorderGroups(groupIDs: groups.sorted(by: groupOrder).map(\.id))
        return true
    }

    @discardableResult
    mutating func setAlias(_ alias: String?, forItemID itemID: String) -> Bool {
        mutateItem(id: itemID) { item in
            let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
            item.alias = trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    @discardableResult
    mutating func setFavorite(_ favorite: Bool, forItemID itemID: String) -> Bool {
        mutateItem(id: itemID) { $0.isFavorite = favorite }
    }

    @discardableResult
    mutating func setIgnored(_ ignored: Bool, forItemID itemID: String) -> Bool {
        mutateItem(id: itemID) { $0.isIgnored = ignored }
    }

    @discardableResult
    mutating func setMembership(_ member: Bool, itemID: String, groupID: UUID) -> Bool {
        guard groups.contains(where: { $0.id == groupID }),
              let index = items.firstIndex(where: { $0.id == itemID }) else { return false }
        let contains = items[index].groupIDs.contains(groupID)
        guard contains != member else { return false }
        if member { items[index].groupIDs.append(groupID) }
        else { items[index].groupIDs.removeAll { $0 == groupID } }
        return true
    }

    mutating func reorderItems(itemIDs: [String]) {
        let ordered = normalizedIDs(itemIDs, followedBy: items.sorted(by: itemOrder).map(\.id))
        for (order, id) in ordered.enumerated() {
            items[items.firstIndex(where: { $0.id == id })!].manualOrder = order
        }
    }

    @discardableResult
    mutating func recordSuccessfulInvocation(forItemID itemID: String, at date: Date, now: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return false }
        return items[index].recordSuccessfulInvocation(at: date, now: now)
    }

    @discardableResult
    mutating func recordError(_ error: AccessibilityDomainError?, forItemID itemID: String) -> Bool {
        mutateItem(id: itemID) { $0.lastError = error }
    }

    private mutating func mutateItem(id: String, _ mutation: (inout MenuBarItemRecord) -> Void) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&items[index])
        return true
    }

    private func normalizedIDs<ID: Hashable>(_ requested: [ID], followedBy fallback: [ID]) -> [ID] {
        let known = Set(fallback)
        var seen = Set<ID>()
        return (requested + fallback).filter { known.contains($0) && seen.insert($0).inserted }
    }

    private func groupOrder(_ lhs: GroupRecord, _ rhs: GroupRecord) -> Bool {
        lhs.manualOrder == rhs.manualOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.manualOrder < rhs.manualOrder
    }

    private func itemOrder(_ lhs: MenuBarItemRecord, _ rhs: MenuBarItemRecord) -> Bool {
        lhs.manualOrder == rhs.manualOrder ? lhs.id < rhs.id : lhs.manualOrder < rhs.manualOrder
    }
}

public extension MenuBarItemRecord {
    /// Stores every genuine success. SmartGroupEngine applies its 30-second
    /// coalescing window when deriving Frequent, preserving raw audit history.
    @discardableResult
    mutating func recordSuccessfulInvocation(at date: Date, now: Date = Date()) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              now.timeIntervalSinceReferenceDate.isFinite,
              date <= now else { return false }
        successfulInvocations.append(date)
        return true
    }
}

public struct CatalogReconciliationResult: Equatable, Sendable {
    public let runtimeSnapshots: [String: AccessibilitySnapshot]
    public let duplicateStableIDs: Set<String>

    public init(runtimeSnapshots: [String: AccessibilitySnapshot], duplicateStableIDs: Set<String>) {
        self.runtimeSnapshots = runtimeSnapshots
        self.duplicateStableIDs = duplicateStableIDs
    }
}

public enum DynamicStatusTitle {
    public static func canTransition(from oldValue: String, to newValue: String) -> Bool {
        let old = analyzed(oldValue)
        let new = analyzed(newValue)
        return old.hasDigit && new.hasDigit && old.skeleton == new.skeleton
    }

    private static func analyzed(_ value: String) -> (hasDigit: Bool, skeleton: String) {
        var hasDigit = false
        let ignoredBadgeCharacters = CharacterSet(charactersIn: "()[]{}（）【】")
        let skeleton = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            if CharacterSet.decimalDigits.contains(scalar) { hasDigit = true; return nil }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || ignoredBadgeCharacters.contains(scalar) { return nil }
            return scalar
        }.map(String.init).joined()
        return (hasDigit, skeleton)
    }
}

public enum CatalogReconciler {
    @discardableResult
    public static func reconcile(
        _ document: inout CatalogDocument,
        snapshots: [AccessibilitySnapshot],
        at date: Date = Date(),
        canLaunchHost: @Sendable (String) -> Bool
    ) -> CatalogReconciliationResult {
        let candidates = snapshots.filter(isVisibleCandidate)
        let grouped = Dictionary(grouping: candidates, by: { $0.menuBarItemIdentity.stableID })
        let duplicateIDs = Set(grouped.compactMap { $0.value.count > 1 ? $0.key : nil })
        let uniqueSnapshots = grouped.values.compactMap { $0.count == 1 ? $0[0] : nil }
        let incomingSecondaryCounts = Dictionary(grouping: uniqueSnapshots, by: secondaryFingerprint).mapValues(\.count)
        var runtime: [String: AccessibilitySnapshot] = [:]

        for stableID in grouped.keys.sorted() {
            guard let matches = grouped[stableID] else { continue }
            guard matches.count == 1 else { continue }
            let snapshot = matches.sorted(by: snapshotOrder).first!
            let identity = snapshot.menuBarItemIdentity
            let launchable = snapshot.bundleIdentifier.flatMap { bundleIdentifier -> Bool? in
                let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : canLaunchHost(trimmed)
            } ?? false
            let capability = ItemCapability.classify(
                hasName: !(snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                actions: snapshot.actions,
                canLaunchHost: launchable
            )

            let exactIndex = document.items.firstIndex(where: { $0.identity.stableID == stableID })
            let secondary = secondaryFingerprint(snapshot)
            let secondaryIndices = document.items.indices.filter {
                document.items[$0].identity.axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                    && secondaryFingerprint(document.items[$0].identity) == secondary
            }
            let transitioningIndices = secondaryIndices.filter {
                DynamicStatusTitle.canTransition(
                    from: document.items[$0].identity.originalName,
                    to: identity.originalName
                )
            }
            // Title-only status items (notification badges are the common case) used
            // to accumulate one persisted record per value. Once two records prove
            // that a single bundle/path is dynamic, collapse that history back to one
            // canonical record and retain all user-owned metadata.
            let shouldConsolidateDynamicHistory = incomingSecondaryCounts[secondary] == 1
                && secondaryIndices.count > 1
                && (transitioningIndices.count >= 2 || (exactIndex != nil && !transitioningIndices.isEmpty))
            let dynamicIndex: Int? = {
                guard identity.axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                      incomingSecondaryCounts[secondary] == 1,
                      secondaryIndices.count == 1,
                      let index = secondaryIndices.first,
                      DynamicStatusTitle.canTransition(
                          from: document.items[index].identity.originalName,
                          to: identity.originalName
                      ) else { return nil }
                return index
            }()

            let consolidatedIndex = shouldConsolidateDynamicHistory
                ? preferredRecordIndex(in: secondaryIndices, items: document.items)
                : nil
            if let index = consolidatedIndex ?? exactIndex ?? dynamicIndex {
                let retainedID = document.items[index].id
                if shouldConsolidateDynamicHistory {
                    mergeUserMetadata(into: &document.items[index], from: secondaryIndices.map { document.items[$0] })
                }
                document.items[index].identity = identity
                document.items[index].hostName = snapshot.processName
                document.items[index].capability = capability
                document.items[index].lastSeenAt = date
                document.items[index].lastError = nil
                if shouldConsolidateDynamicHistory {
                    document.items.removeAll {
                        $0.id != retainedID
                            && $0.identity.axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                            && secondaryFingerprint($0.identity) == secondary
                    }
                }
                runtime[retainedID] = snapshot
            } else {
                let nextOrder = (document.items.map(\.manualOrder).max() ?? -1) + 1
                let record = MenuBarItemRecord(
                    identity: identity,
                    hostName: snapshot.processName,
                    capability: capability,
                    manualOrder: nextOrder,
                    lastSeenAt: date,
                    lastError: nil
                )
                document.items.append(record)
                runtime[record.id] = snapshot
            }
        }
        return CatalogReconciliationResult(runtimeSnapshots: runtime, duplicateStableIDs: duplicateIDs)
    }

    private static func isVisibleCandidate(_ snapshot: AccessibilitySnapshot) -> Bool {
        guard snapshot.bundleIdentifier != "com.local.MenuHub",
              MenuBarCandidatePolicy.isCandidate(role: snapshot.role, subrole: snapshot.subrole, actions: snapshot.actions),
              (snapshot.width ?? 1) > 0,
              (snapshot.height ?? 1) > 0 else { return false }
        let hasName = !(snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasName || snapshot.processName != "Control Center"
    }

    private static func snapshotOrder(_ lhs: AccessibilitySnapshot, _ rhs: AccessibilitySnapshot) -> Bool {
        let l = [lhs.bundleIdentifier ?? "", lhs.processName, lhs.title ?? "", lhs.identifier ?? "", lhs.accessibilityPath.map(String.init).joined(separator: "."), String(lhs.positionX ?? -.infinity)].joined(separator: "|")
        let r = [rhs.bundleIdentifier ?? "", rhs.processName, rhs.title ?? "", rhs.identifier ?? "", rhs.accessibilityPath.map(String.init).joined(separator: "."), String(rhs.positionX ?? -.infinity)].joined(separator: "|")
        return l < r
    }

    private static func secondaryFingerprint(_ snapshot: AccessibilitySnapshot) -> String {
        secondaryFingerprint(snapshot.menuBarItemIdentity)
    }

    private static func secondaryFingerprint(_ identity: MenuBarItemIdentity) -> String {
        let bundle = identity.bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return bundle + "|path:" + identity.path.map(String.init).joined(separator: ".")
    }

    private static func preferredRecordIndex(in indices: [Int], items: [MenuBarItemRecord]) -> Int? {
        indices.min { lhs, rhs in
            let left = items[lhs]
            let right = items[rhs]
            let leftScore = customizationScore(left)
            let rightScore = customizationScore(right)
            if leftScore != rightScore { return leftScore > rightScore }
            if left.lastSeenAt != right.lastSeenAt { return left.lastSeenAt > right.lastSeenAt }
            if left.manualOrder != right.manualOrder { return left.manualOrder < right.manualOrder }
            return left.id < right.id
        }
    }

    private static func customizationScore(_ item: MenuBarItemRecord) -> Int {
        (item.alias == nil ? 0 : 8)
            + (item.isFavorite ? 4 : 0)
            + (item.groupIDs.isEmpty ? 0 : 2)
            + (item.successfulInvocations.isEmpty ? 0 : 1)
    }

    private static func mergeUserMetadata(into retained: inout MenuBarItemRecord, from records: [MenuBarItemRecord]) {
        if retained.alias == nil {
            retained.alias = records.compactMap(\.alias).first
        }
        retained.isFavorite = records.contains(where: \.isFavorite)
        retained.isIgnored = records.contains(where: \.isIgnored)
        retained.groupIDs = Array(Set(records.flatMap(\.groupIDs))).sorted { $0.uuidString < $1.uuidString }
        retained.successfulInvocations = Array(Set(records.flatMap(\.successfulInvocations))).sorted()
        retained.manualOrder = records.map(\.manualOrder).min() ?? retained.manualOrder
        retained.lastError = retained.lastError ?? records.compactMap(\.lastError).first
    }
}
