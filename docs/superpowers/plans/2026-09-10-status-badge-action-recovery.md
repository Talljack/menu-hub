# Status Badge and Action Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a privacy-preserving unread-total capsule, persistent status-item placement, adaptive background refresh, per-item inclusion controls, and bounded recovery for slow menu bar actions.

**Architecture:** Pure parsing, classification, aggregation, and persisted preference logic live in `MenuHubCore`. `HubPanelModel` owns adaptive monitoring and publishes a value-only badge presentation; a narrow AppKit renderer updates `NSStatusItem`. Invocation invalidates live scan generations before pressing and resumes monitoring afterward so Accessibility work cannot race.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Combine, macOS Accessibility APIs, XCTest/XCUITest, XcodeGen, macOS 14+

---

## File Structure

- Create `Sources/MenuHubCore/StatusBar/UnreadBadge.swift`: parsing, chat classification, override resolution, aggregation, and presentation values.
- Modify `Sources/MenuHubCore/Catalog/MenuBarItemRecord.swift`: persist tri-state `UnreadBadgePreference` with backward-compatible decoding.
- Modify `Sources/MenuHubCore/Catalog/CatalogMutations.swift`: mutate the per-item override.
- Create `Tests/MenuHubCoreTests/UnreadBadgeTests.swift`: exhaustive core behavior tests.
- Modify `Tests/MenuHubCoreTests/MenuBarItemRecordTests.swift`: legacy JSON migration coverage.
- Modify `Sources/MenuHub/CatalogController.swift`: publish aggregation inputs and persist override changes.
- Modify `Sources/MenuHub/HubPanelModel.swift`: adaptive visible/background monitoring, badge publication, and scan/invocation coordination.
- Modify `Tests/MenuHubTests/HubPanelModelTests.swift`: deterministic cadence, badge, and coordination tests.
- Create `Sources/MenuHub/StatusItemBadgeRenderer.swift`: focused `NSStatusItem` presentation boundary.
- Modify `Sources/MenuHubCore/StatusBar/MenuBarIconFactory.swift`: generate the selected monochrome icon-plus-capsule template image.
- Modify `Sources/MenuHub/AppDelegate.swift`: stable autosave names, badge subscription, and background monitoring lifecycle.
- Modify `Tests/MenuHubCoreTests/HubPresentationTests.swift`: dynamic image dimensions and template rendering tests.
- Modify `Tests/MenuHubTests/ManagementSettingsTests.swift`: autosave-name and management override tests.
- Modify `Sources/MenuHub/ManagementWindow.swift`: native per-item tri-state picker.
- Modify `Sources/MenuHub/HubItemRow.swift`: failed-row Retry and Open App actions.
- Modify `Sources/MenuHubCore/Actions/ActionExecutor.swift`: increase the bounded press timeout without retrying timed-out actions.
- Modify `Tests/MenuHubCoreTests/AccessibilityPipelineTests.swift`: timeout and retry invariants.
- Modify `Resources/*.lproj/Localizable.strings`: all ten localizations for badge, override, and retry labels.
- Modify `Tests/MenuHubCoreTests/LocalizationCompletenessTests.swift`: required-key coverage.
- Modify `Sources/MenuHub/UITestRuntime.swift` and `Tests/MenuHubUITests/MenuHubUITests.swift`: deterministic unread and failed-action fixtures.
- Modify `README.md` and localized READMEs only if the behavior requires user-facing clarification after implementation.

### Task 1: Core unread parsing, classification, aggregation, and persistence

**Files:**
- Create: `Sources/MenuHubCore/StatusBar/UnreadBadge.swift`
- Create: `Tests/MenuHubCoreTests/UnreadBadgeTests.swift`
- Modify: `Sources/MenuHubCore/Catalog/MenuBarItemRecord.swift`
- Modify: `Sources/MenuHubCore/Catalog/CatalogMutations.swift`
- Modify: `Tests/MenuHubCoreTests/MenuBarItemRecordTests.swift`

- [ ] **Step 1: Write failing parser, classifier, aggregator, override, and migration tests**

