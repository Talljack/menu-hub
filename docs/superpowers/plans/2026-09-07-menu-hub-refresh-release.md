# Menu Hub Refresh and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver efficient live badge updates, native macOS feedback, and tag-driven Universal macOS releases.

**Architecture:** Split full discovery from targeted refresh, serialize and debounce persistence, cache immutable host metadata, and keep UI state projection in the panel model. Package releases through one local script shared by GitHub Actions.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Accessibility API, XCTest, XcodeGen, Bash, GitHub Actions.

---

### Task 1: Refresh policy and lightweight Accessibility refresh

**Files:**
- Modify: `Sources/MenuHubCore/Accessibility/AccessibilityServing.swift`
- Modify: `Sources/MenuHubCore/Accessibility/AccessibilityClient.swift`
- Modify: `Sources/MenuHub/CatalogController.swift`
- Modify: `Sources/MenuHub/HubPanelModel.swift`
- Test: `Tests/MenuHubCoreTests/AccessibilityPipelineTests.swift`
- Test: `Tests/MenuHubTests/HubPanelModelTests.swift`

- [ ] Add failing tests proving one initial full scan, one-second targeted refresh, twenty-second discovery, no overlap, and cancellation on close.
- [ ] Add a targeted refresh API that resolves known snapshots and rereads observable values without pressing them.
- [ ] Update the controller to reconcile targeted values in memory and perform full discovery only on policy triggers.
- [ ] Add NSWorkspace launch/termination invalidation and run the focused tests to green.

### Task 2: Debounced and change-aware persistence

**Files:**
- Modify: `Sources/MenuHub/CatalogController.swift`
- Test: `Tests/MenuHubTests/CatalogControllerTests.swift`

- [ ] Add failing tests for unchanged scan suppression, five-second coalescing, ordered saves, and shutdown flush.
- [ ] Introduce an injectable save debounce scheduler and compare persisted catalog content before scheduling a save.
- [ ] Keep explicit destructive/reset operations immediately durable and run controller tests to green.

### Task 3: Host metadata cache and pre-scan filtering

**Files:**
- Modify: `Sources/MenuHub/HostApplicationResolver.swift`
- Modify: `Sources/MenuHubCore/Accessibility/AccessibilityClient.swift`
- Test: `Tests/MenuHubTests/PanelNavigationTests.swift`
- Test: `Tests/MenuHubCoreTests/AccessibilityPipelineTests.swift`

- [ ] Add failing tests for repeated resolution, invalidation, and exclusion of proven system infrastructure.
- [ ] Cache metadata by PID/process bundle URL and invalidate on workspace lifecycle events.
- [ ] Apply a conservative pre-scan process predicate and run focused tests to green.

### Task 4: Native loading and feedback UI

**Files:**
- Modify: `Sources/MenuHub/HubPanelView.swift`
- Modify: `Sources/MenuHub/HubItemRow.swift`
- Modify: `Sources/MenuHub/SettingsView.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/MenuHubTests/HubPanelModelTests.swift`
- Test: `Tests/MenuHubTests/ManagementSettingsTests.swift`

- [ ] Add failing projection tests for transient updated state and per-item partial warning state.
- [ ] Replace the detached busy indicator with an in-place compact progress label and stable-width footer.
- [ ] Widen the Settings sidebar, add login-item guidance, and verify light/dark and list/grid fixtures.

### Task 5: Reproducible tag release

**Files:**
- Create: `.gitignore`
- Create: `VERSION`
- Create: `scripts/build-release.sh`
- Create: `scripts/validate-version.sh`
- Create: `.github/workflows/macos-release.yml`
- Create: `CHANGELOG.md`
- Modify: `docs/ReleaseChecklist.md`
- Modify: `project.yml`

- [ ] Add shell checks that fail for mismatched or malformed versions.
- [ ] Implement the shared Universal build/package/checksum script.
- [ ] Add a `v*` workflow with unsigned fallback and optional Developer ID signing/notarization.
- [ ] Initialize Git if required, commit the verified source baseline, and create local tag `v0.1.0` only after all gates pass.

### Task 6: Full verification and local installation

**Files:**
- Verify all modified files and generated artifacts.

- [ ] Run `swift test` and confirm zero failures.
- [ ] Run the release build script and confirm arm64 plus x86_64 output.
- [ ] Sign locally, verify the signature, replace `/Applications/Menu Hub.app` recoverably, and launch it.
- [ ] Exercise search, scrolling, loading placement, targeted title refresh, settings, and error feedback through the installed UI.
- [ ] Run `git status`, tag validation, and checksum verification before reporting completion.
