# Phase 0.2A — Placement Geometry Result Report

Updated: 2026-08-02

## 1. Read Paths

| Path | Status |
|------|--------|
| `~/.codex/AGENTS.md` | Read |
| Repository `AGENTS.override.md` | Absent |
| Repository `AGENTS.md` | Absent |
| `HANDOFF.md` | Read |
| `docs/PRODUCT_REQUIREMENTS.md` | Read |
| `docs/RESEARCH.md` | Read |
| `docs/ARCHITECTURE.md` | Read |
| `docs/DELIVERY_PLAN.md` | Read |
| `.agent/results/alcove-autopilot-progress.md` | Read |
| `spikes/desktop-window/` conventions | Read |

No instruction file was absent unexpectedly. No read failures.

## 2. Created/Modified Files

| File | Action |
|------|--------|
| `spikes/display-placement/Package.swift` | Created |
| `spikes/display-placement/Sources/DisplayPlacement/PlacementGeometry.swift` | Created |
| `spikes/display-placement/Tests/DisplayPlacementTests/PlacementGeometryTests.swift` | Created |
| `docs/SPIKE_DISPLAY_PLACEMENT.md` | Created |
| `.agent/results/phase-0.2a-placement-geometry.md` | Created |

No existing files modified.

## 3. Package/Model Design

Swift 6 package, macOS 15 deployment target, no dependencies, no AppKit import.

Types: `NormalizedAnchor` (clamped 0...1), `PlacementRecord` (immutable), `GridSpacing` (enum), `PlacementError` (enum), `PlacementGeometry` (static capture/restore).

Capture: normalize origin within movable range, clamp anchor to 0...1, use 0 when movable range is zero.

Restore: constrain size → same-geometry absolute origin or changed-geometry anchor restore → grid-snap → clamp.

## 4. Build/Test Commands and Exit Codes

Claude originally ran plain `swift build` and `swift test`: both exited 0 with 44 tests. Codex review removed two `try!` calls, corrected the documented rounding rule, made anchor construction reject non-finite values, and added full saved-record validation plus regression tests. Codex then ran:

```
cd spikes/display-placement && swift package clean && swift build -Xswiftc -warnings-as-errors
# Exit code: 0

cd spikes/display-placement && swift package clean && swift test -Xswiftc -warnings-as-errors
# Exit code: 0
# 51 tests executed, 0 failures after Codex review
```

## 5. Automated Facts Established

- Capture produces correct normalized anchors for center and all four corners.
- Zero movable range on either or both axes yields anchor component 0 (not NaN).
- Anchor components below 0 and above 1 are clamped to 0...1.
- Negative visible-frame origins produce correct relative normalization.
- Same geometry prefers the saved absolute origin.
- Changed geometry restores from the normalized anchor within the current movable range.
- Preferred size is constrained to the current visible frame before movable range calculation.
- Grid-snap occurs before the final clamp; overshoot is clamped to the visible frame boundary.
- No-snap restore returns the exact computed origin.
- NaN/infinity coordinates, non-positive visible size, negative preferred size, and invalid grid spacing all produce explicit errors.
- Restore also rejects invalid saved absolute/reference frames and non-finite preferred sizes; direct anchor construction rejects non-finite components.
- Final-frame containment holds across 7 representative geometries × 2 snap modes.
- Capture and restore are deterministic (identical repeated results).
- CGRect normalizes negative dimensions silently; negative window-frame sizes cannot be tested through CGRect construction alone.

## 6. Work/Manual Evidence Not Performed

- No real `NSScreen` enumeration or display UUID lookup.
- No `didChangeScreenParametersNotification` observation.
- No disconnect/reconnect, resolution/scaling, rearrangement, sleep/wake, or eviction testing.
- No persistence layer integration.
- No manual hardware matrix.

## 7. Known Issues and Three Least-Certain Points

1. **CGRect normalization:** Negative CGRect dimensions are silently normalized by CoreGraphics. The capture function validates post-normalization values. Tests for negative window-frame dimensions are replaced with CGSize-based preferred-size tests.
2. **Grid snap rounding:** Explicitly uses `.toNearestOrAwayFromZero`; a half-grid regression test locks the choice, but its interaction feel is unmeasured.
3. **No real-world validation:** All geometry is test-supplied. No interaction with actual displays or system events.

**Three least-certain points:**
1. Whether the normalized-anchor scheme survives real display topology changes (Phase 0.2B).
2. Whether grid-snap rounding behavior matches user expectations in practice.
3. Whether the preferred-size constraint order handles all edge cases with real `NSScreen.visibleFrame` values (notch, Dock, menu bar combinations).

## 8. Strict Scope Statement

Phase 0.2A models and tests pure placement geometry only. It does not enumerate real screens, observe notifications, implement display UUID lookup, or implement disconnect/reconnect state. It does not create production `AlcoveCore`, `DisplayPlacement`, or an app project.

## 9. Full Spike 0.2 Is Incomplete

Full Spike 0.2 requires Phase 0.2B: real `NSScreen` inventory, public display UUID adapter, screen-parameter notifications, screen ordering, disconnect/reconnect, resolution/scaling, rearrangement, sleep/wake, and eviction-safe state. Display UUID stability is not an Apple guarantee. Full Spike 0.2 is incomplete.
