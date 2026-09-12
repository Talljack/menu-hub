# Liquid Glass Action Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Menu Hub's plain item action popover with the approved rounded, keyboard-accessible Liquid Glass action panel while preserving every existing command on macOS 14 and later.

**Architecture:** Extract a pure presentation-state reducer and a focused SwiftUI action-panel view from `HubItemRow`. The row continues to own callbacks and item state, while the new panel owns only transient navigation/editing UI; a small surface modifier selects native Liquid Glass on macOS 26, regular system material on macOS 14–15, and an opaque semantic background when transparency is reduced.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, XCTest, Swift Package Manager, Xcode 26.6, macOS 14 deployment target

---

## File Structure

- Create `Sources/MenuHub/HubItemActionPanelState.swift`: pure page, disclosure, command-order, and Escape behavior.
- Create `Sources/MenuHub/HubItemActionPanel.swift`: the approved header, primary command, rounded action surfaces, rename/groups/more states, keyboard routing, and accessibility.
- Create `Sources/MenuHub/HubActionPanelSurface.swift`: material and button styling with macOS 14/26 and accessibility fallbacks.
- Modify `Sources/MenuHub/HubItemRow.swift`: remove the inline popover UI and pass existing values/callbacks to the extracted panel.
- Modify `Tests/MenuHubTests/PanelNavigationTests.swift`: reducer, command availability, material-mode, and layout-parity regression tests.
- Modify `Resources/*/Localizable.strings`: add complete panel headings, editor, status, disclosure, and keyboard-hint strings in all ten languages.
- Modify `Tests/MenuHubTests/LocalizationTests.swift`: require the new keys across every supported localization.
- Modify `Tests/MenuHubUITests/MenuHubUITests.swift`: smoke-test action-panel presentation and key accessibility identifiers if the existing harness supports it.
- Modify `VERSION` and `project.yml`: advance the post-0.1.4 feature release to 0.1.5 after all validation passes.

### Task 1: Pure Action-Panel State

**Files:**
- Create: `Sources/MenuHub/HubItemActionPanelState.swift`
- Modify: `Tests/MenuHubTests/PanelNavigationTests.swift`

- [ ] **Step 1: Write failing reducer tests**

Add tests that exercise mutually exclusive pages, advanced disclosure, presentation reset, and layered Escape behavior:

```swift
func testActionPanelPresentationStartsWithCommandsAndResetsDraft() {
    var state = HubItemActionPanelState()
    state.present(alias: "Work")
    XCTAssertEqual(state.page, .commands)
    XCTAssertEqual(state.aliasDraft, "Work")
    XCTAssertFalse(state.showsMoreActions)

    state.showRename()
    state.aliasDraft = "Changed"
    state.dismiss()
    state.present(alias: nil)
    XCTAssertEqual(state.page, .commands)
    XCTAssertEqual(state.aliasDraft, "")
}

func testActionPanelEscapeUnwindsInnerStateBeforeDismissal() {
    var state = HubItemActionPanelState(isPresented: true)
    state.showRename()
    XCTAssertEqual(state.handleEscape(), .stayPresented)
    XCTAssertEqual(state.page, .commands)
    state.toggleMoreActions()
    XCTAssertEqual(state.handleEscape(), .stayPresented)
    XCTAssertFalse(state.showsMoreActions)
    XCTAssertEqual(state.handleEscape(), .dismiss)
}

func testActionPanelPagesAreMutuallyExclusive() {
    var state = HubItemActionPanelState(isPresented: true)
    state.showRename()
    state.showGroups()
    XCTAssertEqual(state.page, .groups)
    XCTAssertFalse(state.showsMoreActions)
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
swift test --filter PanelNavigationTests
```

Expected: compilation fails because `HubItemActionPanelState` and its page/escape types do not exist.

- [ ] **Step 3: Implement the minimal reducer**

Create a value type with explicit states and no view dependencies:

