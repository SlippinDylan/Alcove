# Slice 10D — CI, Performance, and Artifact Validation

## Goal

Make every push and pull request prove the automated MVP contract and publish a
directly testable unsigned universal application without entering the separate
signing/DMG release gate.

## Scope

- Run on the documented `macos-26` GitHub runner with Xcode 26.6 explicitly
  selected.
- Run all AlcoveCore and hosted AppKit tests.
- Enforce the production unsafe-construct and read-only UI source boundaries.
- Build and inspect an unsigned universal Release app.
- Verify both architectures, macOS 15.0 minimum deployment, and `LSUIElement`.
- Upload the zipped unsigned app as a workflow artifact.
- Measure production enumeration of 999 immediate children against NFR-03's
  500 ms budget.

## Out of Scope

- Certificates, notarization, DMG packaging, quarantine behavior, and public
  GitHub Releases remain Spike 0.6.
- Hardware-only macOS 15, Intel, multiple-display, Spaces, and Stage Manager
  observations remain manual evidence.
