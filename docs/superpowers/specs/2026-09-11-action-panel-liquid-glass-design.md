# Menu Hub Liquid Glass Action Panel Design

**Status:** Visual direction approved in conversation on 2026-09-11; specification awaiting final review

**Target:** Menu Hub for macOS 14+, Swift 6, SwiftUI + AppKit

**Selected direction:** A1 — native inset action panel, refined as a rounded, minimal, frosted-glass functional layer

## 1. Problem

The current item action popover is a vertically packed collection of plain buttons, separators, and an always-visible alias form. It exposes the required commands, but does not communicate hierarchy, feels visually rectangular, and makes a secondary configuration task compete with the primary action.

The replacement must feel native to macOS, preserve the application's keyboard-first behavior, remain usable on macOS 14 and later, and avoid presenting decorative transparency at the expense of legibility.

## 2. Goals

1. Make the default action visually immediate while keeping all existing item commands available.
2. Replace hard rectangular groups with a softer popover shell and individually rounded command surfaces.
3. Use system-backed translucency as a restrained functional layer, not as a content background.
4. Collapse editing and advanced commands until requested.
5. Preserve mouse, trackpad, keyboard, VoiceOver, localization, Reduce Motion, Reduce Transparency, and Increase Contrast behavior.
6. Keep list and icon-grid layouts behaviorally identical.

## 3. Information Architecture

The action panel is anchored to the selected item's ellipsis button and contains these regions in order:

### 3.1 Item header

- Host application icon, 42 by 42 points.
- Resolved item display name.
- Secondary label identifying it as a menu bar item, or the current editing context.
- Compact readiness status when useful. Do not show a green ready indicator for an unavailable item.

The header is informational and does not receive a glass effect of its own.

### 3.2 Primary action

A single full-width prominent control runs the item's current default action. Its localized label continues to adapt to launch-only and retry states. Return activates it while focus is outside an editor.

The button uses the system accent tint and a rounded rectangle. It is the only persistently tinted control in the panel.

### 3.3 Quick actions

- Open the resolved host application, when available.
- Add to Favorites or Remove from Favorites.

Each command is its own rounded surface. Commands use SF Symbols, text labels, and trailing keyboard hints where applicable.

### 3.4 Customize

- Rename.
- Group membership, when groups exist.
- More Actions disclosure.

Rename replaces the command content with an inline editor in the same popover. Group membership opens a compact nested menu or disclosure list and keeps checkmarks synchronized with the model. More Actions reveals Retest Capability, Show in Management, and Ignore Item.

Ignore Item remains destructive, is separated from frequent commands by hierarchy and disclosure, and uses the system destructive color. It must not become the visually dominant control.

### 3.5 Keyboard footer

A subtle, noninteractive footer summarizes context-valid keys only. It never displays shortcuts that do not work in the current state.

Default state:

- Up/Down: move selection between commands.
- Return: run the focused command, with the primary action as the initial command.
- Escape: close the action panel.

Rename state:

- Return: save when the text field is focused.
- Escape: cancel editing and return to the default action panel; a second Escape closes the panel.

## 4. Visual System

### 4.1 Shape and spacing

- Popover content target width: 340–360 points, allowed to grow for localization and Dynamic Type/accessibility text sizing.
- Outer continuous corner radius: approximately 28–30 points where the system presentation permits it.
- Primary control corner radius: approximately 14–15 points.
- Command surface corner radius: approximately 13–14 points.
- Inline editor corner radius: approximately 16–17 points.
- Base spacing unit: 4 points, composed primarily as 8, 12, and 16 point gaps.
- Minimum compact command height: 38 points; allow vertical expansion for wrapping localization.

Nested shapes maintain concentric curvature. The implementation must prefer system metrics and shapes over reproducing fixed CSS values literally.

### 4.2 Materials

The panel is a transient functional layer above the catalog, so it uses a regular, legibility-preserving glass/material treatment. Glass is not applied independently to every icon, label, or decorative inner view.

- On macOS 26 when built with an SDK that exposes Liquid Glass, use the native SwiftUI/AppKit glass APIs with availability checks.
- On macOS 14 and 15, and whenever the newer API is unavailable, use a system material backed by `NSVisualEffectView` or SwiftUI material rather than a simulated gradient or custom blur shader.
- If Reduce Transparency is enabled, replace translucent surfaces with the appropriate opaque semantic system background.
- If Increase Contrast is enabled, strengthen semantic borders and text contrast using system colors.
- Use the regular/readable variant for this text-heavy popover. Do not use highly clear glass over arbitrary desktop content.

Only the popover shell and key functional controls receive material emphasis. Standard content remains visually quiet.

### 4.3 Color and depth

- Use semantic system text, secondary text, fill, separator, accent, and destructive colors.
- Avoid decorative gradients inside production controls.
- Use one subtle outer elevation shadow and system-provided glass highlights.
- Hover and keyboard focus share the same selection model; hover adds a restrained surface lift rather than a saturated block.
- Pressed state uses a small opacity/scale response only when Reduce Motion is off.

### 4.4 Icons and typography

- Use SF Symbols for commands and status. Do not use text glyph approximations in production.
- Use the host application's actual icon only in the header.
- Use macOS semantic font styles and weights. Avoid oversized titles and all-caps section headings in localized production UI; compact section labels may use secondary styling without artificial letter spacing.

## 5. Interaction State Model

The popover owns an explicit presentation state rather than multiple unrelated booleans:

- `commands`
- `rename`
- `groups`
- `moreActionsExpanded`

The exact representation may be an enum plus disclosure state, but invalid combinations such as rename and group editing simultaneously must be impossible.

Opening the popover resets it to `commands`, initializes the alias draft from the latest record, and selects the primary action. Dismissing the popover cancels unsaved edits.

