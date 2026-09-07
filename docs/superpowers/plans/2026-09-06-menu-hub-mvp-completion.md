# Menu Hub MVP Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the approved Menu Hub MVP, including durable catalog organization, progressive Accessibility authorization, native inset-group UI, bilingual resources, management/settings, diagnostics, and local release validation.

**Architecture:** Keep the Phase 0 spacer and Accessibility probe as preserved evidence while moving product behavior into protocol-backed `MenuHubCore` services. The menu-bar target composes those services on the main actor; background actors perform scanning and persistence, and SwiftUI views render immutable state snapshots.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ApplicationServices Accessibility, Carbon hot keys, ServiceManagement, XCTest, XcodeGen, macOS 14+

---

## File Structure

Create focused feature files instead of expanding `AppDelegate.swift` and `HubPanelView.swift`:

- `Sources/MenuHubCore/Catalog/MenuBarItemRecord.swift`: stable item model, capability and user metadata.
- `Sources/MenuHubCore/Catalog/CatalogDocument.swift`: schema version and preferences envelope.
- `Sources/MenuHubCore/Catalog/CatalogStore.swift`: versioned atomic JSON and backup recovery.
- `Sources/MenuHubCore/Search/SearchIndex.swift`: normalized scoring and stable ordering.
- `Sources/MenuHubCore/Groups/SmartGroupEngine.swift`: Recent and Frequent derivation.
- `Sources/MenuHubCore/Permissions/PermissionState.swift`: pure permission state machine.
- `Sources/MenuHubCore/Actions/ActionPolicy.swift`: Press/Open App/Unavailable selection.
- `Sources/MenuHubCore/Diagnostics/DiagnosticArchive.swift`: bounded redacted diagnostic export model.
- `Sources/MenuHub/PermissionCoordinator.swift`: live AX checks and app-activation transitions.
- `Sources/MenuHub/HotKeyController.swift`: configurable conflict-safe Carbon registration.
- `Sources/MenuHub/HubPanelModel.swift`: panel state and orchestration.
- `Sources/MenuHub/HubPanelView.swift`: fixed header/footer and safe scrolling content.
- `Sources/MenuHub/HubItemRow.swift`: compact accessible row with hover and selection.
- `Sources/MenuHub/ManagementWindow.swift`: item/group editor window.
- `Sources/MenuHub/SettingsView.swift`: six settings sections and launch-at-login.
- `Sources/MenuHub/OnboardingView.swift`: permission and setup flow.
- `Sources/MenuHub/AppDelegate.swift`: application composition and status-item routing only.
- `Resources/en.lproj/Localizable.strings`: English UI.
- `Resources/zh-Hans.lproj/Localizable.strings`: Simplified Chinese UI.
- `Tests/MenuHubCoreTests/MenuBarItemRecordTests.swift`, `CatalogStoreTests.swift`, `SearchIndexTests.swift`, `SmartGroupEngineTests.swift`, `PermissionStateTests.swift`, `ActionPolicyTests.swift`, `AccessibilityPipelineTests.swift`, `HotKeyDescriptorTests.swift`, `CatalogMutationTests.swift`, `PanelNavigationTests.swift`, `OnboardingPolicyTests.swift`, `LocalizationCompletenessTests.swift`, and `DiagnosticRedactionTests.swift`: pure and fake-backed coverage for the new core services.

The existing `AccessibilityClient` remains the production adapter. It gains protocol conformance and bounded calls but does not absorb catalog, ranking, or UI responsibilities.

---

### Task 1: Catalog Identity and Capability Model

**Files:**
- Create: `Sources/MenuHubCore/Catalog/MenuBarItemRecord.swift`
- Create: `Sources/MenuHubCore/Catalog/CatalogDocument.swift`
- Create: `Tests/MenuHubCoreTests/MenuBarItemRecordTests.swift`

- [ ] **Step 1: Write the failing identity and capability tests**