```swift
import Foundation

enum HubItemActionPanelPage: Equatable { case commands, rename, groups }
enum HubItemActionPanelEscapeResult: Equatable { case stayPresented, dismiss }

struct HubItemActionPanelState: Equatable {
    var isPresented = false
    private(set) var page: HubItemActionPanelPage = .commands
    var aliasDraft = ""
    private(set) var showsMoreActions = false

    mutating func present(alias: String?) {
        isPresented = true
        page = .commands
        aliasDraft = alias ?? ""
        showsMoreActions = false
    }

    mutating func dismiss() {
        isPresented = false
        page = .commands
        showsMoreActions = false
    }

    mutating func toggle() {
        if isPresented { dismiss() } else { present(alias: nil) }
    }

    mutating func applyExternalRequest(_ requested: Bool, alias: String?) {
        if requested { present(alias: alias) }
    }

    mutating func showRename() { page = .rename; showsMoreActions = false }
    mutating func showGroups() { page = .groups; showsMoreActions = false }
    mutating func showCommands() { page = .commands }
    mutating func toggleMoreActions() { page = .commands; showsMoreActions.toggle() }

    mutating func handleEscape() -> HubItemActionPanelEscapeResult {
        if page != .commands { page = .commands; return .stayPresented }
        if showsMoreActions { showsMoreActions = false; return .stayPresented }
        return .dismiss
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run `swift test --filter PanelNavigationTests`.

Expected: new reducer tests pass and existing action-menu state tests are updated to the new `present(alias:)`/`applyExternalRequest(_:alias:)` API.

- [ ] **Step 5: Commit the reducer**

```bash
git add Sources/MenuHub/HubItemActionPanelState.swift Tests/MenuHubTests/PanelNavigationTests.swift
git commit -m "feat: model action panel presentation states"
```

### Task 2: Surface and Command Presentation Models

**Files:**
- Create: `Sources/MenuHub/HubActionPanelSurface.swift`
- Modify: `Sources/MenuHub/HubItemActionPanelState.swift`
- Modify: `Tests/MenuHubTests/PanelNavigationTests.swift`

- [ ] **Step 1: Write failing appearance and command-order tests**

```swift
func testActionPanelSurfaceUsesOpaqueFallbackWhenTransparencyIsReduced() {
    XCTAssertEqual(HubActionPanelSurfaceMode.resolve(reduceTransparency: true, supportsLiquidGlass: true), .solid)
    XCTAssertEqual(HubActionPanelSurfaceMode.resolve(reduceTransparency: false, supportsLiquidGlass: false), .material)
    XCTAssertEqual(HubActionPanelSurfaceMode.resolve(reduceTransparency: false, supportsLiquidGlass: true), .liquidGlass)
}

