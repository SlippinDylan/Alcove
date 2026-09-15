# Spike 0.1 — Desktop Window Behavior

Status: In Progress — Phase 0.1A bootstrap, Phase 0.1B strategy model, and Phase 0.1C window class comparison implemented and automatically built/tested. Full Spike 0.1 remains incomplete; manual system-transition testing is not yet done. No window class is selected.

The reproducible manual protocol and untouched 12-variant result matrix are in [`SPIKE_DESKTOP_WINDOW_MANUAL_MATRIX.md`](SPIKE_DESKTOP_WINDOW_MANUAL_MATRIX.md). Every cell remains `NR` until a person executes it on a real desktop.

---

## 1. Goal

This spike validates whether a public AppKit window strategy can reliably provide Alcove's desktop-layer behavior across Show Desktop, Spaces, full-screen apps, Stage Manager, lock, and sleep/wake without permanent eviction.

**Phase 0.1A** (bootstrap): validated that a bounded implementation agent can create a correct small macOS project, configure window level and collection behavior, implement switchable strategies, build deterministically, and honestly distinguish automated from manual verification.

**Phase 0.1B** (strategy model): extended the harness with a typed strategy data model, focused preset combinations covering every required dimension, runtime switching, diagnostics showing configured intent vs. actual state, key-window eligibility control, and automated structural tests.

**Phase 0.1C** (window class comparison): extended the harness with independently switchable `NSWindow` and `NSPanel` class candidates, a central typed `WindowClassCandidate` enum, a public-API `NSPanel` subclass with configurable `canBecomeKey`, experimental panel property documentation, runtime class switching independent of strategy presets, diagnostics showing configured and actual runtime class, and automated structural tests covering both classes across all presets.

---

## 2. Project Form

**Form:** `swiftc` + deterministic `.app` build script + deterministic test script.

**Why chosen:** A single `swiftc` invocation with an explicit build script is the most deterministic, inspectable, and dependency-free form for a disposable harness. It avoids Xcode project complexity and SwiftPM's `.app` bundling limitations. The build command is a single line; the output is a plain `.app` bundle with no hidden build system state.

---

## 3. Project Structure

```text
spikes/desktop-window/
├── Sources/
│   ├── WindowStrategy.swift          — StrategyConfiguration + StrategyPreset model
│   ├── WindowClassCandidate.swift    — WindowClassCandidate enum (NSWindow / NSPanel)
│   ├── AlcoveSpikeWindow.swift       — NSWindow subclass with configurable canBecomeKey
│   ├── AlcoveSpikePanel.swift        — NSPanel subclass with configurable canBecomeKey + experimental panel properties
│   ├── DiagnosticsView.swift         — Live diagnostics (configured intent + actual state)
│   ├── ExperimentWindowController.swift — Window lifecycle, delegate, notifications
│   ├── AppDelegate.swift             — Menu bar, preset/class switching, window management
│   └── main.swift                    — Application entry point
├── Tests/
│   └── main.swift                    — Structural strategy + window class model tests
├── build.sh                          — Deterministic app build script
├── test.sh                           — Deterministic test build + run script
└── build/                            — Generated build output (currently untracked)
    └── AlcoveSpike.app/
```

---

## 4. Strategy Model (Phase 0.1B)

### 4.1 Design

The strategy identity/configuration is represented centrally with typed Swift values:

- **`StrategyConfiguration`** — a struct holding typed Space behavior, full-screen participation, cycle participation, level, and key eligibility. It derives AppKit collection flags rather than storing an unchecked flag bag.
- **`SpaceBehavior`** — represents either stationary behavior (with an explicit all-Spaces choice) or move-to-active-Space behavior, making invalid `.moveToActiveSpace` combinations unrepresentable.
- **`StrategyPreset`** — an enum of named presets, each returning a `StrategyConfiguration`. Menu actions and controllers reference presets by name; they do not scatter collection-behavior flags.
- **`AlcoveSpikeWindow`** — a minimal `NSWindow` subclass that exposes a configurable `canBecomeKey` override, enabling key-ineligible presets to accurately return `false`.

### 4.2 Presets