```swift
import XCTest
@testable import MenuHubCore

final class MenuBarItemRecordTests: XCTestCase {
    func testStableIDIgnoresPIDAndPosition() {
        let a = MenuBarItemIdentity(bundleIdentifier: "com.example.app", originalName: "Sync", axIdentifier: "sync", path: [0, 2])
        let b = MenuBarItemIdentity(bundleIdentifier: "com.example.app", originalName: "Sync", axIdentifier: "sync", path: [9])
        XCTAssertEqual(a.stableID, b.stableID)
    }

    func testLaunchOnlyCapabilityHasValidFallback() {
        XCTAssertEqual(ItemCapability.classify(hasName: true, actions: [], canLaunchHost: true), .launchOnly)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `swift test --filter MenuBarItemRecordTests`

Expected: compilation fails because `MenuBarItemIdentity` and `MenuBarItemRecord` do not exist.

- [ ] **Step 3: Implement Codable and Sendable catalog types**

```swift
public struct MenuBarItemIdentity: Codable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let originalName: String
    public let axIdentifier: String?
    public let path: [Int]

    public var stableID: String {
        [bundleIdentifier, axIdentifier ?? originalName].joined(separator: "|")
    }
}

public struct MenuBarItemRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var identity: MenuBarItemIdentity
    public var hostName: String
    public var alias: String?
    public var capability: ItemCapability
    public var isFavorite: Bool
    public var groupIDs: [UUID]
    public var manualOrder: Int
    public var lastSeenAt: Date
    public var successfulInvocations: [Date]
    public var lastError: AccessibilityDomainError?

    public var displayName: String { alias?.nilIfBlank ?? identity.originalName }
}
```

Add `GroupRecord`, `AppearancePreference`, `LanguagePreference`, `HotKeyPreference`, and `CatalogDocument(schemaVersion:items:groups:preferences:)` with public memberwise initializers. Keep schema version `1`.

- [ ] **Step 4: Run all core tests**

Run: `swift test`

Expected: all existing tests and `MenuBarItemRecordTests` pass.

- [ ] **Step 5: Record checkpoint**

This workspace is not a Git repository. Record the completed task in this plan and keep the build green; do not initialize Git without user authorization.

---

### Task 2: Versioned Atomic Catalog Persistence

**Files:**
- Create: `Sources/MenuHubCore/Catalog/CatalogStore.swift`
- Create: `Tests/MenuHubCoreTests/CatalogStoreTests.swift`

- [ ] **Step 1: Write async round-trip and backup-recovery tests**

```swift
final class CatalogStoreTests: XCTestCase {
    func testRoundTripUsesVersionedDocument() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = CatalogStore(directory: directory)
        let document = CatalogDocument.empty
        try await store.save(document)
        XCTAssertEqual(try await store.load(), document)
    }

    func testCorruptPrimaryRecoversBackup() async throws {
        let fixture = try CatalogStoreFixture.makeWithBackup()
        try Data("broken".utf8).write(to: fixture.primary)
        XCTAssertEqual(try await fixture.store.load(), fixture.expected)
    }
}
```

- [ ] **Step 2: Verify focused tests fail**

Run: `swift test --filter CatalogStoreTests`

Expected: compilation fails because `CatalogStore` is missing.

- [ ] **Step 3: Implement actor-isolated storage**

```swift
public actor CatalogStore {
    private let directory: URL
    private var primary: URL { directory.appending(path: "catalog-v1.json") }
    private var backup: URL { directory.appending(path: "catalog-v1.backup.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> CatalogDocument {
        do { return try decode(primary) }
        catch {
            guard FileManager.default.fileExists(atPath: backup.path) else { throw error }
            return try decode(backup)
        }
    }

    public func save(_ document: CatalogDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.menuHub.encode(document)
        if FileManager.default.fileExists(atPath: primary.path) {
            _ = try FileManager.default.replaceItemAt(backup, withItemAt: primary)
        }
        let temporary = directory.appending(path: "catalog-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(primary, withItemAt: temporary)
    }
}
```

Implement first-save handling, ISO-8601 date strategies, unsupported-schema rejection, explicit migration entry point, and reliable cleanup of temporary files.

- [ ] **Step 4: Run persistence tests and the full suite**

Run: `swift test --filter CatalogStoreTests && swift test`

Expected: both commands exit successfully.

---

### Task 3: Search and Smart Groups

**Files:**
- Create: `Sources/MenuHubCore/Search/SearchIndex.swift`
- Create: `Sources/MenuHubCore/Groups/SmartGroupEngine.swift`
- Create: `Tests/MenuHubCoreTests/SearchIndexTests.swift`
- Create: `Tests/MenuHubCoreTests/SmartGroupEngineTests.swift`

- [ ] **Step 1: Write ranking, recent, and frequency tests**

```swift
func testExactAliasOutranksPrefixAndHostMatches() {
    let results = SearchIndex.search("chat", in: fixtures)
    XCTAssertEqual(results.map(\.id), ["alias-exact", "name-prefix", "host-contains"])
}

func testFrequentRequiresThreeSuccessesAndDeduplicatesThirtySeconds() {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let engine = SmartGroupEngine(now: { now })
    XCTAssertEqual(engine.frequent(from: frequencyFixtures).map(\.id), ["qualified"])
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter SearchIndexTests && swift test --filter SmartGroupEngineTests`

Expected: missing-type compilation failures.

- [ ] **Step 3: Implement deterministic ranking and group rules**

```swift
public enum SearchIndex {
    public static func search(_ query: String, in items: [MenuBarItemRecord], limit: Int = 12) -> [MenuBarItemRecord] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return Array(items.prefix(limit)) }
        return items.compactMap { item in score(item, needle: needle).map { ($0, item) } }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.manualOrder < $1.1.manualOrder }
            .prefix(limit).map(\.1)
    }
}

