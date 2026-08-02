# Spike 0.2 — Display Identity and Placement

**Status: In Progress — Phase 0.2A pure geometry only**

Full Spike 0.2 remains incomplete. Phase 0.2A models and tests the pure placement geometry. Phase 0.2B (real screen enumeration, display UUID, notifications, disconnect/reconnect) is not started.

---

## 1. Scope

Phase 0.2A creates a disposable Swift package under `spikes/display-placement/` that models and tests only the movable-range-normalized placement geometry required by the placement restoration algorithm in `ARCHITECTURE.md` §7.

**In scope:**
- Normalized anchor computation (capture)
- Absolute-frame and normalized-anchor restoration (restore)
- Grid-snap with configurable spacing or explicit no-snap
- Preferred-size constraint before movable-range calculation
- Input validation (NaN/infinity, non-positive visible size, negative preferred size, invalid grid spacing)
- Final-frame containment invariants

**Out of scope (Phase 0.2B):**
- Real `NSScreen` inventory and enumeration
- `CGDisplayCreateUUIDFromDisplayID` adapter
- `NSApplication.didChangeScreenParametersNotification` observation
- Display ordering stability
- Disconnect/reconnect state machine
- Resolution/scaling change handling
- Display rearrangement
- Sleep/wake geometry re-read
- Eviction-safe primary-screen fallback
- Persistence layer integration

---

## 2. Package Structure

```
spikes/display-placement/
├── Package.swift                          # Swift 6, macOS 15, no dependencies
├── Sources/DisplayPlacement/
│   └── PlacementGeometry.swift            # Pure model and operations
└── Tests/DisplayPlacementTests/
    └── PlacementGeometryTests.swift       # 51 automated XCTest cases
```

**Why a Swift package:** The spike is pure model and XCTest with no UI, no AppKit dependency, and no app target. SPM provides the simplest build/test path with no Xcode project, no bridging, and no bundle signing. The `swift test` command runs the full suite directly.

---

## 3. Model Design

### Types

| Type | Purpose |
|------|---------|
| `NormalizedAnchor` | Portal origin as `(x, y)` fractions of the movable range, clamped to `0...1` |
| `PlacementRecord` | Immutable record: absolute frame, save-time visible frame, preferred size, normalized anchor |
| `GridSpacing` | `.noSnap` or `.snap(CGFloat)` for configurable grid behavior |
| `PlacementError` | Explicit error: `nonFiniteValue`, `nonPositiveVisibleSize`, `negativeDimension`, `invalidGridSpacing` |
| `PlacementGeometry` | Namespace with static `capture` and `restore` operations |

### Capture Formula

```
movableWidth  = max(0, visibleFrame.width  - windowFrame.width)
movableHeight = max(0, visibleFrame.height - windowFrame.height)

nx = movableWidth  > 0 ? (windowFrame.minX - visibleFrame.minX) / movableWidth  : 0
ny = movableHeight > 0 ? (windowFrame.minY - visibleFrame.minY) / movableHeight : 0

anchor = clamp(nx, 0...1), clamp(ny, 0...1)
```

### Restore Operation Order (mandatory)

1. Validate inputs (finite, positive visible size, non-negative preferred size, valid grid spacing).
2. Constrain preferred size to the current visible frame: `min(preferred, visible)`.
3. If current visible geometry exactly matches save-time visible geometry → use saved absolute origin.
4. If geometry changed → compute movable range with constrained size, restore origin from normalized anchor.
5. Grid-snap the origin relative to the visible-frame origin (when snapping enabled).
6. Clamp the frame to the visible frame (after snap, not before).

---

## 4. Commands and Results

### Clean Build

```
cd spikes/display-placement
swift package clean
swift build -Xswiftc -warnings-as-errors
```

**Result:** Exit code 0. Build complete.

### Clean Test

```
cd spikes/display-placement
swift package clean
swift test -Xswiftc -warnings-as-errors
```

**Result:** Exit code 0. 51 tests executed, 0 failures.

---

## 5. Automated Evidence

All 51 test cases pass with exact deterministic assertions. Coverage includes:

| Category | Coverage |
|----------|----------|
| Center + four corners | Exact anchor values |
| Zero movable range | X-only, Y-only, and both axes |
| Anchor clamping | Capture outside range and direct finite anchor construction |
| Negative visible-frame origins | One and both axes |
| Same geometry | Saved absolute origin, with and without snap |
| Changed geometry | Wider and smaller current visible frames |
| Preferred-size constraint | Both axes and one axis; constraint precedes movable range |
| Grid snap then clamp | Normal, overshoot, boundary, large spacing, and half-grid rounding |
| Invalid input errors | Non-finite anchor/window/reference/preferred/grid values, invalid visible sizes, negative preferred size, and non-positive spacing |
| Containment invariant | Seven representative geometries in both snap modes |
| Determinism and edge cases | Repeated capture/restore, oversized window, boundary anchor, and zero origin |

---

## 6. Manual Evidence Not Performed

Phase 0.2A produces no manual evidence. The following require Phase 0.2B:

- Real display UUID stability across disconnect/reconnect
- `NSScreen.screens` ordering across topology changes
- Resolution/scaling change behavior
- Sleep/wake geometry re-read
- Display rearrangement in System Settings
- Eviction-safe primary-screen placement
- `didChangeScreenParametersNotification` event coverage

---

## 7. Known Issues

1. **CGRect normalization:** CoreGraphics silently normalizes negative CGRect dimensions (e.g., `width: -1` becomes `width: 1` with shifted origin). Negative window-frame dimensions cannot be tested through CGRect construction. The capture function validates post-normalization values. The restore function validates `preferredSize` directly via CGSize (which does not normalize).

2. **Grid snap rounding:** The model explicitly uses `.toNearestOrAwayFromZero`. A half-grid regression test locks that deterministic choice; user-perceived suitability is still unmeasured.

3. **No real screen interaction:** All geometry values are test-supplied. No `NSScreen`, `CGDisplay`, or notification interaction exists in this phase.

---

## 8. Phase 0.2B Work Still Required

The following items are required to resolve full Spike 0.2 and are not started:

- [ ] Real `NSScreen` inventory and display UUID adapter using `CGDisplayCreateUUIDFromDisplayID`
- [ ] UUID stability measurement across disconnect/reconnect (not an Apple guarantee)
- [ ] `NSApplication.didChangeScreenParametersNotification` observation and event coverage
- [ ] `NSScreen.screens` ordering stability across topology changes
- [ ] Disconnect/reconnect state machine (displaced → active)
- [ ] Resolution/scaling change geometry re-read and restore
- [ ] Display rearrangement in System Settings
- [ ] Sleep/wake geometry re-read
- [ ] Eviction-safe primary-screen fallback without overwriting home placement
- [ ] Integration with the Persistence layer (Slice 8)
- [ ] Manual hardware matrix for multi-display scenarios

**Explicit statement:** Display UUID stability is not an Apple guarantee. Apple does not document `CGDisplayCreateUUIDFromDisplayID` as stable through every disconnect/reconnect scenario. Full Spike 0.2 is incomplete.