| # | Preset | Level | Collection Behavior | Key Eligible | Dimensions Exercised |
|---|--------|-------|---------------------|--------------|----------------------|
| 1 | Normal Baseline | `.normal` | none | yes | Control comparison |
| 2 | Desktop Candidate | `desktopIconWindow + 1` | `canJoinAllSpaces, stationary, ignoresCycle` | yes | Original Phase 0.1A candidate |
| 3 | Desktop (No JoinAllSpaces) | `desktopIconWindow + 1` | `stationary, ignoresCycle` | yes | `.canJoinAllSpaces` absent |
| 4 | Desktop (MoveToActiveSpace) | `desktopIconWindow + 1` | `moveToActiveSpace, ignoresCycle` | yes | `.moveToActiveSpace` |
| 5 | Desktop (No Key) | `desktopIconWindow + 1` | `canJoinAllSpaces, stationary, ignoresCycle` | no | Key-window ineligible |
| 6 | Desktop (FullScreenAuxiliary) | `desktopIconWindow + 1` | `canJoinAllSpaces, stationary, fullScreenAuxiliary, ignoresCycle` | yes | `.fullScreenAuxiliary` |

### 4.3 Why Focused, Not Cartesian

The six presets cover every required dimension without generating an unwieldy Cartesian product:

- **`.stationary`** — presets 2, 3, 5, 6
- **`.moveToActiveSpace`** — preset 4
- **`.fullScreenAuxiliary`** — preset 6
- **`.canJoinAllSpaces` present** — presets 2, 5, 6
- **`.canJoinAllSpaces` absent** — presets 1, 3, 4
- **Key eligible** — presets 1, 2, 3, 4, 6
- **Key ineligible** — preset 5

`.moveToActiveSpace` is never combined with `.stationary` or `.canJoinAllSpaces`. Phase 0.1B treats all-Spaces membership and movement to the active Space as exclusive candidate semantics so each preset has an interpretable purpose; this structural choice is not evidence of runtime Space behavior. The normal baseline remains a comparison control. The original desktop candidate is preserved exactly.

### 4.4 Window Class Model (Phase 0.1C)

#### Design

Window class is represented as a central typed enum independent of the strategy presets:

- **`WindowClassCandidate`** — an enum with exactly two cases: `.nsWindow` and `.nsPanel`. The selected window class is independently switchable at runtime and preserved across close/recreate alongside the selected strategy preset.

- **`AlcoveSpikePanel`** — a minimal `NSPanel` subclass that exposes a configurable `canBecomeKey` override (matching the existing `AlcoveSpikeWindow` pattern for `NSWindow`). Both subclasses share the same immutable key-eligibility construction pattern.

#### Focused Comparison, Not Cartesian

Two independent menus replace a Cartesian product:
- **Strategy menu** (⌘1–⌘6) — selects the strategy preset (unchanged from Phase 0.1B).
- **Window Class menu** (⌘7–⌘8) — selects the window class candidate.

Every strategy preset must be constructible with either window class. This is verified by automated tests.

#### Experimental NSPanel Property Choices

The following `NSPanel` properties are set as deliberate experimental defaults in `AlcoveSpikePanel`, not as confirmed production decisions:

| Property | Value | Rationale |
|----------|-------|-----------|
| `isFloatingPanel` | `false` | Disables the panel's floating-panel flag so explicit window level remains the ordering input under test; actual ordering is manual evidence. |
| `hidesOnDeactivate` | `false` | Requests that AppKit not hide the panel automatically on deactivation; actual visibility is manual evidence. |

Both properties require manual testing against Show Desktop, Spaces, Stage Manager, and system transitions before any production decision.

#### Window Construction Path

Both `NSWindow` and `NSPanel` share one construction path after creation:
1. Factory creates the appropriate concrete subclass (`AlcoveSpikeWindow` or `AlcoveSpikePanel`).
2. Shared setup applies: title, titlebar transparency, movable-by-background, level, collection behavior, and `NSGlassEffectView` background.
3. Class-specific setup (panel experimental properties) branches only where the class actually requires it.

#### Key Eligibility