public struct SmartGroupEngine: Sendable {
    public var now: @Sendable () -> Date
    public func recent(from items: [MenuBarItemRecord]) -> [MenuBarItemRecord] {
        let cutoff = now().addingTimeInterval(-14 * 86_400)
        return items.filter { ($0.successfulInvocations.max() ?? .distantPast) >= cutoff }
            .sorted { ($0.successfulInvocations.max() ?? .distantPast) > ($1.successfulInvocations.max() ?? .distantPast) }
            .prefix(8).map { $0 }
    }

    public func frequent(from items: [MenuBarItemRecord]) -> [MenuBarItemRecord] {
        let cutoff = now().addingTimeInterval(-30 * 86_400)
        return items.compactMap { item -> (MenuBarItemRecord, Int)? in
            let ordered = item.successfulInvocations.filter { $0 >= cutoff }.sorted()
            let deduplicated = ordered.reduce(into: [Date]()) { kept, date in
                if kept.last.map({ date.timeIntervalSince($0) >= 30 }) ?? true { kept.append(date) }
            }
            return deduplicated.count >= 3 ? (item, deduplicated.count) : nil
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.displayName.localizedStandardCompare($1.0.displayName) == .orderedAscending }
        .map(\.0)
    }
}
```

Implement Unicode case/diacritic/width normalization. Score exact alias, exact name, prefix, word prefix, substring, host, and group in that order. Resolve ties by favorite, manual order, localized standard name, then stable ID.

- [ ] **Step 4: Add the 100-item performance measure and run tests**

Run: `swift test`

Expected: all tests pass; the release XCTest measure for 100 items remains below 16 ms on the local Mac.

---

### Task 4: Permission and Action State Machines

**Files:**
- Create: `Sources/MenuHubCore/Permissions/PermissionState.swift`
- Create: `Sources/MenuHubCore/Actions/ActionPolicy.swift`
- Create: `Tests/MenuHubCoreTests/PermissionStateTests.swift`
- Create: `Tests/MenuHubCoreTests/ActionPolicyTests.swift`

- [ ] **Step 1: Write pure transition and fallback tests**

```swift
func testReturningAuthorizedStartsScanWithoutPromptingAgain() {
    var machine = PermissionStateMachine(state: .awaitingSystemChange)
    XCTAssertEqual(machine.handle(.applicationBecameActive(isTrusted: true)), [.setAuthorized, .scan])
}

