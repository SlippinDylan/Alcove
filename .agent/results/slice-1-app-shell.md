# Slice 1 — App Shell and Menu Bar Result

## Implemented

- Production `Alcove.xcodeproj` with shared `Alcove` scheme.
- macOS 15 AppKit application target and hosted XCTest target.
- `LSUIElement=true`, `LSBackgroundOnly=false`, accessory activation policy.
- Owned status item with a template system symbol, disabled New Portal, and Quit.
- Idempotent status-item start/stop and app-delegate lifecycle boundary.
- No Portal, folder access, persistence, package, signing, or entitlement work.

## Verification

- `xcodebuild -project Alcove.xcodeproj -list`: app/test targets and shared scheme found.
- Debug host tests: 3 tests, 0 failures.
- Release build: success for `arm64 x86_64` with warnings as errors.
- `lipo -archs`: `x86_64 arm64`.
- Built Info.plist: `LSUIElement=true`, `LSBackgroundOnly=false`, minimum macOS 15.0.
- `git diff --check`: passed before commit.

## Remaining Exit Gate

The automated Slice 1 boundary is complete. Per project UI-verification policy,
menu-bar visibility, absence from the Dock, and interactive Quit remain manual
checks and are not reported as passed.
