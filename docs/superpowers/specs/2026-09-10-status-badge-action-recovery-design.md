# Menu Bar Placement, Unread Badge, and Action Recovery Design

**Status:** Approved in conversation on 2026-09-10

**Target:** Menu Hub for macOS 14+, Swift 6, SwiftUI + AppKit

**Privacy:** Local-only; no networking, analytics, message-content access, private APIs, or injection

## 1. Goals

1. Make the Menu Hub status item visible as early as possible on first launch and preserve its user-adjusted position.
2. Add a compact, monochrome unread-count capsule to the Menu Hub status item.
3. Count only explicit numeric unread values from recognized chat applications or items the user explicitly includes.
4. Keep unread counts reasonably fresh while the panel is closed without continuously performing full Accessibility discovery.
5. Prevent scanning and invocation from racing with each other.
6. Make slow or temporarily unresponsive menu bar items recover cleanly without risking duplicate actions.

## 2. Platform Constraints

AppKit exposes creation, visibility, behavior, and autosave identity for an `NSStatusItem`, but it does not expose a public coordinate or ordering API. Menu Hub therefore cannot guarantee an absolute leftmost position, move ahead of another application's item, or move itself around a notch without private APIs.

Menu Hub will:

- create the primary status item before its spacer item;
- assign each item a stable, distinct `autosaveName`;
- keep the primary item square and visible when no unread count exists;
- let macOS restore the position after the user Command-drags the item;
- never reset a saved position during upgrades;
- keep the global shortcut available if macOS clips an item because of insufficient space.

This is a best-effort initial placement with reliable system-managed persistence, not a claim of forced positioning.

## 3. Unread Badge Experience

### 3.1 Appearance

The selected visual direction is **C: monochrome count capsule**.

- No unread count: render the existing Menu Hub template icon at square status-item width.
- Count from 1 through 99: render the icon followed by a compact rounded capsule containing the total.
- Count greater than or equal to 100, or any contributing exact-lower-bound value such as `99+`: render `99+`.
- The icon and capsule are one dynamically generated template image. The opaque parts use the system status-item tint and the digit cutouts reveal the menu bar behind them, so the result automatically reverses between light and dark appearances.
- The status item grows only enough to fit the capsule and returns to square width at zero.
- The hit target, native pressed highlight, left click, right click, Option-click, tooltip, and VoiceOver behavior remain unchanged.
- Increased Contrast is respected by using a solid template silhouette. No animation is required, so Reduce Motion needs no special branch.

The status item's accessibility label and tooltip include the localized unread total when nonzero, for example “Menu Hub, 14 unread messages.”

### 3.2 Exact-Number Rule

After trimming surrounding whitespace, only a status title made entirely of Unicode decimal digits and an optional trailing ASCII `+` is eligible. Digits embedded in app names, percentages, timers, network speeds, punctuation, or arbitrary prose are not parsed. Parsed digits are normalized to an integer and rendered with ASCII digits in the Menu Hub capsule.

Examples:

| Exposed title | Result |
| --- | --- |
| `14` | 14 |
| `99+` | lower bound 99; aggregate presentation is `99+` |
| `•` | ignored |
| `3 unread` | ignored |
| `Battery 83%` | ignored |
| `2026` in an app name | ignored |

Apps that expose only “has unread” without an exact number do not contribute a dot, plus sign, or estimated value.

### 3.3 Default Chat Classification

An item participates automatically only when its resolved host matches the built-in chat registry. Matching prefers normalized bundle identifiers and uses normalized host names only as a fallback.

The initial registry covers:

- Feishu / Lark
- WeChat
- WeCom
- QQ
- DingTalk
- Slack
- Microsoft Teams
- Telegram
- WhatsApp
- Discord
- Signal
- LINE
- KakaoTalk
- Viber
- Zoom Workplace
- Mattermost
- Zulip
- Element

Registry membership does not imply that an app exposes a usable menu bar number. It only permits a valid number to contribute if one is present.

Battery monitors, system monitors, network meters, timers, calendars, download managers, cloud-sync tools, and VPN tools are excluded by default.

### 3.4 Per-Item Override

Each catalog item gains a persisted tri-state preference:

- `automatic`: use the built-in chat classifier;
- `include`: count a valid numeric title regardless of classifier result;
- `exclude`: never count the item.

Existing catalog documents decode missing values as `automatic`. Encoding remains local in Menu Hub's existing Application Support catalog. The setting appears in Items & Groups management and uses a native Picker or menu labelled “Menu Hub Badge.” All ten existing localizations receive complete strings.

## 4. Count Model and Data Flow

`MenuHubCore` receives small, testable value types:

- `UnreadBadgePreference`
- `UnreadCountValue` (`exact(Int)` or `atLeast99`)
- `UnreadCountParser`
- `ChatApplicationClassifier`
- `UnreadBadgeAggregator`
- `UnreadBadgePresentation` (`hidden`, `count(Int)`, or `overflow`)

The aggregator consumes current catalog records and their current runtime Accessibility snapshots. It deduplicates by stable item identity, applies the override before parsing, uses saturating addition, and stops retaining exact totals once the result is known to be `99+`.

The controller/model publishes only a value presentation. `AppDelegate` subscribes and passes it to a focused AppKit renderer. SwiftUI remains the owner of catalog preferences; AppKit owns only status-item lifecycle and rendering.

No message bodies, notification text, contact names, or remote data are collected or stored.

## 5. Adaptive Refresh Architecture

The approved approach is adaptive lightweight polling:

