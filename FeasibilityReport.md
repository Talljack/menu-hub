# Menu Hub Phase 0 Feasibility Report

Generated: 2026-09-06T14:19:31Z

MVP gate: BLOCKED

> A build result is not hardware compatibility evidence. PENDING and BLOCKED checks must not be treated as passing.

## Environment

- macOS: Version 26.5.2 (Build 25F84)
- Hardware: Apple Silicon (arm64)
- Screens detected: 1
- Accessibility trusted: yes

## Automated checks

| Check | Status | Evidence |
|---|---|---|
| Public API build | PASS | Probe is running with AppKit and ApplicationServices. |
| Accessibility permission | PASS | AXIsProcessTrusted returned true. |
| Menu-bar candidate discovery | PASS | Found 40 candidate(s). Bob (pid 952): staleElement Bob Graphics and Media (pid 19355): targetUnresponsive Bob Networking (pid 19356): targetUnresponsive CC Switch Graphics and Media (pid 52660): targetUnresponsive CC Switch Networking (pid 52661): targetUnresponsive Grammarly Desktop Graphics and Media (pid 7422): targetUnresponsive Grammarly Desktop Networking (pid 7423): targetUnresponsive Grammarly Desktop Uninstaller (pid 11549): targetUnresponsive Grammarly Desktop Web Content (pid 7424): targetUnresponsive Raycast Graphics and Media (pid 1378): targetUnresponsive Raycast Networking (pid 1380): targetUnresponsive Raycast Web Content (pid 1381): targetUnresponsive Superhuman Web UI Graphics and Media (pid 7851): targetUnresponsive Superhuman Web UI Networking (pid 7852): targetUnresponsive Universal Control (pid 938): targetUnresponsive WemeetExternal (pid 55466): targetUnresponsive WemeetExternal (pid 32535): targetUnresponsive WemeetExternal (pid 68301): targetUnresponsive |
| Hidden-item AXPress | PENDING | Collapse the spacer, then rerun with --press-index N for an explicitly selected candidate. |

## Representative target matrix

| Target | Category | Status | Evidence |
|---|---|---|---|
| Wi-Fi | System | PENDING | Not tested on this machine |
| Bluetooth | System | PENDING | Discovery candidate matched 'Bluetooth'; hidden-state press still requires user verification. |
| Sound | System | PENDING | Not tested on this machine |
| Battery | System | PENDING | Discovery candidate matched 'Battery'; hidden-state press still requires user verification. |
| VPN A | VPN | PENDING | Not tested on this machine |
| VPN B | VPN | PENDING | Not tested on this machine |
| Sync A | Cloud sync | PENDING | Not tested on this machine |
| Sync B | Cloud sync | PENDING | Not tested on this machine |
| Recorder A | Screen recording | PENDING | Not tested on this machine |
| Recorder B | Screen recording | PENDING | Not tested on this machine |
| Container tool | Development | PENDING | Not tested on this machine |
| Audio tool | Audio | PENDING | Not tested on this machine |
| Clipboard tool | Productivity | PENDING | Not tested on this machine |
| AI tool | AI | PENDING | Not tested on this machine |
| Developer tool | Development | PENDING | Not tested on this machine |

## Manual layout and recovery checks

| Check | Status | Evidence |
|---|---|---|
| 1000 collapse/reveal cycles | PENDING | Run the repeatable UI protocol. |
| Built-in notch display | PENDING | Requires visual and click validation on notch hardware. |
| External display hot-plug | PENDING | Requires physical external display. |
| Scaled resolution change | PENDING | Requires interactive display setting change. |
| Full-screen application | PENDING | Requires interactive full-screen test. |
| Sleep and wake recovery | PENDING | Requires repeated physical sleep/wake. |
| SystemUIServer restart recovery | PENDING | Requires interactive recovery observation. |
| Hidden item remains AXPress actionable | PENDING | Requires explicit user-selected target press. |

## Decision

MVP implementation is stopped at the Phase 0 gate until discovery, hidden-item press, restoration, and the hardware matrix are empirically verified.
