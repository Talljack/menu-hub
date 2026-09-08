# Menu Hub for macOS

English | [简体中文](README.zh-CN.md)

Menu Hub is a native macOS menu bar manager. Its always-visible four-petal Hub icon opens a compact panel where you can search, favorite, group, and activate accessible menu bar items.

The project uses Swift 6, SwiftUI, and AppKit, and requires macOS 14 or later. It does not use private APIs, Electron, code injection, Screen Recording, network services, analytics SDKs, or cloud storage.

> Menu Hub is an MVP, not yet a notarized public release. See the [MVP comparison audit](outputs/MVP-Comparison-Audit.md) for the exact validation status and known limitations.

## Using Menu Hub

- Click the four-petal Hub icon in the menu bar to open or close the panel.
- Press `⌥M` from any app to toggle the panel. You can change the shortcut under Settings > Shortcuts.
- Type to search. Use `↑` / `↓` to select, `Return` for the default action, `⌘Return` to open the host app, and `⌘K` for the action menu.
- Use `⌘1` through `⌘9` to activate favorites, `⌘F` to focus search, and `Esc` to clear search or close the panel.
- Option-click the Hub icon to hide or reveal the managed menu bar area. Right-click it to rescan, open Settings, restore the menu bar, or quit.
- The panel can show favorites, recent items, frequent items, custom groups, and all items. Every row leads with the resolved host app name so identical icons remain distinguishable.

Menu Hub prefers `AXPress` for actionable items. When an item cannot be pressed, it can fall back to opening the known host application. Unsupported items remain disabled and show a reason.

## Accessibility permission

The first-run guide explains why Accessibility is useful before macOS displays its permission prompt. You may skip it and continue in app-launcher mode.

To authorize Menu Hub:

1. Open the first-run setup, or go to Settings > Permissions & Privacy.
2. Choose Open System Settings.
3. Enable Menu Hub under Privacy & Security > Accessibility.
4. Return to Menu Hub. Permission is checked again when the app becomes active.

If macOS shows Menu Hub as enabled but the app still reports no access, choose Repair Permission. After explicit confirmation, Menu Hub resets only its own `com.local.MenuHub` Accessibility entry and opens System Settings again. It never resets another app's permission.

## Management and settings

The item manager supports searching, aliases, favorites, multiple groups, ordering, ignore/restore, capability retesting, last-seen information, and local error details. Group deletion can be undone.

Settings includes General, Appearance, Items & Groups, Shortcuts, Permissions & Privacy, and Diagnostics. It supports launch at login, restored hidden state, panel behavior, system/light/dark appearance, list/grid layout, language selection, shortcut recording, local data controls, privacy-redacted diagnostics, and emergency menu bar restoration.

The interface supports System Default, English, and Simplified Chinese. Reopen a window after changing the language; restart Menu Hub if any existing text remains unchanged.

## Build and test locally

Install XcodeGen and a Swift 6 toolchain, then run:

```sh
xcodegen generate
swift test
xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS'
xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Release \
  -derivedDataPath work/DerivedData clean build
open work/DerivedData/Build/Products/Release/MenuHub.app
```

Menu Hub is an `LSUIElement` app, so it does not show a Dock icon or a normal main window. Look for the Hub icon in the menu bar or press `⌥M`.

## Versioning and CI releases

The root `VERSION` file is the source of truth and must match `MARKETING_VERSION` in `project.yml`. To produce tested native builds for Apple Silicon (`arm64`) and Intel (`x86_64`) locally:

```sh
./scripts/build-release.sh
```

Every push or merge to `main` runs [.github/workflows/release.yml](.github/workflows/release.yml), which tests the project, builds both chip architectures, and uploads architecture-specific DMG and ZIP artifacts.

Pushing a `v*` tag always creates a visible GitHub Release. Without Apple credentials it is clearly marked as an unsigned pre-release and its filenames contain `-UNSIGNED`. With all of the following secrets, CI creates a Developer ID signed, notarized, and stapled normal release:

- `FORMAL_RELEASE_ENABLED` (`true` only when the formal UI release gate is ready)
- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APP_STORE_CONNECT_API_KEY_P8_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

Download `arm64` on Apple Silicon Macs and `x86_64` on Intel Macs. Each release provides a drag-to-Applications DMG and a ZIP containing `Menu Hub.app`.

Store formal-release secrets in the protected GitHub `release` environment. Tag jobs require approval there, and a release tag must point to the current `main` commit.

The Phase 0 probe remains available for public-API compatibility testing:

```sh
swift run FeasibilityProbe --output FeasibilityReport.md
swift run FeasibilityProbe --press-index 0 --output FeasibilityReport.md
```

## Privacy and local data

Catalogs, favorites, aliases, groups, preferences, and usage history remain on this Mac under:

```text
~/Library/Application Support/Menu Hub/
```

The catalog uses schema-versioned Codable JSON, atomic replacement, and a local recovery backup. Diagnostics are exported only after you choose a destination, and redact or hash home paths, user names, search text, and stable item identifiers.

## Public API limitations

macOS does not provide a public API that can guarantee enumeration, movement, hiding, and proxy activation for every third-party menu bar item. Menu Hub uses a transparent variable-width `NSStatusItem` to manage layout space and Accessibility APIs to discover and activate supported items.

- System-managed items such as Clock and Control Center are outside the hiding guarantee.
- Items without stable Accessibility metadata or `AXPress` support may only open their host app or remain unavailable.
- Long foreground-app menus, notched displays, and multi-display changes can still cause macOS to clip items. Menu Hub restores a safe revealed state when layout becomes uncertain.
- Compatibility must be verified on the target macOS, display arrangement, and third-party app versions.

## Documentation

- [Local validation report](outputs/LocalValidationReport.md)
- [MVP comparison audit](outputs/MVP-Comparison-Audit.md)
- [Release checklist](docs/ReleaseChecklist.md)
- [Phase 0 manual test checklist](docs/Phase0ManualTestChecklist.md)
- [Phase 0 feasibility report](FeasibilityReport.md)
