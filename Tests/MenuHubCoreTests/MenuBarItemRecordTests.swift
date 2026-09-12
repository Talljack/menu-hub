import XCTest
@testable import MenuHubCore

final class MenuBarItemRecordTests: XCTestCase {
    func testStableIDIgnoresPIDPositionAndPathWhenAXIdentifierExists() {
        let a = MenuBarItemIdentity(
            processIdentifier: 41,
            bundleIdentifier: "com.example.app",
            originalName: "Sync",
            axIdentifier: "sync",
            path: [0, 2],
            position: .init(x: 1200, y: 0)
        )
        let b = MenuBarItemIdentity(
            processIdentifier: 99,
            bundleIdentifier: "com.example.app",
            originalName: "Renamed",
            axIdentifier: "sync",
            path: [9],
            position: .init(x: 800, y: 0)
        )

        XCTAssertEqual(a.stableID, b.stableID)
    }

    func testStableIDFallbackNormalizesOriginalNameDeterministically() {
        let a = MenuBarItemIdentity(
            processIdentifier: 1,
            bundleIdentifier: "com.example.app",
            originalName: "  CAFÉ\u{00a0}Status  ",
            axIdentifier: nil,
            path: [1]
        )
        let b = MenuBarItemIdentity(
            processIdentifier: 2,
            bundleIdentifier: "com.example.app",
            originalName: "cafe status",
            axIdentifier: nil,
            path: [8]
        )

        XCTAssertNotEqual(a.stableID, b.stableID)
        XCTAssertEqual(a.stableID, "com.example.app|name:cafe status|path:1")
        XCTAssertEqual(b.stableID, "com.example.app|name:cafe status|path:8")
    }

    func testFallbackDistinguishesSameBundleAndNameAtDifferentPaths() {
        let a = MenuBarItemIdentity(
            bundleIdentifier: "com.example.app",
            originalName: "Sync",
            axIdentifier: nil,
            path: [0, 2]
        )
        let b = MenuBarItemIdentity(
            bundleIdentifier: "com.example.app",
            originalName: "Sync",
            axIdentifier: nil,
            path: [0, 3]
        )

        XCTAssertNotEqual(a.stableID, b.stableID)
    }

    func testAXIdentifierIsOpaqueAndCaseAndAccentDifferencesRemainDistinct() {
        let uppercase = MenuBarItemIdentity(
            bundleIdentifier: "com.example.app",
            originalName: "Sync",
            axIdentifier: "CAFÉ",
            path: [0]
        )
        let lowercase = MenuBarItemIdentity(
            bundleIdentifier: "com.example.app",
            originalName: "Sync",
            axIdentifier: "cafe",
            path: [0]
        )

        XCTAssertNotEqual(uppercase.stableID, lowercase.stableID)
    }

    func testBlankAXIdentifierUsesNameAndPathFallback() {
        let identity = MenuBarItemIdentity(
            bundleIdentifier: "com.example.app",
            originalName: "Sync",
            axIdentifier: " \n ",
            path: [4, 1]
        )

        XCTAssertEqual(identity.stableID, "com.example.app|name:sync|path:4.1")
    }

    func testBlankAliasFallsBackToOriginalName() {
        let record = makeRecord(alias: "  \n ")

        XCTAssertEqual(record.displayName, "Sync")
    }

    func testLaunchOnlyCapabilityHasValidFallback() {
        XCTAssertEqual(
            ItemCapability.classify(hasName: true, actions: [], canLaunchHost: true),
            .launchOnly
        )
    }

    func testEmptyDocumentUsesSchemaVersionOneAndDefaultPreferences() {
        let document = CatalogDocument.empty

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertTrue(document.items.isEmpty)
        XCTAssertTrue(document.groups.isEmpty)
        XCTAssertEqual(document.preferences.hotKey, .default)
        XCTAssertEqual(document.preferences.hotKey.keyCode, 46)
        XCTAssertEqual(document.preferences.hotKey.modifiers, [.option])
    }

    func testCatalogDocumentCodableRoundTripPreservesAllModelFields() throws {
        let groupID = UUID(uuidString: "A3D49F5C-3B46-47F5-B6A7-AB8681732F48")!
        var record = makeRecord(alias: "Work Sync")
        record.isFavorite = true
        record.groupIDs = [groupID]
        record.isIgnored = true
        record.successfulInvocations = [Date(timeIntervalSince1970: 100)]
        record.lastError = .targetUnresponsive

        let document = CatalogDocument(
            items: [record],
            groups: [GroupRecord(id: groupID, name: "Work", manualOrder: 2)],
            preferences: Preferences(
                appearance: .dark,
                language: .english,
                hotKey: HotKeyPreference(keyCode: 12, modifiers: [.command, .shift]),
                launchAtLogin: true,
                restoreHiddenState: true,
                closeOnFocusLoss: false,
                closeAfterSuccessfulTrigger: false,
                automaticScanning: false,
                showGroupHeadings: false,
                showCapabilities: true,
                layout: .grid
            )
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(CatalogDocument.self, from: data)

        XCTAssertEqual(decoded, document)
    }

    func testRecordDecodesLegacyJSONWithoutHostBundleIdentifier() throws {
        var record = makeRecord(alias: nil)
        record.hostBundleIdentifier = "com.example.outer"
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "hostBundleIdentifier")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(MenuBarItemRecord.self, from: legacyData)

        XCTAssertNil(decoded.hostBundleIdentifier)
        XCTAssertEqual(decoded.identity.bundleIdentifier, "com.example.app")
    }

    func testRecordDecodesLegacyJSONWithoutUnreadBadgePreferenceAsAutomatic() throws {
        var record = makeRecord(alias: nil)
        record.unreadBadgePreference = .include
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "unreadBadgePreference")

        let decoded = try JSONDecoder().decode(
            MenuBarItemRecord.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.unreadBadgePreference, .automatic)
    }

    func testRecordDecodesUnknownUnreadBadgePreferenceAsAutomatic() throws {
        let encoded = try JSONEncoder().encode(makeRecord(alias: nil))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["unreadBadgePreference"] = "future-policy"

        let decoded = try JSONDecoder().decode(
            MenuBarItemRecord.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.unreadBadgePreference, .automatic)
    }

    private func makeRecord(alias: String?) -> MenuBarItemRecord {
        let identity = MenuBarItemIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.example.app",
            originalName: "Sync",
            axIdentifier: "sync",
            path: [0, 2],
            position: .init(x: 1200, y: 0)
        )
        return MenuBarItemRecord(
            identity: identity,
            hostName: "Example",
            alias: alias,
            capability: .full,
            isFavorite: false,
            groupIDs: [],
            manualOrder: 3,
            lastSeenAt: Date(timeIntervalSince1970: 50),
            successfulInvocations: [],
            lastError: nil,
            isIgnored: false
        )
    }
}
