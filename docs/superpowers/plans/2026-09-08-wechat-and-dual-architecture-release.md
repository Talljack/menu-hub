# WeChat Badge Identity and Dual-Architecture Release Plan

## Goal

Fix title-only menu bar items such as WeChat when a numeric badge disappears, then publish separate Apple Silicon and Intel download artifacts.

## Tasks

1. Add regression tests for `1 -> unnamed WeChat` during full reconciliation and lightweight refresh/invocation.
2. Add a conservative identity transition that only accepts a badge-only value changing to the known host name (or the reverse) at the same bundle/path.
3. Run focused tests, the full Swift suite, and a Debug build.
4. Update release scripts and GitHub Actions to build `arm64` and `x86_64` separately and package each as DMG and ZIP.
5. Validate Mach-O architectures, mount both DMGs, inspect both ZIPs, and run the app on the native architecture.
6. Update release documentation, open a pull request, merge after checks, then request explicit version confirmation before creating the next tag.