func testActionPanelCommandsReflectCapabilitiesAndExpansion() {
    XCTAssertEqual(
        HubItemActionPanelCommand.visible(canOpenHost: true, hasGroups: true, showsMore: false),
        [.primary, .openHost, .favorite, .rename, .groups, .more]
    )
    XCTAssertEqual(
        HubItemActionPanelCommand.visible(canOpenHost: false, hasGroups: false, showsMore: true),
        [.primary, .favorite, .rename, .more, .retest, .management, .ignore]
    )
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run `swift test --filter PanelNavigationTests`.

Expected: compilation fails for missing surface mode and command definitions.

- [ ] **Step 3: Implement semantic modes and commands**

Add a pure resolver and command order:

```swift
enum HubActionPanelSurfaceMode: Equatable {
    case solid, material, liquidGlass

    static func resolve(reduceTransparency: Bool, supportsLiquidGlass: Bool) -> Self {
        if reduceTransparency { return .solid }
        return supportsLiquidGlass ? .liquidGlass : .material
    }
}

enum HubItemActionPanelCommand: Hashable {
    case primary, openHost, favorite, rename, groups, more, retest, management, ignore

    static func visible(canOpenHost: Bool, hasGroups: Bool, showsMore: Bool) -> [Self] {
        var result: [Self] = [.primary]
        if canOpenHost { result.append(.openHost) }
        result += [.favorite, .rename]
        if hasGroups { result.append(.groups) }
        result.append(.more)
        if showsMore { result += [.retest, .management, .ignore] }
        return result
    }
}
```

Implement reusable view modifiers/styles:

```swift
struct HubActionPanelSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let supportsGlass: Bool
        if #available(macOS 26.0, *) { supportsGlass = true } else { supportsGlass = false }
        switch HubActionPanelSurfaceMode.resolve(reduceTransparency: reduceTransparency, supportsLiquidGlass: supportsGlass) {
        case .solid:
            content.background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 28, style: .continuous))
        case .material:
            content.background(.regularMaterial, in: .rect(cornerRadius: 28, style: .continuous))
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
            }
        }
    }
}
```

Use semantic colors and a rounded command button style whose pressed scale becomes `1` under Reduce Motion.

- [ ] **Step 4: Run focused tests and both architecture builds**

```bash
swift test --filter PanelNavigationTests
swift build --arch arm64
swift build --arch x86_64
```

Expected: tests pass and both builds compile the guarded macOS 26 branch while preserving the macOS 14 deployment target.

- [ ] **Step 5: Commit the visual primitives**

```bash
git add Sources/MenuHub/HubActionPanelSurface.swift Sources/MenuHub/HubItemActionPanelState.swift Tests/MenuHubTests/PanelNavigationTests.swift
git commit -m "feat: add adaptive glass action surfaces"
```

### Task 3: Extract and Build the Action Panel

**Files:**
- Create: `Sources/MenuHub/HubItemActionPanel.swift`
- Modify: `Sources/MenuHub/HubItemRow.swift`
- Modify: `Tests/MenuHubTests/PanelNavigationTests.swift`

- [ ] **Step 1: Add failing integration assertions**

Add a testable configuration value that proves list/grid parity and callback availability:

```swift
func testActionPanelConfigurationIsIndependentOfCatalogLayout() {
    let row = HubItemActionPanelConfiguration(canOpenHost: true, hasGroups: true, isInvoking: false)
    let grid = HubItemActionPanelConfiguration(canOpenHost: true, hasGroups: true, isInvoking: false)
    XCTAssertEqual(row.visibleCommands(showsMore: false), grid.visibleCommands(showsMore: false))
}
```

Run `swift test --filter PanelNavigationTests` and expect compilation failure for the missing configuration.

- [ ] **Step 2: Implement the focused panel view**

Create `HubItemActionPanel` with a single initializer carrying the existing item values and callbacks:

```swift
struct HubItemActionPanel: View {
    let item: HubPanelItem
    let canOpenHost: Bool
    let groups: [HubItemActionGroup]
    let isInvoking: Bool
    let hasFailure: Bool
    let primaryAction: () -> Void
    let openHost: () -> Void
    let toggleFavorite: () -> Void
    let saveAlias: (String?) -> Void
    let setMembership: (UUID, Bool) -> Void
    let ignore: () -> Void
    let retestCapability: () -> Void
    let openManagement: () -> Void
    let dismiss: () -> Void
    @Binding var state: HubItemActionPanelState
}
```

The body must implement:

- a 42-point real host icon, title, semantic subtitle, and readiness status;
- one accent-tinted 42-point primary action;
- rounded 38-point Open Host and Favorite command surfaces;
- Rename and Groups transitions without dismissing the popover;
- an in-place More Actions disclosure;
- Retest, Management, and destructive Ignore commands;
- an inline rename editor with Clear, Cancel, and Save;
- a group membership list with native checkmarks;
- stable identifiers such as `hub.item.actions.primary`, `.rename`, `.groups`, `.more`, and `.ignore`;
- a 340–360 point preferred width with flexible vertical height and semantic leading/trailing layout.

All actions that leave the panel call `dismiss()` before invoking the existing callback. Group membership keeps the panel open. Alias save trims whitespace and sends `nil` for an empty alias.

- [ ] **Step 3: Add keyboard focus and layered Escape**

Use `@FocusState private var focusedCommand: HubItemActionPanelCommand?`, apply `.focused` to visible command buttons, and route key presses:

```swift
.onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
.onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
.onKeyPress(.escape) {
    if state.handleEscape() == .dismiss { dismiss() }
    return .handled
}
```

Set initial focus to `.primary` when the commands page appears. In rename mode, focus the text field; Return saves and Escape cancels before the popover can close.

- [ ] **Step 4: Replace the inline view in `HubItemRow`**

Remove `actionPopover` and `aliasEditor`. Initialize/present the reducer with `item.record.alias`, then attach:

```swift
.popover(isPresented: $actionMenuState.isPresented, arrowEdge: .trailing) {
    HubItemActionPanel(
        item: item,
        canOpenHost: canOpenHost,
        groups: groups,
        isInvoking: isInvoking,
        hasFailure: hasFailure,
        primaryAction: action,
        openHost: openHost,
        toggleFavorite: toggleFavorite,
        saveAlias: saveAlias,
        setMembership: setMembership,
        ignore: ignore,
        retestCapability: retestCapability,
        openManagement: openManagement,
        dismiss: { actionMenuState.dismiss() },
        state: $actionMenuState
    )
}
```

Keep `sharedMenuActions` as the native context-menu representation of the same callbacks.

- [ ] **Step 5: Run focused and complete tests**

```bash
swift test --filter PanelNavigationTests
swift test
```

Expected: the focused configuration/reducer tests pass and the complete suite has zero failures.

- [ ] **Step 6: Commit the extracted panel**

```bash
git add Sources/MenuHub/HubItemActionPanel.swift Sources/MenuHub/HubItemRow.swift Tests/MenuHubTests/PanelNavigationTests.swift
git commit -m "feat: redesign item actions as a glass panel"
```

### Task 4: Complete Localization and Accessibility Copy

**Files:**
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
- Modify: `Tests/MenuHubTests/LocalizationTests.swift`

- [ ] **Step 1: Add failing required-key tests**

Extend the localization manifest with:

```swift
let actionPanelKeys = [
    "actionPanel.menuBarItem", "actionPanel.ready", "actionPanel.quickActions",
    "actionPanel.customize", "actionPanel.rename", "actionPanel.groups",
    "actionPanel.moreActions", "actionPanel.displayName", "actionPanel.optional",
    "actionPanel.cancel", "actionPanel.keyboardDefault", "actionPanel.keyboardRename"
]
```

Run `swift test --filter LocalizationTests`; expect missing-key failures for all localization bundles.

- [ ] **Step 2: Add natural translations in all ten languages**

Add complete values for every key. English source values are:

```text
Menu bar item
Ready
Quick Actions
Customize
Rename
Groups
More Actions
Display Name
Optional
Cancel
↑↓ Select · ↩ Activate · Esc Close
Return Save · Esc Cancel
```

Translations must be authored as complete phrases, preserve macOS terminology, and not concatenate dynamic fragments. Reuse existing localized Favorite, Clear, Save, Retest, Management, and Ignore strings where their meanings already match.

- [ ] **Step 3: Verify localization coverage**

Run `swift test --filter LocalizationTests`.

Expected: every supported bundle contains every required key and no value falls back to the key name.

- [ ] **Step 4: Commit localization**

```bash
git add Resources Tests/MenuHubTests/LocalizationTests.swift
git commit -m "feat: localize the glass action panel"
```

### Task 5: UI Regression Coverage and Visual Verification

**Files:**
- Modify: `Tests/MenuHubUITests/MenuHubUITests.swift`
- Modify: `Sources/MenuHub/HubItemActionPanel.swift` only if verification reveals a defect

- [ ] **Step 1: Add UI smoke coverage**

Use the existing launch fixture to select a catalog item, open Actions with Command-K, and assert:

```swift
XCTAssertTrue(app.otherElements["hub.item.actions.panel"].waitForExistence(timeout: 3))
XCTAssertTrue(app.buttons["hub.item.actions.primary"].exists)
XCTAssertTrue(app.buttons["hub.item.actions.rename"].exists)
XCTAssertTrue(app.buttons["hub.item.actions.more"].exists)
```

Activate Rename and assert `hub.item.actions.aliasField` receives focus. Press Escape and verify the editor disappears while the panel remains; press Escape again and verify the panel closes.

- [ ] **Step 2: Run non-UI Xcode tests**

```bash
xcodegen generate
xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS' -skip-testing:MenuHubUITests CODE_SIGNING_ALLOWED=NO
```

Expected: core and app tests pass with zero failures.

- [ ] **Step 3: Build and run signed local UI tests**

```bash
xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS' -only-testing:MenuHubUITests
```

Expected: the new action-panel flow and existing grid/list keyboard tests pass. If macOS blocks the runner for an environmental signing reason, record the exact reason and manually run the same acceptance flow in the installed signed app.

- [ ] **Step 4: Manually verify appearance and behavior**

Check dark/light appearance, Reduce Transparency, Increase Contrast, Reduce Motion, a long localization, list layout, icon-grid layout, action failure/retry, and the macOS 26 glass rendering. Capture screenshots for the release evidence directory without committing user-specific desktop content.

- [ ] **Step 5: Commit UI coverage and fixes**

```bash
git add Tests/MenuHubUITests/MenuHubUITests.swift Sources/MenuHub/HubItemActionPanel.swift
git commit -m "test: cover glass action panel interactions"
```

### Task 6: Build, Package, and Install Locally

**Files:**
- Modify: `VERSION`
- Modify: `project.yml`

- [ ] **Step 1: Advance the version to 0.1.5**

Set `VERSION` to `0.1.5` and `MARKETING_VERSION` in `project.yml` to `0.1.5`.

- [ ] **Step 2: Validate version and build release artifacts**

```bash
./scripts/validate-version.sh v0.1.5
BUILD_ONLY=1 ./scripts/build-release.sh
RELEASE_KIND=unsigned ./scripts/package-release.sh
./scripts/validate-release-artifacts.sh
```

Expected: arm64 and x86_64 apps build and exactly two DMGs, two ZIPs, and four checksum files validate.

- [ ] **Step 3: Install the arm64 build safely**

Quit the running Menu Hub process, move the existing `/Applications/Menu Hub.app` to a timestamped temporary backup, copy the new arm64 app into `/Applications`, verify its signature and architecture, then launch it.

Expected:

```text
CFBundleShortVersionString = 0.1.5
Architectures in the fat file or executable = arm64
codesign verification = valid on disk
```

- [ ] **Step 4: Exercise the installed app**

Open the panel with Option-M, open an item's action panel from Icon Grid, traverse commands with Up/Down, run a safe item, open/cancel Rename, expand More Actions, and confirm no new Menu Hub crash report appears.

- [ ] **Step 5: Commit the version bump**

```bash
git add VERSION project.yml MenuHub.xcodeproj
git commit -m "chore: prepare v0.1.5"
```

### Task 7: Review, Merge, and Publish v0.1.5

**Files:**
- No source changes unless review or CI finds a defect

- [ ] **Step 1: Run final verification**

Run `swift test`, the Xcode non-UI suite, both architecture release builds, artifact validation, `git diff --check`, and `git status --short`.

Expected: zero failures, valid artifacts, and a clean worktree.

- [ ] **Step 2: Push the feature branch and open a pull request**

Push `codex/status-badge-action-recovery`, create a ready-for-review pull request into `main`, and include test, installed-app, compatibility, and unsigned-preview status in the body.

- [ ] **Step 3: Wait for CI and merge**

Verify every required check succeeds. Merge the pull request only after the remote head matches the locally verified commit.

- [ ] **Step 4: Tag the exact main commit**

Create and push annotated tag `v0.1.5` on the merged `main` commit. Do not move or recreate an existing public release tag.

- [ ] **Step 5: Verify the GitHub Release**

Wait for the release workflow to publish the public prerelease and verify it contains exactly eight downloadable assets: arm64/x86_64 DMG, arm64/x86_64 ZIP, and their checksum files. Record the release URL and any unsigned Gatekeeper instructions in the handoff.
