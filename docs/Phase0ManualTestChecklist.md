# Menu Hub Phase 0 Manual Test Checklist

Do not mark a row passing from compilation alone. Record macOS build, hardware, display arrangement, target app/version, observed menu position, AX result, and recovery result.

## Setup and emergency recovery

1. Build and open `MenuHub.app`.
2. Open the Hub menu and choose **Show Setup Marker**.
3. Hold Command and drag the ⇆ marker immediately to the right of the third-party items under test.
4. Choose **Hide Items** and confirm the items to the marker's left leave the visible menu-bar region within about 180 ms.
5. Choose **Reveal Items** or Option-click the Hub icon and confirm every item returns.
6. If anything is unclear, choose **Restore Menu Bar** before continuing.

## Mandatory environments

- Built-in notch display, default and scaled resolution.
- One non-notch display.
- External display connected, disconnected, primary-display switched, and arrangement changed.
- A full-screen app on each display.
- 20 sleep/wake cycles.
- 20 external-display hot-plug cycles.
- SystemUIServer restart and target-app restart.
- 1000 consecutive hide/reveal operations.

For every layout change, the expected first reaction is immediate reveal. Any case that leaves items inaccessible is a Phase 0 failure.

## Accessibility and press matrix

Grant Accessibility only after selecting **Request Accessibility Permission…**. Do not grant Screen Recording. For each of at least 15 representative items, record discovery, resolved name, host, position, actions, visible press, hidden press, popup placement, timeout/stale behavior, and restore behavior.

System targets: Wi-Fi, Bluetooth, Sound, Battery. Third-party categories: two VPN, two sync, two recording, and at least one each of container, audio, clipboard, AI, and developer tools.

## Gate

Phase 0 passes only when discovery and hidden-state AXPress are reliable on macOS 14 and the latest stable macOS, recovery passes every mandatory environment, and the 15-item matrix contains real evidence. Otherwise retain the probe, stop MVP UI work, and revise the product to a spacer plus application launcher.