- Panel visible: refresh known items every 1 second, retaining the current full-discovery cadence.
- Panel hidden: refresh only known items every 5 seconds.
- Every 20 seconds while actively viewing the panel, run full discovery as today.
- While hidden, run full discovery only after launch, app-set changes, wake, screen changes, permission restoration, or a manual Rescan.
- If automatic scanning is disabled, background unread monitoring also stops and the last successfully observed badge is cleared to avoid presenting stale data.
- Permission denial clears the badge and stops Accessibility work.
- Only a changed badge presentation triggers status-item redraw.

The existing scheduler is extended with an explicit monitoring mode instead of starting and destroying all live updates with the panel view lifecycle. `AppDelegate` starts background monitoring after permission coordination is ready. Panel appearance upgrades the mode; panel dismissal downgrades it.

## 6. Scan and Invocation Coordination

Only one Accessibility operation class may own the live pipeline at a time.

When invocation begins:

1. cancel and invalidate any scheduled or in-flight live refresh generation;
2. disable manual and automatic scan initiation for the duration of the invocation;
3. execute against the selected snapshot;
4. publish the outcome only if its generation is still current;
5. resume the appropriate visible or hidden monitoring mode;
6. schedule a known-item refresh after the invocation settles.

Cancellation cannot interrupt an Accessibility system call that is already executing. Late results are discarded, and no automatic retry is issued after an outer timeout because the original action may still complete.

## 7. Slow and Failed Action Recovery

- Increase the default outer press timeout from 500 milliseconds to approximately 1.2 seconds.
- Preserve the existing short retry for an immediate `cannotComplete` response.
- Preserve one rescan-and-retry for a verified stale or missing element.
- Never automatically repeat a timed-out press.
- Clear row failure emphasis and the bottom warning after approximately 3 seconds unless a newer failure replaces it.
- While a row is failed, its action menu changes the primary labels to “Retry” and “Open App” where host launch is available.
- Starting a retry clears the previous failure immediately.
- A failed action does not mark other rows, permanently disable Rescan, or leave the model in scanning state.

This favors safety over hiding errors: users see a brief, actionable failure without a modal alert, and Menu Hub avoids accidentally toggling a VPN or menu command twice.

## 8. Error Handling

- Integer parsing rejects negative, fractional, percentage, mixed-text, empty, and overflowing values.
- Missing runtime snapshots produce no contribution and no user-facing error.
- Custom decoding maps a missing or unknown persisted badge-preference value to `automatic`, so old and future catalog data cannot make the entire document fail to load.
- If dynamic template rendering fails, Menu Hub falls back to the existing icon and keeps all click behavior available.
- Scan failures do not replace a previously valid catalog, but the badge is cleared when the data cannot be considered current because permission was lost or automatic monitoring was explicitly disabled.

## 9. Testing Strategy

All production changes follow red-green-refactor.

### Core unit tests

- accepts exact integer and `99+` titles;
- rejects percentages, mixed prose, timers, names containing digits, dots, and empty strings;
- recognizes every default chat registry entry and rejects representative non-chat apps;
- applies `automatic`, `include`, and `exclude` correctly;
- deduplicates stable identities;
- sums exact values and saturates to `99+` without integer overflow;
- migrates old catalog JSON to `automatic`.

### App/model tests

- hidden monitoring uses the slower known-item cadence;
- visible monitoring uses the existing fast cadence and periodic discovery;
- permission loss and disabling automatic scanning clear the badge and stop work;
- invocation pauses refresh and resumes the correct mode;
- timeout does not issue a second press;
- stale elements still rescan and retry once;
- failure feedback clears after the bounded interval;
- retry and open-host actions publish the correct state.

### AppKit renderer tests

- zero, single-digit, double-digit, and `99+` presentations select correct dimensions;
- the rendered image is a template image;
- status item returns to square width at zero;
- localized tooltip and accessibility label update with the count;
- stable, distinct autosave names are assigned before use.

### UI tests and manual checks

- management exposes the tri-state override and persists it;
- dark and light menu bars render the capsule legibly;
- VoiceOver reads the count;
- left click, right click, Option-click, global shortcut, and Command-drag remain functional;
- a simulated slow item does not show a premature error;
- a simulated timeout shows bounded feedback and recovery actions;
- notch and external-display changes keep the status item usable;
- Release builds succeed for arm64 and x86_64.

## 10. Acceptance Criteria

1. Fresh installation creates the Menu Hub item before its spacer, without claiming or using forced placement.
2. User Command-dragged placement survives relaunch through stable autosave names.
3. A Feishu title of `14` produces a Menu Hub capsule of `14` within one background interval.
4. Multiple eligible exact counts are summed; `99+` is shown for overflow or a lower-bound input.
5. A WeChat item without a numeric title contributes zero.
6. Non-chat numeric menu items contribute zero in `automatic` and can contribute in `include`.
7. Changing an override updates the badge after the next successful refresh.
8. Automatic monitoring performs no continuous full discovery while the panel is hidden.
9. Invoking an item cannot overlap a newly started automatic scan.
10. A timed-out press is never automatically repeated.
11. Failure feedback clears automatically and exposes retry/open-host recovery.
12. Existing interaction, localization, privacy, signing, packaging, and dual-architecture tests remain green.

## 11. References

- Apple `NSStatusItem`: <https://developer.apple.com/documentation/appkit/nsstatusitem>
- Apple `NSStatusItem.autosaveName`: <https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename-swift.property>
- Apple `NSDockTile.badgeLabel` (documents only an app's own Dock tile): <https://developer.apple.com/documentation/appkit/nsdocktile/badgelabel>
- Slack badge semantics: <https://slack.com/help/articles/360025446073-Guide-to-Slack-notifications>