Both classes support key-eligible and key-ineligible construction via their configurable `canBecomeKey` override. The existing `Desktop (No Key)` preset remains the focused key-ineligible variant for both classes.

`becomesKeyOnlyIfNeeded` is not used as a substitute for a hard `canBecomeKey == false` policy.

### 4.5 Runtime Switching

Menu entries ⌘1–⌘6 switch between strategy presets; ⌘7–⌘8 switch between window classes. Switching either dimension tears down the current window and creates a new one. The selected preset and selected window class are independently preserved across close/recreate. The `AppDelegate` holds a strong reference to the `ExperimentWindowController`; a weak-capture close callback clears that owner reference for both menu-driven and titlebar-driven closes.

### 4.6 Diagnostics

The diagnostics display shows both configured intent and actual state. The block below is an illustrative format, not an observed runtime transcript or GUI-verification result:

```
=== CONFIGURED INTENT ===
Preset: Desktop Candidate
Window Class: NSWindow
Configured Level: 1001
Configured Behavior: canJoinAllSpaces, stationary, ignoresCycle
Configured Key Eligibility: eligible

=== ACTUAL STATE ===
Window Type: AlcoveSpikeWindow
Window Level: 1001
Actual Behavior: canJoinAllSpaces, stationary, ignoresCycle
canBecomeKey: true
canBecomeMain: true
isKeyWindow: true
isMainWindow: true

=== GEOMETRY ===
Window Frame: (200.0, 200.0, 600.0, 500.0)
Screen Frame: (0.0, 0.0, 1920.0, 1080.0)
Visible Frame: (0.0, 25.0, 1920.0, 1055.0)
Display ID: 1234567890
Activation Policy: accessory
```

Phase 0.1C adds: configured window class (from `WindowClassCandidate`), actual runtime class (from `type(of:)`), and `canBecomeMain` to the diagnostics. The configured class label comes from the typed `WindowClassCandidate` enum, not from the strategy preset label.

---

## 5. Build and Run

### App Build Command

```bash
cd spikes/desktop-window
bash build.sh
```

Exit result: **0** (clean compile, no errors, no warnings).

### Test Command

```bash
cd spikes/desktop-window
bash test.sh
```

Exit result: **0** (140 assertions passed, 0 failed after Codex review).

### Run Command

```bash
open spikes/desktop-window/build/AlcoveSpike.app
```

---

## 6. Automated Verification Actually Executed

| Check | Result |
|-------|--------|
| Swift 6 strict-concurrency `xcrun swiftc` compilation (arm64, macOS 26 target) — app | **Pass** — exit code 0, warnings treated as errors |
| Swift 6 strict-concurrency `xcrun swiftc` compilation (arm64, macOS 26 target) — tests | **Pass** — exit code 0, warnings treated as errors |
| App binary exists in `.app` bundle | **Pass** — `AlcoveSpike` Mach-O arm64 |
| Info.plist contains `LSUIElement = YES` | **Pass** |
| Ad-hoc code signing | **Pass** — build script `xcrun codesign --force --sign -` succeeded |
| Source files contain no force unwraps | **Verified by inspection** |
| Source files contain no `as!` casts | **Verified by inspection** |
| Modification boundary respected | **Verified by inspection** — only files within allowed paths |
| **Structural tests (140 assertions)** | **All pass** — see §7 |

### 6.1 Structural Tests Prove

The `Tests/main.swift` executable verifies these model properties without GUI or system interaction:

**Phase 0.1B strategy preset tests (preserved):**

1. Preset identifiers are unique across all 6 presets.
2. Preset names are unique across all 6 presets.
3. Normal Baseline has `.normal` window level and empty (minimal) collection behavior.
4. Desktop Candidate retains `desktopIconWindow + 1`, `.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`, and key eligibility — preserving the Phase 0.1A configuration exactly.
5. Every preset's emitted `collectionBehavior` matches an independently declared expected flag set.
6. Every preset's `windowLevel` accessor matches its typed configuration.
7. Every preset's `isKeyEligible` accessor matches its typed configuration.
8. At least one preset includes `.stationary`.
9. At least one preset includes `.moveToActiveSpace`.
10. At least one preset includes `.fullScreenAuxiliary`.
11. At least one preset includes `.canJoinAllSpaces`.
12. At least one preset omits `.canJoinAllSpaces`.
13. At least one preset is key-eligible.
14. At least one preset is key-ineligible.
15. No preset combines `.stationary` and `.moveToActiveSpace`.
16. No preset combines `.canJoinAllSpaces` and `.moveToActiveSpace`.
17. All non-normal presets use `desktopIconWindow + 1` level.
18. All non-normal desktop presets include `.ignoresCycle`.
19. The concrete `NSWindow` subclass (`AlcoveSpikeWindow`) reports configured key eligibility for both allowed values.
20. Closing the controller's concrete window notifies its lifecycle owner exactly once.