```swift
final class UnreadBadgeTests: XCTestCase {
    func testParserAcceptsOnlyWholeNumericTitles() {
        XCTAssertEqual(UnreadCountParser.parse("14"), .exact(14))
        XCTAssertEqual(UnreadCountParser.parse(" ９ "), .exact(9))
        XCTAssertEqual(UnreadCountParser.parse("99+"), .atLeast99)
        for value in ["", "•", "3 unread", "Battery 83%", "12:30", "-1", "2@·17"] {
            XCTAssertNil(UnreadCountParser.parse(value), value)
        }
    }

    func testAutomaticClassificationIncludesChatAndRejectsSystemMonitor() {
        XCTAssertTrue(ChatApplicationClassifier.isChat(bundleIdentifier: "com.larksuite.feishu", hostName: "Feishu"))
        XCTAssertTrue(ChatApplicationClassifier.isChat(bundleIdentifier: "com.tencent.xinWeChat", hostName: "WeChat"))
        XCTAssertTrue(ChatApplicationClassifier.isChat(bundleIdentifier: "com.tinyspeck.slackmacgap", hostName: "Slack"))
        XCTAssertFalse(ChatApplicationClassifier.isChat(bundleIdentifier: "com.apple.controlcenter", hostName: "Battery"))
        XCTAssertFalse(ChatApplicationClassifier.isChat(bundleIdentifier: "com.bjango.istatmenus", hostName: "iStat Menus"))
    }

    func testAggregatorUsesOverridesDeduplicatesAndSaturates() {
        let snapshots = fixtures(
            ("lark", "com.larksuite.feishu", "Feishu", "14", .automatic),
            ("battery", "com.apple.controlcenter", "Battery", "83", .automatic),
            ("timer", "com.example.timer", "Timer", "5", .include),
            ("wechat", "com.tencent.xinWeChat", "WeChat", "•", .automatic),
            ("qq", "com.tencent.qq", "QQ", "99+", .automatic)
        )
        XCTAssertEqual(UnreadBadgeAggregator.presentation(records: snapshots.records, snapshots: snapshots.runtime), .overflow)
    }
}
```

Add a legacy decoding test that removes `unreadBadgePreference` from encoded item JSON and asserts `.automatic`. Add another with an unknown raw string and assert `.automatic` rather than failing the document.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter UnreadBadgeTests
```

Expected: FAIL because `UnreadCountParser`, `ChatApplicationClassifier`, `UnreadBadgeAggregator`, and `UnreadBadgePreference` do not exist.

- [ ] **Step 3: Implement the minimal core types**

```swift
public enum UnreadBadgePreference: String, Codable, CaseIterable, Equatable, Sendable {
    case automatic, include, exclude
}

public enum UnreadCountValue: Equatable, Sendable {
    case exact(Int)
    case atLeast99
}

public enum UnreadBadgePresentation: Equatable, Sendable {
    case hidden
    case count(Int)
    case overflow
}

public enum UnreadCountParser {
    public static func parse(_ title: String?) -> UnreadCountValue? {
        guard var value = title?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let overflow = value.hasSuffix("+")
        if overflow { value.removeLast() }
        guard !value.isEmpty, value.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else { return nil }
        let normalized = value.compactMap(\.wholeNumberValue).map(String.init).joined()
        guard let number = Int(normalized) else { return nil }
        return overflow ? .atLeast99 : .exact(number)
    }
}
```

Implement `ChatApplicationClassifier` with normalized exact bundle IDs plus conservative host-name fallbacks for the approved registry. Implement `UnreadBadgeAggregator` so preference resolution occurs before parsing, stable IDs are deduplicated, zero contributes nothing, addition saturates, and any lower-bound/total of 100 or greater returns `.overflow`.

Add `unreadBadgePreference` to `MenuBarItemRecord` and implement explicit `CodingKeys`, `init(from:)`, and `encode(to:)`. Decode missing or unknown values through `decodeIfPresent(String.self, ...)` and `UnreadBadgePreference(rawValue:) ?? .automatic`.

- [ ] **Step 4: Add catalog mutation and verify GREEN**

```swift
@discardableResult
public mutating func setUnreadBadgePreference(_ preference: UnreadBadgePreference, forItemID itemID: String) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == itemID }),
          items[index].unreadBadgePreference != preference else { return false }
    items[index].unreadBadgePreference = preference
    return true
}
```

Run:

```bash
swift test --filter UnreadBadgeTests
swift test --filter MenuBarItemRecordTests
```

Expected: both suites PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuHubCore/StatusBar/UnreadBadge.swift Sources/MenuHubCore/Catalog/MenuBarItemRecord.swift Sources/MenuHubCore/Catalog/CatalogMutations.swift Tests/MenuHubCoreTests/UnreadBadgeTests.swift Tests/MenuHubCoreTests/MenuBarItemRecordTests.swift
git commit -m "feat: add unread badge policy"
```