func testMissingPressFallsBackToHostLaunch() {
    XCTAssertEqual(ActionPolicy.defaultAction(capability: .launchOnly), .openHostApplication)
}
```

- [ ] **Step 2: Verify focused tests fail**

Run: `swift test --filter PermissionStateTests && swift test --filter ActionPolicyTests`

Expected: missing-type compilation failures.

- [ ] **Step 3: Implement explicit states and actions**

```swift
public enum PermissionState: Equatable, Sendable { case unknown, explanation, awaitingSystemChange, authorized, denied, repairRequired }
public enum PermissionEvent: Equatable, Sendable { case featureRequested, openedSettings, applicationBecameActive(isTrusted: Bool), operationDenied }
public enum PermissionEffect: Equatable, Sendable { case showExplanation, openSettings, setAuthorized, setDenied, offerRepair, scan }
public enum ItemDefaultAction: Equatable, Sendable { case press, openHostApplication, unavailable }
```

The reducer must never emit a system prompt on launch. `operationDenied` after a previously authorized state emits `setDenied` and `offerRepair`.

- [ ] **Step 4: Run all tests**

Run: `swift test`

Expected: all tests pass.

---

### Task 5: Protocol-Backed Scanner, Resolver, and Executor

**Files:**
- Modify: `Sources/MenuHubCore/Accessibility/AccessibilityClient.swift`
- Create: `Sources/MenuHubCore/Accessibility/AccessibilityServing.swift`
- Create: `Sources/MenuHubCore/Actions/ActionExecutor.swift`
- Create: `Tests/MenuHubCoreTests/AccessibilityPipelineTests.swift`

- [ ] **Step 1: Write fake-backed integration cases**

```swift
actor FakeAccessibilityClient: AccessibilityServing {
    var result: AccessibilityScanResult
    var pressResult: Result<Void, AccessibilityDomainError>
    func scan() async -> AccessibilityScanResult { result }
    func press(_ snapshot: AccessibilitySnapshot) async -> Result<Void, AccessibilityDomainError> { pressResult }
}

func testStaleElementTriggersOneRescanAndRetry() async {
    let fake = FakeAccessibilityClient(staleThenSuccess: true)
    let result = await ActionExecutor(accessibility: fake, launcher: FakeLauncher()).execute(fixture)
    XCTAssertEqual(result, .pressed)
    XCTAssertEqual(await fake.scanCount, 1)
}
```

- [ ] **Step 2: Verify pipeline tests fail**

Run: `swift test --filter AccessibilityPipelineTests`

Expected: protocol and executor are missing.

- [ ] **Step 3: Add protocol conformance and bounded execution**

```swift
public protocol AccessibilityServing: Sendable {
    func scan() async -> AccessibilityScanResult
    func press(_ snapshot: AccessibilitySnapshot) async -> Result<Void, AccessibilityDomainError>
}

public protocol ApplicationLaunching: Sendable {
    func open(bundleIdentifier: String) async -> Bool
}

public enum ActionOutcome: Equatable, Sendable { case pressed, openedHost, unavailable, failed(AccessibilityDomainError) }
```

Adapt `AccessibilityClient` without private APIs. Re-resolve stale elements once, cap each action attempt, map all `AXError` values, and use `NSWorkspace` only through the launcher adapter.

- [ ] **Step 4: Run integration and full tests**

Run: `swift test --filter AccessibilityPipelineTests && swift test`

Expected: all tests pass.

---

### Task 6: Configurable Option-M Global Shortcut

**Files:**
- Modify: `Sources/MenuHub/HotKeyController.swift`
- Create: `Sources/MenuHubCore/HotKeys/HotKeyDescriptor.swift`
- Create: `Tests/MenuHubCoreTests/HotKeyDescriptorTests.swift`

- [ ] **Step 1: Write validation tests**

```swift
func testDefaultShortcutIsOptionM() {
    XCTAssertEqual(HotKeyDescriptor.default, .init(keyCode: 46, modifiers: [.option]))
}