**Phase 0.1C window class candidate tests (new):**

21. Exactly two unique class candidates exist (`NSWindow`, `NSPanel`).
22. Class candidate identifiers are unique.
23. Class candidate display names are unique.
24. The factory creates the correct concrete runtime class (`AlcoveSpikeWindow` for `.nsWindow`, `AlcoveSpikePanel` for `.nsPanel`).
25. The concrete `NSPanel` subclass (`AlcoveSpikePanel`) reports configured key eligibility for both allowed values.
26. Diagnostics/configuration class labels come from the typed `WindowClassCandidate` enum, not from the strategy preset label.
27. All six strategy presets are available and constructible with both window classes.
28. Both classes with Normal Baseline preserve `.normal` level and empty collection behavior.
29. Both classes with Desktop Candidate preserve `desktopIconWindow + 1`, `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle`.
30. Both classes with Desktop (No Key) report `canBecomeKey == false` and preserve level/collection behavior.
31. Controller close callback fires exactly once for both window class candidates.
32. The factory applies the two explicit experimental `NSPanel` property values.

---

## 7. Manual Verification Not Yet Executed

The following require real macOS GUI interaction and **cannot** be verified by headless automation:

| Test | Status |
|------|--------|
| Level relative to Finder desktop icons | **Unverified** |
| Normal application windows cover the portal | **Unverified** |
| Clicking on window (focus, events) | **Unverified** |
| Moving the window | **Unverified** |
| Resizing the window | **Unverified** |
| Space switching (portal persists on all Spaces) | **Unverified** |
| Show Desktop (F11 / trackpad gesture) | **Unverified** |
| Mission Control | **Unverified** |
| Stage Manager | **Unverified** |
| Full-screen applications | **Unverified** |
| Lock screen | **Unverified** |
| Sleep / wake | **Unverified** |
| Key-eligible presets can actually become key | **Unverified** |
| Key-ineligible windows remain non-key after ordering | **Unverified** |
| Diagnostics values update correctly on all events | **Unverified** |
| Menu shortcuts all functional | **Unverified** |
| Window recreation lifecycle preserves preset | **Unverified** |
| Preset switching applies correct behavior | **Unverified** |
| NSPanel with key-eligible preset actually becomes key | **Unverified** |
| NSPanel with key-ineligible preset remains non-key after ordering | **Unverified** |
| NSPanel relative ordering with `isFloatingPanel = false` | **Unverified** |
| NSPanel remains visible after app deactivation with `hidesOnDeactivate = false` | **Unverified** |
| Window class switching applies correct runtime type | **Unverified** |
| Window class preserved across close/recreate | **Unverified** |

---

## 8. Known Issues

1. **No automated GUI assertions.** Compilation, artifact checks, and structural model tests passed, but Claude did not execute GUI interaction tests.
2. **Single architecture.** The spike and current production distribution both target `arm64`.
3. **No key-window activation verification.** Tests read both `canBecomeKey` override values, but do not prove either class actually becomes or remains non-key after ordering.
4. **Diagnostics update on move/resize may lag** during rapid interaction due to notification coalescing.
5. **Limited reactivation path.** With `LSUIElement = YES` and no status item, the app has no Dock or normal Command-Tab entry.
6. **Dark material only.** No light-mode or accessibility (Reduce Transparency) adaptation.
7. **NSPanel experimental properties not validated.** `isFloatingPanel = false` and `hidesOnDeactivate = false` are deliberate experimental defaults that require manual testing before any production decision.

