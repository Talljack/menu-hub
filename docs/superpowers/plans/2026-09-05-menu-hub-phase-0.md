# Menu Hub Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify the public-API feasibility probe that gates Menu Hub MVP development.

**Architecture:** A Swift Package provides a native AppKit executable (`MenuHub`) and a separate command-line probe (`FeasibilityProbe`). Shared, testable source code owns spacer state, Accessibility value snapshots, AX error mapping, and report generation. Hardware-dependent validation stays explicit in `FeasibilityReport.md`; the implementation does not infer success from compilation.

**Tech Stack:** Swift 6, AppKit, SwiftUI, ApplicationServices Accessibility, XCTest/Swift Testing, macOS 14+

---

## File map

- `Package.swift`: macOS 14 SwiftPM project with app, probe, library, and test targets.
- `Sources/MenuHubCore/StatusBar/SpacerState.swift`: safe collapsed/expanded width state machine.
- `Sources/MenuHubCore/Accessibility/AccessibilityTypes.swift`: serializable snapshots, capability, and domain errors.
- `Sources/MenuHubCore/Accessibility/AccessibilityClient.swift`: the only wrapper that calls AX C APIs.
- `Sources/MenuHubCore/Feasibility/FeasibilityReport.swift`: deterministic Markdown report generation.
- `Sources/MenuHub/AppDelegate.swift`: two `NSStatusItem` prototype, recovery controls, display-change safety.
- `Sources/MenuHub/main.swift`: native agent-app entry point.
- `Sources/FeasibilityProbe/main.swift`: permission-aware AX scan and report writer.
- `Tests/MenuHubCoreTests/*`: state, AX mapping, and report tests.
- `FeasibilityReport.md`: recorded automated and manual feasibility evidence.
- `docs/Phase0ManualTestChecklist.md`: repeatable notch/multi-display/full-screen test protocol.

### Task 1: Project and red tests

- [ ] Create `Package.swift` with `MenuHubCore`, `MenuHub`, `FeasibilityProbe`, and `MenuHubCoreTests` targets, strict Swift 6 concurrency, and macOS 14 deployment.
- [ ] Write tests for crash-safe startup expansion, clamped spacer widths, AX error mapping, capability classification, and Markdown matrix output before creating production types.
- [ ] Run `swift test` and verify failure is caused by missing production symbols.

### Task 2: Minimal Phase 0 core

- [ ] Implement the spacer state machine and value-only AX snapshot model.
- [ ] Implement AX error mapping and capability derivation.
- [ ] Implement report rendering with explicit `pending`, `pass`, `fail`, and `blocked` states.
- [ ] Run `swift test` and require all tests to pass.

### Task 3: Native status-item probe

- [ ] Create a visible fixed-width Hub item and a transparent variable-width Spacer item.
- [ ] Make setup mode display a draggable marker; make normal mode visually transparent.
- [ ] Add Collapse, Expand/Restore, Setup Marker, Run AX Scan, and Quit actions.
- [ ] Persist only the requested collapsed width and last preference; always launch physically expanded before optionally re-collapsing.
- [ ] Observe screen-parameter and wake notifications and immediately restore the safe expanded width.
- [ ] Build the executable and launch it for a smoke test.

### Task 4: Accessibility feasibility probe

- [ ] Gate all AX traversal on `AXIsProcessTrusted`; prompt only from an explicit user action.
- [ ] Enumerate running applications on a serial actor, inspect bounded accessible descendants, and retain only ordinary value snapshots.
- [ ] Capture title fallback, role/subrole, identifier, position, size, supported actions, pid, process name, and bundle identifier.
- [ ] Resolve a selected candidate afresh and execute `kAXPressAction`; map failures without exposing raw codes as user-facing messages.
- [ ] Run the probe without Screen Recording permission and record the actual permission/discovery result.

### Task 5: Evidence and gate decision

- [ ] Generate `FeasibilityReport.md` from the current machine rather than claiming unperformed hardware results.
- [ ] Add a 15-row representative-app matrix and procedures for single display, notch, external display, resolution switch, full screen, wake, and SystemUIServer restart.
- [ ] Run `swift test`, `swift build`, and a release build; record exact results.
- [ ] If discovery, hidden-item press, or restoration is not empirically verified, mark the MVP gate blocked and retain all probe code.
- [ ] Only after all mandatory Phase 0 rows pass, create the separate MVP implementation plan and begin product UI.

## Risks and stop conditions

- Accessibility trees differ by application and macOS release; bounded traversal may find no usable menu-bar semantics.
- Pushing items outside visible width may invalidate or misplace their accessible press behavior.
- A software-only run cannot establish notch, external-display, full-screen, wake, or 15-app compatibility.
- The transparent spacer technique depends on user-controlled Command-drag order and public layout behavior, not a supported API for managing third-party items.
- Failure of discovery or hidden-item press on macOS 14/current stable stops MVP implementation; the supported fallback is a spacer plus application launcher with revised claims.