### Task 2: Publish badge state and add adaptive monitoring

**Files:**
- Modify: `Sources/MenuHub/CatalogController.swift`
- Modify: `Sources/MenuHub/HubPanelModel.swift`
- Modify: `Sources/MenuHub/HubPanelView.swift`
- Modify: `Sources/MenuHub/AppDelegate.swift`
- Modify: `Tests/MenuHubTests/HubPanelModelTests.swift`

- [ ] **Step 1: Write failing cadence and aggregation tests**

Add deterministic tests using `ManualPanelLiveUpdateScheduler`:

```swift
func testBackgroundMonitoringRefreshesKnownItemsWithoutFullDiscovery() async {
    let scheduler = ManualPanelLiveUpdateScheduler()
    let model = makeAuthorizedModel(scheduler: scheduler, snapshots: [larkSnapshot(title: "2")])
    model.startBackgroundUpdates()
    await finishInitialScan(model)

    scheduler.fire()
    XCTAssertEqual(await accessibility.refreshCount, 1)
    XCTAssertEqual(await accessibility.scanCount, 1)
    XCTAssertEqual(model.unreadBadgePresentation, .count(2))
    XCTAssertEqual(scheduler.intervals.last, 5)
}

func testPanelVisibilityUpgradesAndDowngradesMonitoringCadence() async {
    model.startBackgroundUpdates()
    XCTAssertEqual(scheduler.intervals.last, 5)
    model.panelDidAppear()
    XCTAssertEqual(scheduler.intervals.last, 1)
    model.panelDidDisappear()
    XCTAssertEqual(scheduler.intervals.last, 5)
}

func testDisablingAutomaticScanningClearsBadgeAndStopsScheduler() async {
    model.startBackgroundUpdates()
    await controller.updatePreferences { $0.automaticScanning = false }
    XCTAssertEqual(model.unreadBadgePresentation, .hidden)
    XCTAssertTrue(scheduler.isCancelled)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
swift test --filter HubPanelModelTests
```

Expected: FAIL because background monitoring APIs and `unreadBadgePresentation` do not exist.

- [ ] **Step 3: Implement monitoring mode and badge publication**

```swift
enum PanelMonitoringMode: Equatable {
    case stopped, background, foreground
    var interval: TimeInterval? {
        switch self { case .stopped: nil; case .background: 5; case .foreground: 1 }
    }
}

@Published private(set) var unreadBadgePresentation: UnreadBadgePresentation = .hidden
private var monitoringMode: PanelMonitoringMode = .stopped

func startBackgroundUpdates() { setMonitoringMode(.background) }
func panelDidAppear() { setMonitoringMode(.foreground) }
func panelDidDisappear() { setMonitoringMode(.background) }
func stopMonitoring() { setMonitoringMode(.stopped) }
```

Reschedule the existing cancellation token whenever the mode changes. In background mode, ticks call `refreshKnownItems()` and never periodic full discovery. In foreground mode, retain the existing 20-second discovery behavior. Recompute `UnreadBadgeAggregator.presentation(records:snapshots:)` in the existing document/runtime subscription. Clear the presentation when permission is not authorized or automatic scanning is disabled.

Replace `HubPanelView`'s `startLiveUpdates`/`stopLiveUpdates` calls with `panelDidAppear`/`panelDidDisappear`. Start background monitoring from `AppDelegate` after permission coordination starts and stop it during application termination.

- [ ] **Step 4: Verify GREEN and existing live-update compatibility**