func testBareLetterAndBareModifierAreRejected() {
    XCTAssertFalse(HotKeyDescriptor(keyCode: 46, modifiers: []).isValid)
    XCTAssertFalse(HotKeyDescriptor(keyCode: nil, modifiers: [.option]).isValid)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter HotKeyDescriptorTests`

Expected: `HotKeyDescriptor` is missing.

- [ ] **Step 3: Implement descriptor and transactional registration**

```swift
public struct HotKeyDescriptor: Codable, Equatable, Sendable {
    public var keyCode: UInt32?
    public var modifiers: Set<HotKeyModifier>
    public static let `default` = Self(keyCode: 46, modifiers: [.option])
    public var isValid: Bool { keyCode != nil && !modifiers.isEmpty }
}
```

Change `HotKeyController.register(_:)` to register a candidate before unregistering the existing reference. Treat `eventHotKeyExistsErr` as a localized conflict and keep the previous active shortcut. Unregister references in `deinit`.

- [ ] **Step 4: Run tests and verify exclusive registration manually**

Run: `swift test && xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Debug build`

Expected: tests and build pass; a second `⌥M` registration returns a conflict without disabling the first registration.

---

### Task 7: Durable Panel Model and Catalog Editing

**Files:**
- Replace: `Sources/MenuHub/HubPanelModel.swift`
- Create: `Sources/MenuHub/CatalogController.swift`
- Create: `Tests/MenuHubCoreTests/CatalogMutationTests.swift`

- [ ] **Step 1: Write mutation tests**

```swift
func testDeletingGroupKeepsItsItems() {
    var document = CatalogFixtures.documentWithOneGroup
    document.removeGroup(id: CatalogFixtures.groupID)
    XCTAssertEqual(document.items.count, 2)
    XCTAssertTrue(document.items.allSatisfy { !$0.groupIDs.contains(CatalogFixtures.groupID) })
}

func testSuccessfulInvocationUpdatesRecentAndDedupedFrequency() {
    var record = CatalogFixtures.item
    record.recordSuccess(at: Date(timeIntervalSince1970: 100))
    record.recordSuccess(at: Date(timeIntervalSince1970: 110))
    XCTAssertEqual(record.successfulInvocations.count, 1)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter CatalogMutationTests`

Expected: missing mutation methods.

- [ ] **Step 3: Implement catalog mutations and panel snapshots**

`CatalogController` owns load/save, scan reconciliation, favorite toggles, aliases, group CRUD, ordering, ignore state, successful invocation recording, and error recording. `HubPanelModel` publishes only `PanelSnapshot`, `query`, `selectionID`, `permissionState`, `operationState`, and localized error identifiers.

```swift
struct PanelSnapshot: Equatable {
    var favorites: [MenuBarItemRecord]
    var recent: [MenuBarItemRecord]
    var frequent: [MenuBarItemRecord]
    var customGroups: [(GroupRecord, [MenuBarItemRecord])]
    var allItems: [MenuBarItemRecord]
    var searchResults: [MenuBarItemRecord]
}
```

- [ ] **Step 4: Run all tests and a Debug build**

Run: `swift test && xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Debug build`

Expected: success with no Swift 6 isolation warnings promoted to errors.

---

### Task 8: Native Inset-Group Panel and Scroll Interaction

**Files:**
- Replace: `Sources/MenuHub/HubPanelView.swift`
- Create: `Sources/MenuHub/HubItemRow.swift`
- Create: `Sources/MenuHub/PanelKeyboardRouter.swift`
- Create: `Tests/MenuHubCoreTests/PanelNavigationTests.swift`

- [ ] **Step 1: Write keyboard-selection reducer tests**

```swift
func testEscapeClearsQueryBeforeClosing() {
    let result = PanelNavigation.reduce(state: .init(query: "chat", selectedIndex: 0), key: .escape)
    XCTAssertEqual(result.state.query, "")
    XCTAssertFalse(result.shouldClose)
}

func testSecondEscapeCloses() {
    let result = PanelNavigation.reduce(state: .init(query: "", selectedIndex: 0), key: .escape)
    XCTAssertTrue(result.shouldClose)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter PanelNavigationTests`

Expected: navigation reducer is missing.

- [ ] **Step 3: Implement the approved three-region layout**

```swift
VStack(spacing: 8) {
    HubSearchField(query: $model.query)
    ZStack {
        ScrollViewReader { proxy in
            ScrollView { HubInsetGroups(snapshot: model.snapshot) }
                .contentMargins(.trailing, 10, for: .scrollContent)
        }
        ScrollEdgeFades()
    }
    HubFooter(shortcut: model.shortcutDisplay, openSettings: model.openSettings)
}
.padding(10)
.frame(width: 320, minHeight: 180, maxHeight: 520)
.background(PanelMaterial())
```

Use a system overlay scroller, reserve the trailing gutter, keep actions outside that gutter, and show top/bottom fades only when more content exists. Rows are 38 points high with 22-point icons, full-row primary activation, hover/selection states, and meaningful VoiceOver labels. Respect Reduce Transparency, Reduce Motion, Increase Contrast, and system accent color.

- [ ] **Step 4: Implement full keyboard routing**

Route arrows, Return, Command-Return, Command-K, Command-F, Command-1…9, and two-stage Escape. Scroll the keyboard selection into view. Preserve standard text editing while the search field handles printable input.

- [ ] **Step 5: Build and visually inspect both appearances**

Run: `xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Debug build`

Expected: build succeeds. Manual inspection confirms the scrollbar never overlaps the trailing action target at the maximum 520-point panel height.

---

### Task 9: Progressive Authorization and Onboarding

**Files:**
- Create: `Sources/MenuHub/PermissionCoordinator.swift`
- Create: `Sources/MenuHub/OnboardingView.swift`
- Modify: `Sources/MenuHub/AppDelegate.swift`
- Create: `Tests/MenuHubCoreTests/OnboardingPolicyTests.swift`

- [ ] **Step 1: Write onboarding policy tests**

```swift
func testPermissionMayBeSkippedIntoLauncherMode() {
    XCTAssertEqual(OnboardingPolicy.next(after: .permission, choice: .skip), .scanSummary(mode: .launcher))
}

func testAuthorizedReturnAdvancesAndScans() {
    XCTAssertEqual(OnboardingPolicy.next(after: .permission, choice: .authorized), .scanSummary(mode: .full))
}
```

- [ ] **Step 2: Verify tests fail, then implement the flow**

Run: `swift test --filter OnboardingPolicyTests`

Expected: missing policy types.

Implement welcome, capability boundary, Accessibility explanation, status-item placement, scan result, and shortcut confirmation as reversible steps. Permission can be skipped. Observe `NSApplication.didBecomeActiveNotification`, recheck trust automatically, and start a scan after trust changes to true.

- [ ] **Step 3: Add explicit repair flow**

The repair action explains bundle identity/signature mismatch, asks for confirmation, invokes only the exact `tccutil reset Accessibility com.local.MenuHub` target, and then opens System Settings. It is never automatic and never resets Accessibility for all applications.

- [ ] **Step 4: Run tests and manually exercise grant/revoke states**

Run: `swift test && xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Debug build`

Expected: no repeated prompt after successful authorization; revocation changes the UI to launcher mode without crashing.

---

### Task 10: Management Window, Settings, and Launch at Login

**Files:**
- Create: `Sources/MenuHub/ManagementWindow.swift`
- Create: `Sources/MenuHub/SettingsView.swift`
- Create: `Sources/MenuHub/ShortcutRecorderView.swift`
- Modify: `Sources/MenuHub/main.swift`
- Modify: `Sources/MenuHub/AppDelegate.swift`

- [ ] **Step 1: Add window commands and scene wiring**

```swift
Settings { SettingsView(environment: environment) }
Window("Manage Items", id: "management") {
    ManagementWindow(controller: environment.catalogController)
}
.defaultSize(width: 760, height: 520)
```

Because the current app uses an AppKit entry point, expose equivalent `NSWindowController` instances if SwiftUI scene wiring conflicts with `LSUIElement`. Settings must be reachable from the status menu and `Command-,`; management must be reachable from Settings and item context menus.

- [ ] **Step 2: Implement all six settings sections**

General, Appearance, Items & Groups, Shortcuts, Permissions & Privacy, and Diagnostics must contain the exact controls in the approved design. Use `SMAppService.mainApp.register()` and `.unregister()` for launch at login and display the actual service state.

- [ ] **Step 3: Implement management mutations**

Provide searchable item table, alias editing, favorite toggle, multi-group membership, internal drag ordering, ignore/unignore, capability retest, last-seen, and last-error fields. Save after each completed mutation and provide undo for destructive group deletion.

- [ ] **Step 4: Build and manually verify window lifecycle**

Run: `xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Debug build`

Expected: settings and management windows reopen, resize, remember position, and do not create duplicate app instances.

---

### Task 11: Complete English and Simplified Chinese Localization

**Files:**
- Create: `Resources/en.lproj/Localizable.strings`
- Create: `Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Sources/MenuHub/LocalizationController.swift`
- Modify: `project.yml`
- Modify: `Package.swift`
- Create: `Tests/MenuHubCoreTests/LocalizationCompletenessTests.swift`

- [ ] **Step 1: Add a localization completeness test**

```swift
func testEnglishAndChineseContainIdenticalKeys() throws {
    let english = try LocalizedFixture.keys(language: "en")
    let chinese = try LocalizedFixture.keys(language: "zh-Hans")
    XCTAssertEqual(english, chinese)
}
```

- [ ] **Step 2: Verify the test fails**

Run: `swift test --filter LocalizationCompletenessTests`

Expected: localization resources are missing.

- [ ] **Step 3: Add localized keys for every user-visible string**

```text
"panel.search.placeholder" = "Search menu bar items";
"panel.group.favorites" = "Favorites";
"panel.group.recent" = "Recent";
"panel.group.frequent" = "Frequently Used";
"permission.title" = "Allow Accessibility Access";
"permission.localOnly" = "Your menu-bar catalog stays on this Mac.";
```

Create exact Chinese counterparts and replace literal strings in Swift with localized keys. Add System Default, 简体中文, and English preferences. If full menu localization requires relaunch, provide a localized relaunch button.

- [ ] **Step 4: Regenerate the Xcode project and run tests**

Run: `xcodegen generate && swift test && xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Debug build`

Expected: key sets match and both localizations are included in the app bundle.

---

### Task 12: Diagnostics, Restore Safety, and Status Menu Cleanup

**Files:**
- Create: `Sources/MenuHubCore/Diagnostics/DiagnosticArchive.swift`
- Create: `Sources/MenuHub/DiagnosticsController.swift`
- Modify: `Sources/MenuHub/AppDelegate.swift`
- Create: `Tests/MenuHubCoreTests/DiagnosticRedactionTests.swift`
- Extend: `Tests/MenuHubCoreTests/SpacerStateTests.swift`

- [ ] **Step 1: Write redaction and recovery tests**

```swift
func testArchiveRedactsHomePathAndQueryText() throws {
    let archive = DiagnosticArchive.make(events: fixtures, homeDirectory: "/Users/example")
    let text = String(decoding: try archive.jsonData(), as: UTF8.self)
    XCTAssertFalse(text.contains("/Users/example"))
    XCTAssertFalse(text.contains("private search"))
}

func testUncertainStartupAlwaysRevealsSpacer() {
    XCTAssertEqual(SpacerState.startupAfterUncleanExit(savedHidden: true).visibility, .revealed)
}
```

- [ ] **Step 2: Verify tests fail, then implement bounded local diagnostics**

Run: `swift test --filter DiagnosticRedactionTests`

Expected: missing diagnostic types.

Record only timestamps, app/Menu Hub versions, macOS version, domain error codes, anonymized stable item hashes, scan counts, and durations. Keep a bounded ring buffer. Export only after an explicit save-panel action.

- [ ] **Step 3: Reduce the right-click status menu to product commands**

Use localized dynamic titles for Hide/Show, Rescan, Settings, Restore Menu Bar, and Quit. Remove Phase 0 permission alerts and scan-report alerts from the production menu; keep probe functionality in `FeasibilityProbe`.

- [ ] **Step 4: Run safety tests and build**

Run: `swift test && xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Debug build`

Expected: all tests pass and Restore remains callable regardless of permission state.

---

### Task 13: Automated UI and Integration Coverage

**Files:**
- Create: `Tests/MenuHubUITests/MenuHubUITests.swift`
- Modify: `project.yml`
- Modify: `MenuHub.xcodeproj` by regeneration only

- [ ] **Step 1: Add deterministic launch arguments and UI fixtures**

```swift
app.launchArguments = ["-uiTesting", "1", "-permissionFixture", "authorized", "-catalogFixture", "mixed"]
app.launch()
XCTAssertTrue(app.textFields["panel.search"].waitForExistence(timeout: 3))
```

Add UI tests for onboarding, skipped permission, search, arrow/Return/Escape navigation, persistence relaunch, empty/error/launch-only states, Chinese and English labels, light/dark appearance, and accessibility identifiers. Do not automate or mutate the real TCC database in UI tests.

- [ ] **Step 2: Regenerate and run all automated tests**

Run: `xcodegen generate && xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS'`

Expected: unit, integration, and UI test targets pass.

- [ ] **Step 3: Run the search performance suite in Release**

Run: `swift test -c release --filter SearchIndexPerformanceTests`

Expected: 100-item query completes below 16 ms on the local machine and the measured result is recorded in `outputs/LocalValidationReport.md`.

---

### Task 14: Release Build, Install, and Local Acceptance

**Files:**
- Modify: `README.md`
- Modify: `docs/ReleaseChecklist.md`
- Modify: `outputs/LocalValidationReport.md`
- Modify: `outputs/MVP-Comparison-Audit.md`

- [ ] **Step 1: Run clean Release build and test gates**

Run:

```bash
xcodegen generate
xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS'
xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Release -derivedDataPath work/DerivedData clean build
```

Expected: all commands succeed with Swift 6 and `MACOSX_DEPLOYMENT_TARGET=14.0`.

- [ ] **Step 2: Validate the bundle before installation**

Run:

```bash
codesign --verify --deep --strict --verbose=2 work/DerivedData/Build/Products/Release/Menu\ Hub.app
codesign -dvvv work/DerivedData/Build/Products/Release/Menu\ Hub.app
otool -L work/DerivedData/Build/Products/Release/Menu\ Hub.app/Contents/MacOS/MenuHub
```

Expected: signature is valid, hardened runtime is present, bundle ID is `com.local.MenuHub`, and no prohibited third-party networking/analytics framework is linked.

- [ ] **Step 3: Replace the installed build without duplicate processes**

Quit only the existing `com.local.MenuHub` process, move the previous `/Applications/Menu Hub.app` into a timestamped recoverable backup under `work/`, copy the verified Release bundle into `/Applications`, and launch the installed path. Preserve catalog data. Do not reset Accessibility unless the user invokes the confirmed repair action.

- [ ] **Step 4: Perform local interaction acceptance**

Verify on the current Mac:

- one visible Menu Hub status icon and an invisible spacer;
- `⌥M` opens and closes the panel;
- search focuses immediately;
- scrolling with trackpad/mouse does not cover row actions;
- mouse and keyboard trigger compatible items;
- launch-only items activate their host;
- Favorites, aliases, groups, ordering, Recent, and Frequent survive relaunch;
- Chinese and English switch correctly;
- authorized, revoked, skipped, and repair states behave as specified;
- light/dark and reduced-transparency states remain legible;
- Settings, Management, Diagnostics, launch-at-login status, and Restore work.

- [ ] **Step 5: Report evidence honestly**

Update the validation report and MVP comparison with build/test results, installed bundle identity, screenshots, performance measurements, and any failures. Mark notch, external-display, alternate-hardware, beta-macOS, 1,000-cycle, 500-trigger, 20 sleep/wake, 20 display-plug, and notarization checks as unverified unless they were actually performed.

---

## Plan Self-Review Result

- Every approved MVP area maps to a task: catalog/persistence (1–3, 7), Accessibility and fallback (4–5, 9), shortcut (6), panel and keyboard UI (8), management/settings/login (10), bilingual resources (11), diagnostics/recovery (12), tests/performance (13), and build/install/acceptance (14).
- Phase 0 experimental evidence remains intact; production-only alerts are removed only after equivalent permission and diagnostic UI exists.
- No task requires private APIs, Screen Recording, networking, analytics, cloud storage, or code injection.
- Hardware and long-duration checks cannot be inferred from local automated success and remain explicitly unverified until run.
- This directory is not a Git repository, so commit steps are replaced by green-build checkpoints rather than silently creating repository history.
