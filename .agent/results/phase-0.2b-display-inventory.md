# Phase 0.2B Display Inventory Result

## Invocation

- Claude/MiMo invocation count: 1.
- Final Claude exit: 130 after Codex terminated a repeated recursive SwiftPM test deadlock.
- The redirected log contains only `Execution error`; process inspection supplied the failure evidence.
- MiMo created the package targets, inventory adapter, observer, probe, and initial tests, but did not finish this report or the Spike document.

## Files

- Modified: `spikes/display-placement/Package.swift`.
- Added: `Sources/DisplayInventory/*.swift`, `Sources/DisplayProbe/main.swift`, and `Tests/DisplayInventoryTests/DisplayInventoryTests.swift`.
- Updated by Codex: `docs/SPIKE_DISPLAY_PLACEMENT.md`.
- No production module or protected baseline document was modified by MiMo.

## Design

- `DisplayPlacement` remains UI-free.
- `DisplayInventory` owns MainActor `NSScreen` capture, typed DTOs, UUID conversion, deterministic encoding for an ordered snapshot, and notification lifecycle.
- `DisplayProbe` provides `snapshot` and bounded `observe --seconds N` JSON commands.
- Display ID extraction rejects missing, wrong-type, Boolean, fractional, negative, and overflow values.
- `CGDisplayCreateUUIDFromDisplayID` uses `takeRetainedValue()` under the Create rule and byte formatting without forced bridging.

## MiMo Review Findings and Codex Fixes

1. Removed a recursive `swift build` launched inside `swift test`, which deadlocked on the package lock three times.
2. Replaced an observer whose underlying notification task survived `stop()` with synchronous token registration and explicit teardown.
3. Added explicit idempotent `start()`/`stop()` and eliminated the immediate-post registration race.
4. Removed IUO/force unwraps, `nonisolated(unsafe)`, false skips, and a vacuous assertion.
5. Replaced display ID `0` error sentinel with `nil` plus explicit extraction state.
6. Added exact `UInt32` validation and strict CLI argument consumption.
7. Changed observe output from summary text to JSON events containing fresh snapshots.
8. Added MainActor, stop-suppression, fresh-snapshot, numeric-boundary, and CLI regression tests.

## Codex Verification

Commands, all exit 0:

```text
swift package clean
swift test -Xswiftc -warnings-as-errors
swift package clean
swift build -Xswiftc -warnings-as-errors
.build/debug/DisplayProbe snapshot
.build/debug/DisplayProbe observe --seconds 0.2
ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' <each captured output>
```

- 80 tests, 0 failures; no compiler warnings.
- Snapshot and observe outputs decoded as JSON.
- Current session: three screens, unique indices, one main screen, positive finite frames, scale 2, canonical UUID result available for each. Identifiers omitted.
- Probe: arm64, minimum macOS 15.0, SDK 26.5, system frameworks only, ad-hoc signature.

## Limitations

- The 0.2-second unchanged observe run captured zero events; it verifies bounded exit, not real transition coverage.
- UUID and screen ordering stability are not Apple guarantees and were not inferred from one snapshot.
- Disconnect/reconnect, rearrangement, resolution/scaling, sleep/wake, and eviction behavior remain unverified.
- Eviction-safe state is not implemented. Full Spike 0.2 is incomplete.

## Least-Certain Points

1. UUID behavior across physical disconnect/reconnect.
2. Notification count/timing for real topology transitions.
3. `NSScreen.screens` ordering across rearrangement and sleep/wake.

## Scope

The final changes remain inside the disposable Phase 0.2 spike, its result/task records, HANDOFF, and progress documentation. No production Alcove module was created.