```bash
swift test --filter HubPanelModelTests
swift test --filter CatalogControllerTests
```

Expected: PASS with foreground cadence 1 second, background cadence 5 seconds, and no duplicate scheduled token.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuHub/CatalogController.swift Sources/MenuHub/HubPanelModel.swift Sources/MenuHub/HubPanelView.swift Sources/MenuHub/AppDelegate.swift Tests/MenuHubTests/HubPanelModelTests.swift
git commit -m "feat: monitor unread counts in background"
```

### Task 3: Render the monochrome count capsule and persist status-item positions

**Files:**
- Create: `Sources/MenuHub/StatusItemBadgeRenderer.swift`
- Modify: `Sources/MenuHubCore/StatusBar/MenuBarIconFactory.swift`
- Modify: `Sources/MenuHub/AppDelegate.swift`
- Modify: `Tests/MenuHubCoreTests/HubPresentationTests.swift`
- Modify: `Tests/MenuHubTests/ManagementSettingsTests.swift`

- [ ] **Step 1: Write failing renderer and placement tests**

```swift
func testUnreadTemplateWidthsGrowAndOverflowIsBounded() {
    let hidden = MenuBarIconFactory.makeImage(presentation: .hidden)
    let one = MenuBarIconFactory.makeImage(presentation: .count(7))
    let two = MenuBarIconFactory.makeImage(presentation: .count(42))
    let overflow = MenuBarIconFactory.makeImage(presentation: .overflow)
    XCTAssertTrue([hidden, one, two, overflow].allSatisfy(\.isTemplate))
    XCTAssertLessThan(hidden.size.width, one.size.width)
    XCTAssertLessThan(one.size.width, two.size.width)
    XCTAssertLessThanOrEqual(overflow.size.width, 42)
}

