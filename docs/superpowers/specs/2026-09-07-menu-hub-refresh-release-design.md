# Menu Hub Refresh, Feedback, and Release Design

## Goal

Keep menu-bar badge titles fresh without performing a full Accessibility crawl and disk write every second, improve native macOS feedback and settings presentation, and make version tags produce reproducible Universal macOS release artifacts.

## Runtime design

- Opening the hub performs one full scan immediately.
- While the hub is visible, a one-second lightweight refresh reads only the previously resolved menu-bar elements. It updates runtime titles and capabilities without rediscovering every process.
- Full discovery runs every 20 seconds as a safety net and immediately when NSWorkspace reports an application launch or termination.
- Only one Accessibility operation may be in flight. Closing the hub cancels timers and outstanding work.
- User application filtering happens before Accessibility traversal when the process bundle path proves it is system infrastructure. Unknown processes remain eligible so helper-based user apps are not lost.

## Persistence and caching

- Runtime-only refreshes do not persist unchanged documents.
- Catalog mutations are compared against the previous document. Changed documents are saved through a five-second debounce; explicit shutdown flushes the last pending value.
- Host application metadata is cached by PID and bundle URL for the process lifetime and invalidated on application launch/termination.

## macOS UI design

- The footer contains a single Rescan control. Its label is replaced in place by a compact progress indicator while scanning, preventing horizontal movement and duplicated loading controls.
- Routine success shows a secondary “Updated just now” status that fades without changing panel height. Partial per-app failures stay behind each item’s action menu and diagnostics; only global failures appear in the panel.
- The Settings sidebar is wide enough for English and Simplified Chinese section names. Login-item unavailability includes a short explanation and a route to System Settings when actionable.
- Existing list/grid preference remains respected; controls use semantic colors, system spacing, and native compact control sizes.

## Release design

- `scripts/build-release.sh` validates a semantic `vX.Y.Z` version, generates the Xcode project, runs tests, and builds a Universal Release app.
- A tag-triggered GitHub Actions workflow runs on macOS, verifies the tag matches the project version, builds, packages, and uploads a ZIP plus SHA-256 checksum.
- Without Apple secrets, CI publishes an explicitly unsigned artifact. With Developer ID certificate and App Store Connect API-key secrets, it signs with hardened runtime, notarizes with `notarytool`, staples, verifies, and publishes the signed archive.
- `v0.1.0` is the first local release tag. No remote push is attempted without a configured remote.

## Verification

- Unit tests cover refresh cadence, non-overlap, debounce/flush, unchanged-document suppression, cache invalidation, status projection, and version validation.
- Full Swift tests, Xcode Release build, signature verification, installed-app launch, and real UI inspection are required before tagging.
