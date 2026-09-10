# Icon Grid Keyboard Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every documented panel shortcut work visibly and consistently in Icon Grid mode.

**Architecture:** Reuse `HubItemRow` as the single interaction owner for both list rows and grid cells. `HubPanelView` supplies the grid style and the same callbacks/presentation ID; deterministic XCUITest launch arguments select grid layout for regression coverage.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest/XCUITest, XcodeGen

---

### Task 1: Add a failing Icon Grid keyboard regression test

**Files:**
- Modify: `Sources/MenuHub/UITestRuntime.swift`
- Modify: `Tests/MenuHubUITests/MenuHubUITests.swift`

- [ ] Add a `-uiTestLayout grid` launch argument that seeds `Preferences.layout = .grid`.
- [ ] Add `testIconGridKeyboardSelectionOpensSelectedItemActions`, launch the mixed grid fixture, press Down, press Command-K, and require `hub.item.actions.lark` to appear.
- [ ] Run `xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS,arch=arm64' -only-testing:MenuHubUITests/MenuHubUITests/testIconGridKeyboardSelectionOpensSelectedItemActions` and confirm it fails because the grid does not expose the action popover.

### Task 2: Share item interaction between list and grid

**Files:**
- Modify: `Sources/MenuHub/HubItemRow.swift`
- Modify: `Sources/MenuHub/HubPanelView.swift`
- Test: `Tests/MenuHubTests/PanelNavigationTests.swift`

- [ ] Add row/grid presentation styles to `HubItemRow`, retaining its existing action menu state, accessibility, context menu, and feedback logic.
- [ ] Render grid content with a native accent selection/hover background and a trailing more-actions button.
- [ ] Replace the standalone grid `Button` with the shared component and assign the canonical `all:<itemID>` scroll anchor.
- [ ] Add assertions that selected and hovered grid appearance resolve through the shared appearance state.
- [ ] Run `swift test --filter PanelNavigationTests` and confirm all navigation tests pass.
- [ ] Rerun the focused grid XCUITest and confirm the keyboard-opened actions popover exists.

### Task 3: Verify and install locally

**Files:**
- No source changes expected.

- [ ] Run `swift test` and require all package tests to pass.
- [ ] Run `xcodebuild test` for the focused grid XCUITest in light and dark appearances.
- [ ] Run `BUILD_ONLY=1 SKIP_TESTS=1 ./scripts/build-release.sh` and require arm64 and x86_64 artifacts.
- [ ] Install the arm64 app locally, launch it, and verify the installed version and process state.
- [ ] Commit the fix on `codex/fix-grid-shortcuts`; only after local verification, open and merge a pull request and publish the next patch release.