func testStatusItemAutosaveNamesAreStableAndDistinct() {
    XCTAssertEqual(StatusItemIdentity.primaryAutosaveName, "com.local.MenuHub.primary")
    XCTAssertEqual(StatusItemIdentity.spacerAutosaveName, "com.local.MenuHub.spacer")
    XCTAssertNotEqual(StatusItemIdentity.primaryAutosaveName, StatusItemIdentity.spacerAutosaveName)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
swift test --filter HubPresentationTests
swift test --filter ManagementSettingsTests/testStatusItemAutosaveNamesAreStableAndDistinct
```

Expected: FAIL because the dynamic factory overload and identity constants do not exist.

- [ ] **Step 3: Implement the template renderer and narrow AppKit boundary**

```swift
enum StatusItemIdentity {
    static let primaryAutosaveName = NSStatusItem.AutosaveName("com.local.MenuHub.primary")
    static let spacerAutosaveName = NSStatusItem.AutosaveName("com.local.MenuHub.spacer")
}

@MainActor
struct StatusItemBadgeRenderer {
    func apply(_ presentation: UnreadBadgePresentation, to item: NSStatusItem, button: NSStatusBarButton) {
        let image = MenuBarIconFactory.makeImage(presentation: presentation)
        button.image = image
        button.imagePosition = .imageOnly
        item.length = max(NSStatusItem.squareLength, image.size.width + 8)
    }
}
```

Extend `MenuBarIconFactory` to draw the existing glyph and, when needed, a rounded solid capsule whose decimal glyphs are cleared with `.copy` compositing. Set `isTemplate = true` after drawing. Clamp `.count` to 1...99 and format `.overflow` as `99+`.

In `AppDelegate.configureStatusItems`, assign both autosave names before button configuration. Subscribe to `panelModel.$unreadBadgePresentation.removeDuplicates()` and update the renderer, localized tooltip, and accessibility label.

- [ ] **Step 4: Verify GREEN and pixel visibility**

```bash
swift test --filter HubPresentationTests
swift test --filter ManagementSettingsTests/testStatusItemAutosaveNamesAreStableAndDistinct
```

Expected: PASS; every generated image is template, visible, and bounded.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuHub/StatusItemBadgeRenderer.swift Sources/MenuHubCore/StatusBar/MenuBarIconFactory.swift Sources/MenuHub/AppDelegate.swift Tests/MenuHubCoreTests/HubPresentationTests.swift Tests/MenuHubTests/ManagementSettingsTests.swift
git commit -m "feat: show unread total in menu bar"
```

### Task 4: Add user override controls and complete localization

**Files:**
- Modify: `Sources/MenuHub/CatalogController.swift`
- Modify: `Sources/MenuHub/ManagementWindow.swift`
- Modify: `Tests/MenuHubTests/ManagementSettingsTests.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `Resources/ja.lproj/Localizable.strings`
- Modify: `Resources/ko.lproj/Localizable.strings`
- Modify: `Resources/es.lproj/Localizable.strings`
- Modify: `Resources/fr.lproj/Localizable.strings`
- Modify: `Resources/de.lproj/Localizable.strings`
- Modify: `Resources/pt-BR.lproj/Localizable.strings`
- Modify: `Resources/ru.lproj/Localizable.strings`
- Modify: `Tests/MenuHubCoreTests/LocalizationCompletenessTests.swift`

- [ ] **Step 1: Write failing controller and localization tests**

```swift
func testControllerPersistsUnreadBadgeOverride() async {
    await controller.setUnreadBadgePreference(.include, itemID: "timer")
    XCTAssertEqual(controller.document.items.first { $0.id == "timer" }?.unreadBadgePreference, .include)
    XCTAssertEqual(store.latestSaved?.items.first { $0.id == "timer" }?.unreadBadgePreference, .include)
}
```

Require these keys in localization completeness coverage:

```swift
"management.unreadBadge", "management.unreadBadgeAutomatic",
"management.unreadBadgeInclude", "management.unreadBadgeExclude",
"statusItem.unreadFormat", "panel.retry"
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
swift test --filter ManagementSettingsTests
swift test --filter LocalizationCompletenessTests
```

Expected: FAIL because mutation API and localization keys do not exist.

- [ ] **Step 3: Implement the controller API and native Picker**

```swift
func setUnreadBadgePreference(_ preference: UnreadBadgePreference, itemID: String) async {
    guard document.setUnreadBadgePreference(preference, forItemID: itemID) else { return }
    await mutationDidComplete()
}
```

```swift
Picker(L("management.unreadBadge"), selection: Binding(
    get: { item.unreadBadgePreference },
    set: { value in Task { await controller.setUnreadBadgePreference(value, itemID: item.id) } }
)) {
    Text(L("management.unreadBadgeAutomatic")).tag(UnreadBadgePreference.automatic)
    Text(L("management.unreadBadgeInclude")).tag(UnreadBadgePreference.include)
    Text(L("management.unreadBadgeExclude")).tag(UnreadBadgePreference.exclude)
}
```

Add accurate translations in all ten localization files. Use localized unread formatting for tooltip and VoiceOver, not string concatenation.

- [ ] **Step 4: Verify GREEN**

```bash
swift test --filter ManagementSettingsTests
swift test --filter LocalizationCompletenessTests
```

Expected: PASS with identical localization key sets.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuHub/CatalogController.swift Sources/MenuHub/ManagementWindow.swift Tests/MenuHubTests/ManagementSettingsTests.swift Resources/*.lproj/Localizable.strings Tests/MenuHubCoreTests/LocalizationCompletenessTests.swift
git commit -m "feat: configure unread badge sources"
```

### Task 5: Bound slow actions and recover failed rows safely

**Files:**
- Modify: `Sources/MenuHubCore/Actions/ActionExecutor.swift`
- Modify: `Sources/MenuHub/HubPanelModel.swift`
- Modify: `Sources/MenuHub/HubItemRow.swift`
- Modify: `Tests/MenuHubCoreTests/AccessibilityPipelineTests.swift`
- Modify: `Tests/MenuHubTests/HubPanelModelTests.swift`
- Modify: `Tests/MenuHubTests/PanelNavigationTests.swift`

- [ ] **Step 1: Write failing timeout, coordination, and feedback tests**

```swift
func testDefaultPressAllowsSlowButResponsiveTarget() async {
    let accessibility = FakeAccessibility(pressDelay: .milliseconds(700))
    let outcome = await ActionExecutor(accessibility: accessibility, launcher: FakeLauncher(result: true))
        .execute(item(), snapshot: snapshot())
    XCTAssertEqual(outcome, .pressed)
    XCTAssertEqual(await accessibility.counts.press, 1)
}

func testTimedOutPressNeverRetries() async {
    let accessibility = FakeAccessibility(pressDelay: .seconds(2))
    let executor = ActionExecutor(accessibility: accessibility, launcher: FakeLauncher(result: true), pressTimeout: .milliseconds(40))
    XCTAssertEqual(await executor.execute(item(), snapshot: snapshot()), .failed(.accessibility(.targetUnresponsive)))
    try? await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(await accessibility.counts.press, 1)
    XCTAssertEqual(await accessibility.counts.scan, 0)
}

func testInvocationInvalidatesLiveScanAndFailureFeedbackClears() async {
    model.startBackgroundUpdates()
    scheduler.fire()
    model.invoke(model.items[0])
    XCTAssertTrue(await waitUntil { model.lastFailedItemID == "item" })
    XCTAssertTrue(await waitUntil { model.lastFailedItemID == nil })
    XCTAssertEqual(model.monitoringModeForTests, .background)
}
```

Configure the model's injected `failureFeedbackDuration` to a few milliseconds in tests.

- [ ] **Step 2: Run focused tests and verify RED**

```bash
swift test --filter AccessibilityPipelineTests/testDefaultPressAllowsSlowButResponsiveTarget
swift test --filter HubPanelModelTests/testInvocationInvalidatesLiveScanAndFailureFeedbackClears
```

Expected: the 700 ms press fails under the old 500 ms default and failure feedback never clears.

- [ ] **Step 3: Implement bounded timeout and model coordination**

Set `pressTimeout: Duration = .milliseconds(1_200)`. Keep the explicit timeout tests' injected short durations unchanged. Do not add a timeout rescan or second press.

Before invoking, cancel and nil `inFlightLiveScanTask`, increment its generation, and call `controller.invalidateAccessibilityWork()`. Scheduler ticks guard against `.invoking`. After a current invocation result, restore idle state and let the active monitoring mode schedule a known-item refresh.

Add `failureFeedbackTask` and injected `failureFeedbackDuration`. On failure, publish the row and bottom message, then clear both only if the same item and generation are still current.

- [ ] **Step 4: Add Retry/Open App failure actions**

```swift
Button(hasFailure ? L("panel.retry") : L(item.isLaunchOnly ? "panel.openApp" : "panel.defaultAction")) {
    actionMenuState.dismiss()
    action()
}
if canOpenHost {
    Button(L("panel.openHost")) { actionMenuState.dismiss(); openHost() }
}
```

Add a presentation test proving the failed row exposes localized Retry and retains Open Host availability.

- [ ] **Step 5: Verify GREEN and commit**

```bash
swift test --filter AccessibilityPipelineTests
swift test --filter HubPanelModelTests
swift test --filter PanelNavigationTests
git add Sources/MenuHubCore/Actions/ActionExecutor.swift Sources/MenuHub/HubPanelModel.swift Sources/MenuHub/HubItemRow.swift Tests/MenuHubCoreTests/AccessibilityPipelineTests.swift Tests/MenuHubTests/HubPanelModelTests.swift Tests/MenuHubTests/PanelNavigationTests.swift
git commit -m "fix: recover slow menu bar actions"
```

### Task 6: Add deterministic UI coverage and user documentation

**Files:**
- Modify: `Sources/MenuHub/UITestRuntime.swift`
- Modify: `Tests/MenuHubUITests/MenuHubUITests.swift`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: other localized READMEs only where their installation/usage sections describe live scanning

- [ ] **Step 1: Write failing UI tests**

```swift
func testUnreadBadgeFixtureKeepsPanelInteractionAvailable() {
    launch(arguments: ["-uiTestUnreadCount", "14"])
    XCTAssertTrue(element(identifier: "hub.search").waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Feishu — 14"].exists)
}

func testFailedGridActionExposesRetryAndOpenApp() {
    launch(arguments: ["-uiTestActionFailure", "targetUnresponsive", "-uiTestLayout", "grid"])
    element(identifier: "hub.item.shadowrocket").click()
    element(identifier: "hub.item.shadowrocket.more").click()
    XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Open Host Application"].exists)
}
```

- [ ] **Step 2: Run UI tests and verify RED**

```bash
xcodegen generate
xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS' -only-testing:MenuHubUITests/MenuHubUITests/testUnreadBadgeFixtureKeepsPanelInteractionAvailable -only-testing:MenuHubUITests/MenuHubUITests/testFailedGridActionExposesRetryAndOpenApp
```

Expected: FAIL because the deterministic launch arguments and recovery fixture do not exist.

- [ ] **Step 3: Implement deterministic fixtures and update docs**

Extend `UITestRuntime` to provide exact runtime snapshot titles and controlled outcomes for the two arguments. Add a concise README section explaining the exact-number rule, five-second closed-panel refresh, automatic chat registry, per-item override, privacy boundary, and Command-drag position persistence.

- [ ] **Step 4: Verify GREEN and commit**

```bash
xcodegen generate
xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS' -only-testing:MenuHubUITests/MenuHubUITests/testUnreadBadgeFixtureKeepsPanelInteractionAvailable -only-testing:MenuHubUITests/MenuHubUITests/testFailedGridActionExposesRetryAndOpenApp
git add Sources/MenuHub/UITestRuntime.swift Tests/MenuHubUITests/MenuHubUITests.swift README*.md
git commit -m "test: cover unread badge and action recovery"
```

### Task 7: Full verification, signed local build, install, and runtime check

**Files:**
- No production edits expected
- Generated: `MenuHub.xcodeproj`, `DerivedData/`, `dist/`

- [ ] **Step 1: Run all source and localization tests**

```bash
swift test
```

Expected: all XCTest and Swift Testing suites PASS with zero failures.

- [ ] **Step 2: Run the complete Xcode test suite**

```bash
xcodegen generate
xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Build both release architectures**

```bash
BUILD_ONLY=1 SKIP_TESTS=1 ./scripts/build-release.sh
```

Expected: `Built arm64 app` and `Built x86_64 app`, each followed by `BUILD SUCCEEDED`.

- [ ] **Step 4: Sign and verify the local arm64 app**

```bash
codesign --force --deep --options runtime --timestamp --sign 'Developer ID Application: Yugang Cao (636LV693YD)' 'dist/Menu Hub-0.1.4-arm64/Menu Hub.app'
codesign --verify --deep --strict --verbose=2 'dist/Menu Hub-0.1.4-arm64/Menu Hub.app'
```

Expected: valid Developer ID signature and hardened runtime.

- [ ] **Step 5: Install recoverably and launch**

```bash
backup_dir="$(mktemp -d /tmp/menu-hub-before-badge.XXXXXX)"
pkill -x MenuHub 2>/dev/null || true
mv '/Applications/Menu Hub.app' "$backup_dir/Menu Hub.app"
ditto 'dist/Menu Hub-0.1.4-arm64/Menu Hub.app' '/Applications/Menu Hub.app'
open -a '/Applications/Menu Hub.app'
pgrep -fl '/Applications/Menu Hub.app/Contents/MacOS/MenuHub'
```

Expected: one running MenuHub process from `/Applications/Menu Hub.app`; preserve the printed backup directory until manual verification passes.

- [ ] **Step 6: Manual macOS verification**

Verify on the current Mac:

1. Menu Hub appears immediately and the previous user-dragged position is retained.
2. A Feishu numeric title updates the monochrome capsule within five seconds while the panel is closed.
3. WeChat without an exact number contributes zero.
4. Automatic/include/exclude changes take effect after the next refresh.
5. Dark and light menu bars render the template capsule legibly.
6. Left click, right click, Option-click, global shortcut, arrow navigation, Return, and Command-K still work.
7. A slow deterministic target succeeds; a timed-out target shows brief recovery UI and never receives an automatic second press.
8. Wake and display changes retain a usable status item and restore safe spacer width.

- [ ] **Step 7: Final repository checks and commit only if verification changed docs**

```bash
git diff --check
git status --short --branch
git log --oneline main..HEAD
```

Expected: clean worktree, feature branch ahead of main by the design, plan, and implementation commits.
