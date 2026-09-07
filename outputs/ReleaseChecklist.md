# Menu Hub Release Checklist

## Current Phase 0 status

- [x] Swift 6 and macOS 14 deployment configured.
- [x] Native `.app` target with `LSUIElement=true`.
- [x] App Sandbox disabled for the Accessibility-dependent app target.
- [x] Hardened Runtime configured for signed builds.
- [x] No third-party runtime or package dependency.
- [x] No networking, analytics, account, injection, private API, Screen Recording, or screenshot implementation.
- [x] SwiftPM unit tests and Xcode build automation available.
- [ ] Hidden-state AXPress matrix completed for 15 representative items.
- [ ] macOS 14 hardware verification completed.
- [ ] Latest stable macOS hardware verification completed.
- [ ] Notch, non-notch, external-display, full-screen, sleep/wake, and SystemUIServer recovery verified.
- [ ] Phase 0 gate marked PASS.

MVP implementation and product release remain blocked until every Phase 0 item above passes.

## Future distribution checks

- [ ] Configure an actual Developer ID Application team and certificate.
- [ ] Archive a Release build with Hardened Runtime.
- [ ] Confirm release entitlements do not contain `get-task-allow`.
- [ ] Verify every executable and embedded framework with `codesign --verify --deep --strict --verbose=2`.
- [ ] Verify Gatekeeper assessment with `spctl --assess --type execute --verbose=4`.
- [ ] Submit with `notarytool`, wait for acceptance, and staple the ticket.
- [ ] Test installation and first permission flow on a clean Mac without development certificates.
- [ ] Produce a notarized ZIP or DMG and publish its SHA-256.

No signing or notarization result is claimed in this repository because no release identity or Apple notary credentials were supplied.
