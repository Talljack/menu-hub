# Menu Hub MVP Completion Design

Date: 2026-09-06
Status: User-approved design, pending written-spec review
Product baseline: `menu-hub-macos-product-engineering-spec.md`

## 1. Objective

Complete Menu Hub as a native macOS 14+ menu-bar utility using Swift 6, SwiftUI, and AppKit. The implementation must preserve the verified Phase 0 work, close the gaps between the current functional slice and the original MVP, and never claim compatibility that public macOS APIs cannot provide.

The current build can display the Menu Hub status item, scan accessible menu-bar elements, invoke compatible elements with Accessibility, show recent items, register a global shortcut, and restore its spacer state. It is not a complete MVP because favorites, frequent items, custom groups, aliases, manual ordering, management/settings windows, complete keyboard control, localization, durable model storage, login launch, diagnostics, onboarding, and the full compatibility matrix are not yet complete.

## 2. Confirmed Product Decisions

- Visual direction: A, “Native Inset Groups.”
- Global shortcut: Option-M (`⌥M`) by default.
- Language: follow the macOS language by default, with Simplified Chinese and English localizations and an in-app override.
- Permission experience: contextual, progressive Accessibility authorization with automatic rechecking and a useful degraded mode.
- Privacy: local-only data, no networking, analytics, cloud service, injection, private API, or Screen Recording permission.
- Compatibility claims: unsupported items show their actual limitation and a valid fallback action. Menu Hub does not promise universal proxying of Control Center or third-party status items.

## 3. Main Panel Design

The status-item popover remains a single-layer, transient Mac panel anchored to the Menu Hub icon. Its default width is 320 points. Height adapts from 180 to 520 points according to content and available screen space.

The panel has three layout regions:

1. A fixed header containing a 36-point search field. The field receives focus when the panel opens.
2. A single independently scrolling content region containing visible groups in this order: Favorites, Recent, Frequent, custom user groups, and All Items. Empty groups are omitted. Search replaces the grouped content with at most 12 ranked results.
3. A fixed footer containing keyboard guidance and a Settings entry. Rescan appears as a contextual action or status action rather than occupying list space permanently.

The scroll view reserves trailing space for its overlay scroller and for row actions. The row content and action target never occupy the scroller gutter. The system overlay scroller appears while scrolling and fades when idle. Subtle top and bottom edge fades communicate additional content without introducing a custom scrollbar. Trackpad inertial scrolling and discrete mouse-wheel scrolling both work. Search and footer never scroll away.

Rows remain compact for pointer use: 38-point primary row height, 22-point icon, semantic title and caption styles, and at least a 28-point action target. The whole row performs the default action. The trailing capability control is secondary and receives an explicit accessibility label. Hover, keyboard selection, pressed, progress, success, and failure states are visually distinct. System accent color is used for selection and action emphasis.

The visual language borrows iOS inset grouping, rounded surfaces, semantic hierarchy, and clear permission cards while retaining macOS density, pointer hover, right-click menus, keyboard navigation, system focus rings, transient-popover behavior, and standard settings windows. It uses semantic system colors and materials, supports light and dark appearances, and respects Reduce Transparency, Increase Contrast, Bold Text, and Reduce Motion.

## 4. Interaction Contract

Opening the panel focuses search. The default global shortcut is `⌥M`; the shortcut recorder rejects a bare letter, number, or modifier. Registration is tested before replacing the active shortcut. On conflict, the existing shortcut remains active and the user sees a localized conflict message.

Keyboard behavior:

- Up and Down move the selected row.
- Return invokes the selected item's default action.
- Command-Return opens the host application.
- Command-K opens the selected item's action menu.
- Command-F focuses search.
- Command-1 through Command-9 invoke favorite positions.
- Escape clears a nonempty search first and closes the panel when search is empty.

Mouse behavior:

- Clicking a row invokes its default supported action.
- Right-click exposes Favorite/Unfavorite, Alias, Add to Group, Ignore, Retest Capability, and Open Host App as applicable.
- Option-clicking the Menu Hub status item toggles the hidden region.
- Right-clicking the Menu Hub status item opens the minimal maintenance menu: Hide/Show, Rescan, Settings, Restore Menu Bar, and Quit.

Every action acknowledges input immediately. Slow Accessibility work shows inline progress without blocking the whole panel. Errors remain visible in context and do not automatically close the panel.

## 5. Item Capabilities and Degraded Behavior

Each catalog item records supported actions and reports one of these user-facing outcomes:

- Press: Menu Hub can invoke the Accessibility press action.
- Open App: direct proxy action is unavailable, but the host app can be activated.
- Unavailable: neither a reliable press nor a valid launch fallback exists.

Capability text and icon are both shown when needed; color is never the only signal. The UI must not render a press affordance for a known unsupported item. Stale Accessibility elements are re-resolved before invocation. Timeout, invalid element, missing action, permission loss, and host termination map to distinct domain errors and localized recovery guidance.

If Accessibility permission is absent, Menu Hub remains usable in launcher mode using locally known host applications. Features that require Accessibility are visibly disabled with an explanation and authorization entry point.

## 6. Permission and Onboarding Flow

Accessibility permission is requested in context, not immediately at process launch. First-run onboarding contains no more than the original required steps and permits back navigation and permission skipping.

Before the system prompt, Menu Hub explains that Accessibility is used to read menu-item names and perform only user-requested actions; it also states that data remains on the Mac. “Open System Settings” navigates to the correct Privacy & Security pane.

The permission coordinator rechecks trust when the app becomes active, when the panel opens, before scans, and before invocation. Returning from System Settings after granting permission automatically transitions to authorized state and starts a scan. It does not repeatedly show the authorization prompt.

