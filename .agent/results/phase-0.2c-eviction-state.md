# Phase 0.2C Eviction State Result

## Ownership and Scope

- Implemented directly by Codex because multi-display state is a Codex-owned critical logic area.
- Added only a UI-free reducer and XCTest file inside `spikes/display-placement/`.
- No persistence schema, production module, AppKit window integration, or hardware claim was added.

## Model

- `DisplayIdentity` and `DisplayDescriptor` type display inputs.
- `PlacementSession` separates durable user placements/home from transient presentation.
- Presentation is active, temporarily displaced, or awaiting a display.
- `PlacementDirective` tells an outer window adapter which display/frame to apply and why.
- The reducer returns a new value only after successful geometry calculation.

## Locked Automated Semantics

1. User interaction end is the only durable record/home write.
2. System frame changes may update transient presentation but never placements/home.
3. Missing home centers a constrained temporary frame on primary, then snap/clamp.
4. No available screen defers with no directive and unchanged memory.
5. Home return restores its record; other historical displays cannot steal focus.
6. Resolution/rearrangement restores from saved geometry without rewriting it.
7. An explicit user move on fallback deliberately selects fallback as the new home.

## Verification

```text
swift package clean
swift test -Xswiftc -warnings-as-errors
swift package clean
swift build -Xswiftc -warnings-as-errors
```

- 102 tests, 0 failures.
- The state-machine suite covers disconnect, repeated eviction, empty topology, fallback migration, reconnect, rearrangement, resolution, unrelated display return, oversized fallback, grid snap, user/system origin, and invalid input.
- Geometry and inventory regressions remain green.

## Limitations

- No physical display was disconnected or rearranged in this work unit.
- UUID continuity remains an unverified adapter input assumption.
- Window notification classification as user versus system still requires AppKit integration and manual evidence.
- Full Spike 0.2 remains incomplete.
