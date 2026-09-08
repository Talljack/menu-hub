# Menu Hub DMG and ZIP Release Design

## Goal

Every semantic version tag must create a visible GitHub Release containing both a directly installable DMG and a ZIP archive. Missing Apple credentials must never make the Releases page silently empty or misrepresent an unsigned build as notarized.

## Artifacts

- Build one Universal macOS application containing `arm64` and `x86_64` slices.
- Produce `Menu-Hub-<version>-macos-universal.dmg` with `Menu Hub.app` and an `/Applications` shortcut for drag installation.
- Produce `Menu-Hub-<version>-macos-universal.zip` for update tools and manual extraction.
- Produce SHA-256 files for both artifacts.
- Validate the ZIP, DMG image, application architecture, bundle version, and signature state before upload.

## Release channels

- When all signing and notarization secrets are present, CI signs the app with Developer ID and Hardened Runtime, notarizes it with Apple, staples the ticket, verifies Gatekeeper acceptance, packages the stapled app, and creates a normal GitHub Release.
- When credentials are incomplete, CI packages the unsigned app with `-UNSIGNED` in both filenames, creates a GitHub pre-release titled `Unsigned Preview`, and includes an explicit Gatekeeper warning. It must not claim notarization or normal end-user readiness.
- Pull requests and `main` pushes build and upload DMG/ZIP workflow artifacts but do not create GitHub Releases.
- A `vX.Y.Z` tag creates exactly one release after confirming the tag matches `VERSION` and `MARKETING_VERSION`.

## Required GitHub secrets for a formal release

Developer ID signing:

- `APPLE_CERTIFICATE_P12_BASE64`: base64-encoded Developer ID Application certificate and private key exported as PKCS#12.
- `APPLE_CERTIFICATE_PASSWORD`: password protecting that PKCS#12 export.
- `APPLE_SIGNING_IDENTITY`: exact identity name, currently `Developer ID Application: Yugang Cao (636LV693YD)`.

Apple notarization:

- `APP_STORE_CONNECT_API_KEY_P8_BASE64`: base64-encoded App Store Connect API private key.
- `APP_STORE_CONNECT_KEY_ID`: key ID shown in App Store Connect.
- `APP_STORE_CONNECT_ISSUER_ID`: issuer ID shown in App Store Connect.

Secrets are supplied only to the specific signing/notarization steps and are never printed, committed, or embedded in artifacts. Exporting and uploading the local private signing key requires explicit user confirmation.

## Failure behavior

- Build, test, packaging, checksum, or artifact validation failure stops publication.
- A failed signed/notarized attempt must not fall back to an unsigned normal release.
- Missing credentials select the clearly marked unsigned pre-release path; invalid supplied credentials fail the workflow.
- Existing tags are immutable. The fixed workflow will be exercised with the next patch tag rather than moving `v0.1.0`.

## Verification

- Run the packaging script locally and verify both archive formats and checksums.
- Open the mounted DMG and verify the app plus Applications shortcut.
- Run the complete Swift test suite and Universal Release build.
- Validate the workflow through a pull request, merge it only after CI passes, and verify the post-merge artifacts.
- After user confirmation, release `v0.1.1`; verify that the GitHub Release is visible and that both DMG and ZIP assets can be downloaded.