If trust remains false while System Settings shows the switch enabled, the repair flow explains that a changed app signature or installation identity may have invalidated the old record. A user-confirmed repair can reset the Menu Hub Accessibility entry, relaunch the stable `/Applications/Menu Hub.app` identity, and guide the user through authorization again. No reset occurs silently.

## 7. Localization

All user-visible strings use localization resources. Simplified Chinese and English cover the panel, status menu, onboarding, management window, settings pages, error messages, permission explanations, capability labels, diagnostics, accessibility labels, and help text.

The default language follows macOS. A General setting offers System Default, 简体中文, and English. Changing it updates application UI consistently; if macOS APIs require relaunch for complete menu localization, the UI states this and offers a relaunch action. Search matches localized display names, aliases, original names, host application names, and group names. Chinese pinyin search remains version 1.1 scope as defined by the product baseline.

## 8. Catalog, Groups, and Persistence

The catalog uses the original stable identity model and stores item metadata, capabilities, discovery timestamps, invocation statistics, user aliases, favorite state, group membership, and manual ordering locally.

Recent contains up to eight successfully invoked items from the last 14 days, newest first. Frequent uses successful invocations from a rolling 30-day window, deduplicates repeats within 30 seconds, and requires at least three successful invocations. A user item can belong to multiple groups. Removing a group never removes its items.

Persistence uses versioned JSON with atomic replacement, backup recovery, and explicit migration tests. UserDefaults is limited to small preferences where appropriate. Corrupt data produces a recoverable diagnostic error and restores the last valid backup rather than silently discarding user organization.

## 9. Management and Settings

The management window is a standard resizable macOS window. It provides all-item search, aliases, favorites, grouping, ordering, ignoring, capability inspection, last-seen/error information, and capability retesting. Dragging changes Menu Hub's internal order only and never implies rearrangement of third-party status items.

The Settings scene contains:

- General: launch at login, restore previous hidden state, close on focus loss, close after successful trigger, automatic scanning, and language.
- Appearance: System/Light/Dark, compact list or icon grid, group headings, and capability visibility.
- Items & Groups: entry to management and local organization controls.
- Shortcuts: panel, hide/show, favorite 1–9, conflict status, and restore defaults.
- Permissions & Privacy: live Accessibility status, system settings, purpose, local data location, export/clear data, and no-network statement.
- Diagnostics: rescan, rebuild index, restore menu bar, export redacted diagnostics, app/macOS versions, and recent error codes.

Launch at login uses the public ServiceManagement API. Diagnostics are explicitly exported by the user and redact usernames, home-directory paths, free-form search queries, and unrelated process details.

## 10. Architecture

Existing Phase 0 code is preserved as evidence and separated from production services. Production responsibilities are divided behind protocols so they can be tested without the live Accessibility tree:

- AppShell owns lifecycle and scene activation.
- StatusBarController owns visible Hub and spacer status items.
- PanelController owns presentation, focus, and dismissal.
- PermissionCoordinator owns Accessibility state transitions and repair guidance.
- AccessibilityClient performs public AX queries and actions.
- MenuBarScanner discovers candidates and emits normalized observations.
- ItemResolver maps observations to stable catalog records and re-resolves stale elements.
- ActionExecutor chooses Press/Open App/Unavailable and records successful invocations.
- CatalogStore owns versioned, atomic local persistence.
- SearchIndex performs normalized ranking and stable ordering.
- SmartGroupEngine derives Recent and Frequent groups.
- HotKeyController validates, registers, replaces, and reports shortcuts.
- Diagnostics records bounded, redacted local events and creates exports.

UI models depend on protocols and immutable snapshots. Accessibility calls run off the main actor with bounded timeouts; published UI state and AppKit presentation remain on the main actor.

## 11. Recovery and Safety

The spacer's last known safe width and hidden state are persisted. Restore Menu Bar is available from the status-item menu even when scanning or permission handling fails. On incompatible display changes, invalid geometry, or startup uncertainty, the implementation prefers the fully restored state. It never leaves the menu bar intentionally hidden after an unhandled failure.

The product does not use private status-item APIs or claim it can physically reorder arbitrary third-party items. Phase 0 evidence remains part of the repository. If the required hidden-region or enumeration behavior fails on a supported OS/display configuration, that behavior is disabled for the affected configuration and the launcher fallback remains available.

## 12. Verification and Completion Criteria

Automated coverage includes search normalization/ranking/performance, stable IDs, recent/frequent rules, group behavior, persistence/migration/backup, AX error mapping, permission state transitions, hotkey conflicts, scanner/resolver/action integration with fakes, and localization key completeness. UI tests cover onboarding, permission skipping, keyboard flows, persistence, revoked permission, empty/error states, appearance variants, and accessibility labels where automation is reliable.

The local release workflow must:

1. Run all unit and integration tests.
2. Build the Release configuration with Swift 6 and macOS 14 deployment target.
3. Validate signing, hardened runtime, bundle identity, localized resources, and absence of prohibited networking/analytics dependencies.
4. Install the signed build to `/Applications/Menu Hub.app` without leaving duplicate running identities.
5. Launch it and verify the visible status icon, `⌥M`, popover positioning, nonoverlapping scroll UI, search, mouse and keyboard invocation, favorites, groups, aliases, persistence, both languages, permission recovery, diagnostics, and full restoration.
6. Compare the result with the original MVP acceptance criteria and report every unverified hardware or OS matrix item explicitly.

“Complete” means the software and automated tests satisfy the MVP contract and the local Mac validation passes. It does not mean unperformed notch, external-display, alternate-hardware, beta-macOS, 1,000-cycle, or notarization checks have passed. Those remain clearly labeled until evidence exists.
