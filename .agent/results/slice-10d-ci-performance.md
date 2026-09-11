# Slice 10D Result — CI, Performance, and Artifact Validation

## Implemented

- GitHub Actions now runs on pushes to `main`, pull requests, and manual dispatch.
- The workflow pins Xcode 26.6 on `macos-26`, matching the current official
  runner image inventory inspected through GitHub's `actions/runner-images`
  repository.
- CI rejects force casts, force tries, unsafe isolation/sendability escapes in
  production and Finder-style file mutation APIs in UI modules.
- CI runs every Core and hosted test, builds an unsigned universal Release app,
  verifies `arm64` plus `x86_64`, verifies macOS 15.0 minimum deployment and
  `LSUIElement`, and uploads a zipped app artifact.
- A real 999-file fixture measures the production folder enumerator against the
  500 ms NFR-03 threshold; fixture creation and cleanup are outside the measured
  interval.

## Release Boundary

The artifact is deliberately unsigned. Signing, DMG construction, Gatekeeper,
quarantine, installation, and certificate-expiry claims remain blocked on Spike
0.6 and are not hidden inside this product-completion workflow.

## Local Verification

- AlcoveCore: 110 tests passed.
- Hosted app: 112 tests passed, including the 999-item production enumeration.
- Unsigned Release build: universal `arm64` and `x86_64`, minimum macOS 15.0,
  `LSUIElement=true`.
