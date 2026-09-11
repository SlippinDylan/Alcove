# Slice 8A — Placement Core Result

The verified Spike 0.2 placement geometry and eviction-safe state reducer now
live in AlcoveCore. Capture and restore preserve absolute frames for unchanged
geometry and normalized movable-range anchors for changed geometry. The reducer
keeps user-confirmed placement entries immutable during system eviction, restores
only the remembered home display, and treats empty topology as a deferred state.

Automated verification completed on 2026-09-11:

- AlcoveCore: 107 tests, 0 failures, including 51 placement geometry and 22 placement state tests.
- Hosted Alcove tests: 56 tests, 0 failures.
- Swift 6 strict concurrency and warnings-as-errors compilation passed.
- Unsigned Release app built for arm64 and x86_64 with minimum macOS 15.0.
- `git diff --check` passed.

This slice intentionally does not modify the Portal aggregate or JSON schema.
AppKit display identity/observation, explicit user-interaction boundaries, window
directive application, and v1-to-v2 persistence migration remain in Slice 8.
