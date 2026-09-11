# Spike 0.2 — Display Identity and Placement

**Status: In Progress — Phase 0.2C automated state bootstrap complete**

Full Spike 0.2 remains incomplete. Phase 0.2A models pure placement geometry, Phase 0.2B adds a real-session inventory/notification probe, and Phase 0.2C adds an eviction-safe pure state machine. Physical topology behavior and identity stability remain unverified.

---

## 1. Scope

The disposable Swift package under `spikes/display-placement/` contains the UI-free placement geometry from Phase 0.2A and an AppKit-backed diagnostic adapter from Phase 0.2B.

**In scope:**
- Normalized anchor computation (capture)
- Absolute-frame and normalized-anchor restoration (restore)
- Grid-snap with configurable spacing or explicit no-snap
- Preferred-size constraint before movable-range calculation
- Input validation (NaN/infinity, non-positive visible size, negative preferred size, invalid grid spacing)
- Final-frame containment invariants
- Current `NSScreen.screens` inventory with array index, name, display ID, UUID result, frames, scale, and main-screen state
- Synchronous, idempotent screen-parameter notification registration with MainActor snapshot delivery
- Bounded `snapshot` and `observe` JSON commands
- Pure home/active/displaced/awaiting placement state and typed window directives
- User-confirmed placement as the only durable write path
- Disconnect fallback and home-return restoration without mutation of remembered records

**Still out of scope:**
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
│   ├── PlacementGeometry.swift             # Pure geometry operations
│   └── PlacementStateMachine.swift         # Pure eviction-safe transitions
├── Sources/DisplayInventory/               # MainActor AppKit adapter and DTOs
├── Sources/DisplayProbe/main.swift          # Bounded diagnostic executable
├── Tests/DisplayInventoryTests/             # Adapter/observer/CLI tests
└── Tests/DisplayPlacementTests/
    └── PlacementGeometryTests.swift         # 51 geometry XCTest cases
```

**Why a Swift package:** SPM keeps the geometry library UI-free while isolating AppKit to the inventory and executable targets. It provides deterministic build/test commands without creating a production app or Xcode project.

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

### Clean Test and Build

```
cd spikes/display-placement
swift package clean
swift test -Xswiftc -warnings-as-errors
swift package clean
swift build -Xswiftc -warnings-as-errors
```

**Result:** Both commands exited 0. 102 tests executed with 0 failures; the standalone build emitted no warnings.

### Real-Session Probe

```
.build/debug/DisplayProbe snapshot
.build/debug/DisplayProbe observe --seconds 0.2
```

**Result on 2026-08-02 in the current logged-in session:** both commands exited 0 and emitted decodable JSON. The snapshot contained three screens with unique array indices, exactly one main screen, positive finite geometry, scale factor 2, and an available canonical UUID result for each screen. UUID values are intentionally omitted here. The 0.2-second unchanged observation captured zero events; this proves bounded exit only, not notification coverage.

The executable is arm64, has minimum macOS 15.0 and SDK 26.5, uses only system frameworks, and is ad-hoc signed by SwiftPM.

---

## 5. Automated Evidence

All 102 test cases pass with warnings treated as errors. The original 51 exact geometry tests remain intact. Phases 0.2B–0.2C add coverage for:

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
| Display ID extraction | Missing, wrong-type, Boolean, fractional, negative, overflow, and valid values |
| UUID conversion | Create-rule ownership path and canonical byte formatting without forced bridging |
| Inventory | Current-session frame, scale, index, main-screen, and JSON round-trip invariants |
| Observer lifecycle | Idempotent start/stop, immediate registration, fresh snapshot per event, stop suppression, and background post delivered to a MainActor handler |
| CLI | Invalid/trailing arguments, bounded observe success, snapshot success, and standalone JSON decoding |
| Placement state | Disconnect, repeated eviction, empty topology deferral, reconnect, resolution, rearrangement, unrelated display return, and explicit errors |
| Durable-write boundary | System moves preserve all records; a user-confirmed move alone updates the record and home display |

`CGDisplayCreateUUIDFromDisplayID` follows the Core Foundation Create rule. The adapter consumes the returned retained `CFUUID`, then formats its bytes without forced Objective-C bridging. Missing or invalid `NSScreenNumber` values produce explicit errors and a `nil` display ID rather than the ambiguous sentinel `0`.

JSON key ordering is deterministic for a supplied ordered snapshot. The screen array intentionally preserves current `NSScreen.screens` order; no cross-snapshot ordering guarantee is claimed.

### Phase 0.2C State Semantics

- `placements` stores only user-confirmed records; topology reconciliation never writes it.
- If home is unavailable, a constrained portal is centered on the current primary display, then grid-snapped and clamped. This is a transient directive, not a primary-display placement record.
- If no display exists during reconfiguration, the state becomes `awaitingDisplay` and emits no frame directive until the next topology snapshot.
- When home returns, only `homeDisplay` is considered. A historical non-home display cannot steal the portal.
- A user who explicitly finishes a move or resize on the fallback display chooses a new home. The old record is retained but no longer auto-restored.
- Resolution/rearrangement restores from the remembered record and current geometry without rewriting the record. This resolves the ambiguous parenthetical in candidate `ARCHITECTURE.md` §6.3 in favor of its stronger no-system-write rule and Slice 8 tests; the baseline architecture remains candidate until hardware evidence.

---

## 6. Manual Evidence Not Performed

The following remain manual/hardware evidence:

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

3. **Single-session identity only:** The probe obtained UUIDs in one topology. Apple does not document them as stable through every reconnect, and current array order is not treated as stable.

4. **Synthetic notification limits:** Tests prove registration, teardown, MainActor delivery, and fresh capture for a posted notification. They do not prove which real hardware transitions emit notifications or how many events a transition produces.

5. **Pure reducer evidence only:** The eviction transitions are deterministic and tested, but no real `NSWindow` has yet been driven by them during physical disconnect, reconnect, or display rearrangement.

---

## 8. Full Spike 0.2 Work Still Required

The following items are required to resolve full Spike 0.2:

- [x] Real `NSScreen` inventory and display UUID adapter using `CGDisplayCreateUUIDFromDisplayID`
- [ ] UUID stability measurement across disconnect/reconnect (not an Apple guarantee)
- [x] Bounded `NSApplication.didChangeScreenParametersNotification` observer and synthetic lifecycle coverage
- [ ] Real hardware notification event coverage
- [ ] `NSScreen.screens` ordering stability across topology changes
- [x] Pure disconnect/reconnect state machine (active → displaced/awaiting → active)
- [ ] Resolution/scaling change geometry re-read and restore
- [ ] Display rearrangement in System Settings
- [ ] Sleep/wake geometry re-read
- [x] Pure eviction-safe primary-screen fallback without overwriting home placement
- [x] Integration with the Persistence layer (Slice 8; automated production boundary)
- [ ] Manual hardware matrix for multi-display scenarios

**Explicit statement:** Display UUID stability is not an Apple guarantee. Apple does not document `CGDisplayCreateUUIDFromDisplayID` as stable through every disconnect/reconnect scenario. Full Spike 0.2 is incomplete.