---

## 9. Phase 0.1C Window Class Comparison — Implemented

Phase 0.1C extended the harness to compare `NSWindow` and `NSPanel` independently from the existing strategy presets:

- Added `WindowClassCandidate` enum with exactly two cases: `.nsWindow` and `.nsPanel`.
- Added `AlcoveSpikePanel` — a minimal `NSPanel` subclass with configurable `canBecomeKey` and documented experimental panel properties (`isFloatingPanel = false`, `hidesOnDeactivate = false`).
- Made window class independently switchable at runtime via a separate Window Class menu (⌘7–⌘8).
- Every strategy preset is constructible with either window class; both are preserved across close/recreate.
- Reused one clear construction path: factory creates the concrete class, shared setup applies level/behavior/material, class-specific setup branches only where required.
- Updated diagnostics to show configured window class (from `WindowClassCandidate`), actual runtime class (from `type(of:)`), and `canBecomeMain`.
- Added 12 Phase 0.1C test functions (140 assertions total) covering: exactly two class candidates, factory runtime class verification, both classes' `canBecomeKey` for eligible/ineligible, diagnostics output from configured and actual class, all presets available with both classes, shared style/level/behavior preservation, panel property configuration, and close callbacks.
- App build and tests pass with Swift 6 strict concurrency and warnings as errors.

Phase 0.1C does not validate GUI behavior, Spaces, Show Desktop, Stage Manager, full-screen, lock, or sleep/wake. Neither class is selected as the production window class.

---

## 10. Full Spike 0.1 Remains Incomplete

**Full Spike 0.1 is not complete. Neither `NSWindow` nor `NSPanel` is selected as the production window class.** What has been accomplished:

- Phase 0.1A: harness bootstrap and initial 2-strategy comparison.
- Phase 0.1B: typed strategy model, 6 focused presets covering all required dimensions, runtime switching, diagnostics with intent-vs-actual display, key-window eligibility control, and 66 automated structural assertions after Codex review.
- Phase 0.1C: window class comparison with `NSWindow` and `NSPanel` as independently switchable candidates, experimental panel properties documented, diagnostics showing configured and actual runtime class, and 140 automated structural assertions.

What remains:

1. **Manual system-transition testing:** Every preset with both window classes must be tested against Show Desktop, Spaces, Mission Control, Stage Manager, full-screen, lock, and sleep/wake on real hardware.
2. **NSPanel experimental property validation:** `isFloatingPanel` and `hidesOnDeactivate` require manual testing against system transitions.
3. **Architecture decision:** Select the evidence-backed window class and strategy from measured results, or declare feasibility failure.
4. **No evidence has been recorded** for any system transition behavior.
5. **No architecture or product-scope decision** can be made from automated tests alone.

---

## 11. Required Operations

All operations are available via menu commands (⌘ shortcuts):

| Operation | Shortcut | Implementation |
|-----------|----------|----------------|
| Normal Baseline | ⌘1 | Switch to `.normal` level, no collection behavior |
| Desktop Candidate | ⌘2 | Switch to original Phase 0.1A candidate |
| Desktop (No JoinAllSpaces) | ⌘3 | Desktop candidate without `.canJoinAllSpaces` |
| Desktop (MoveToActiveSpace) | ⌘4 | `.moveToActiveSpace` instead of `.stationary` |
| Desktop (No Key) | ⌘5 | Desktop candidate with key-window disabled |
| Desktop (FullScreenAuxiliary) | ⌘6 | Desktop candidate with `.fullScreenAuxiliary` |
| NSWindow | ⌘7 | Switch to `NSWindow` class (preserves selected strategy) |
| NSPanel | ⌘8 | Switch to `NSPanel` class (preserves selected strategy) |
| Activate / Make Key | ⌘A | Activates the app, then uses `makeKeyAndOrderFront` for eligible presets or `orderFront` for non-key presets |
| Close Window | ⌘W | Closes window; the close callback clears the controller owner reference |
| Recreate Window | ⌘N | Closes existing (if any), creates fresh controller + window |
| Quit | ⌘Q | Standard `NSApplication.terminate` |