### 5.1 Invocation

- Selecting a command dismisses the popover before running actions that can open another menu or application.
- Existing invocation recovery, retry labels, disabled states, and progress feedback remain intact.
- While invocation is running, conflicting commands are disabled and the originating control shows system progress feedback.
- A failed action keeps the action panel available with Retry and Open App recovery choices.

### 5.2 Rename

- Rename is collapsed by default.
- Activating Rename transitions to the editor and focuses/selects the text field.
- Save trims the value and persists through the existing alias callback.
- Clear removes the alias and returns to the commands state after persistence succeeds.
- Cancel discards the draft.
- Empty localized placeholders never become saved aliases.

### 5.3 Groups

- Hide the Group command if no groups exist.
- Show membership with native checkmarks.
- Updating membership keeps the action panel open so multiple groups can be changed efficiently.
- Group names remain user content and may wrap or truncate with a tooltip; they must not be encoded into accessibility identifiers.

### 5.4 More Actions

- Advanced actions are collapsed by default.
- Disclosure expansion occurs in place with a short system animation unless Reduce Motion is enabled.
- Retest Capability and Show in Management use neutral styling.
- Ignore Item uses destructive styling and dismisses the panel before performing the action.

## 6. Keyboard and Accessibility

1. `Command-K` from either catalog layout opens this same panel for the selected item.
2. Initial keyboard focus goes to the primary action without stealing text focus when Rename is active.
3. Up and Down traverse enabled commands in visible order and skip static labels.
4. Return executes the focused command; Command-Return opens the host application when available.
5. Escape unwinds the innermost state before dismissing the popover.
6. Full Keyboard Access receives a visible native focus ring.
7. VoiceOver announces the panel, item name, command role, state, keyboard equivalent, and destructive action semantics.
8. Decorative material layers are hidden from the accessibility tree.
9. Existing right-click/context-menu commands remain available and use the same action labels and callbacks.

## 7. Localization and Layout Resilience

All new or changed strings are added to the existing localization catalog for every supported language. No English string is assembled from fragments. The panel must tolerate:

- German and Russian expansion;
- CJK labels;
- right-to-left layout for Arabic;
- long user aliases and group names;
- missing host application names;
- accessibility text size or increased contrast.

The width may grow within the usable screen frame; content must never be clipped offscreen. The panel uses native leading/trailing alignment so RTL order is correct without language-specific branches.

## 8. Implementation Boundaries

- Extract the production action panel from `HubItemRow` into a focused SwiftUI view and presentation-state model.
- Keep item action callbacks owned by the existing row/model boundary; the panel must not acquire Accessibility or persistence responsibilities.
- Reuse one action definition/source of truth for popover, context menu, and keyboard routing wherever practical to prevent label or availability drift.
- Use AppKit interop only for system material behavior or focus/window details SwiftUI cannot express reliably on the minimum deployment target.
- Do not add third-party UI dependencies, custom blur shaders, private APIs, networking, analytics, or stored visual snapshots of user applications.

## 9. Testing Strategy

Production changes follow red-green-refactor.

### 9.1 Unit tests

- opening and dismissing reset presentation state correctly;
- rename, groups, and more-actions states cannot conflict;
- Escape unwinds rename/groups/disclosure before dismissing;
- visible command order and availability match item capabilities;
- Retry/Open App labels appear after failure;
- no-group and no-host variants omit unavailable commands;
- alias save, clear, cancel, favorite, group, retest, management, ignore, primary action, and open-host callbacks fire exactly once;
- keyboard traversal skips static and disabled elements;
- Reduce Motion resolves to no custom transition.

### 9.2 View and integration checks

- list and grid layouts open the same extracted panel;
- Command-K opens the panel and Return executes the selected default action;
- rename field receives focus and keyboard commands do not leak to the catalog;
- the panel stays within each display's visible frame;
- all localization bundles contain the required keys;
- accessibility identifiers remain stable and do not include user content.

### 9.3 Manual visual checks

- light and dark appearances;
- vibrant and plain desktop backgrounds;
- Reduce Transparency, Increase Contrast, Reduce Motion, and Full Keyboard Access;
- RTL plus the longest supported localized labels;
- macOS 14 material fallback and macOS 26 native Liquid Glass path where available;
- notch display and external-display placement;
- hover, pressed, focus, disabled, progress, success, and failure states.

## 10. Acceptance Criteria

1. The action panel has a visibly softer continuous outer shape and no hard rectangular command groups.
2. The primary action is obvious without making secondary commands difficult to discover.
3. Alias editing and advanced actions are collapsed by default and remain fully keyboard accessible.
4. Every action that exists today remains reachable in list and icon-grid layouts.
5. The panel uses native Liquid Glass when available and a system-material fallback on the macOS 14 minimum target.
6. Reduce Transparency produces a legible opaque panel without lost borders or controls.
7. Long localized content and RTL layout remain readable and onscreen.
8. VoiceOver and Full Keyboard Access can operate every command.
9. Invocation recovery and exactly-once callback behavior remain unchanged.
10. All unit, integration, build, packaging, and existing regression tests pass before release.

## 11. References

- Apple Human Interface Guidelines, Materials: <https://developer.apple.com/design/human-interface-guidelines/materials>
- Apple, “Meet Liquid Glass”: <https://developer.apple.com/videos/play/wwdc2025/219/>
- Apple, “Get to know the new design system”: <https://developer.apple.com/videos/play/wwdc2025/356/>
- Apple, “Build an AppKit app with the new design”: <https://developer.apple.com/videos/play/wwdc2025/310/>
- Raycast, “A fresh look and feel”: <https://www.raycast.com/blog/a-fresh-look-and-feel>
