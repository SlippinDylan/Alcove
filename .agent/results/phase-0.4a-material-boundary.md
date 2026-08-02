# Phase 0.4A — Material Compatibility Boundary Result

## Agent Input and Scope

MiMo reported reading `HANDOFF.md`, the four baseline documents, the desktop-window Spike documentation, and relevant SDK headers. It reported the repository agent file absent and `~/.codex/AGENTS.md` blocked by its sandbox. It created only the allowed Phase 0.4A paths and made no commit.

Created files:

- five app sources and one test source under `spikes/materials/`;
- deterministic `build.sh` and `test.sh`;
- `docs/SPIKE_MATERIALS.md`;
- this report.

## MiMo Result Before Review

MiMo exited 0 and reported 8115 assertions. Codex rejected that count and the implementation as acceptance evidence:

- the Glass path created a container but no `NSGlassEffectView` descendants;
- the initial path was hard-coded to Glass and ignored accessibility/OS resolution;
- the observer used `NotificationCenter.default`, but SDK workspace notifications require `NSWorkspace.shared.notificationCenter`;
- observer stop did not invalidate already queued tasks;
- opaque, observer, diagnostics, and recreate tests contained manual pass increments or only proved no crash;
- per-line source scanning inflated the assertion total and swallowed read errors;
- recreation discarded material/level selection;
- representative controls had started implementing out-of-scope tab state;
- two prohibited `fatalError` paths remained.

## Codex Repairs

Codex retained the bounded model/harness concept and corrected it:

- added two real Glass effect descendants inside the Glass container;
- resolved the first material before layout and injected accessibility options for real path tests;
- made Increase Contrast diagnostic-only pending visual evidence;
- added a dynamic opaque background view and kept the canvas outside every effect;
- registered on the correct workspace notification center with identity-based stale-callback rejection and RAII cleanup;
- preserved material/level intent across real app-delegate recreation and fixed menu targets;
- removed tab state, unsafe unavailable initializers, fake passes, swallowed test errors, and inflated source assertion counting;
- replaced the test suite with explicit behavior, hierarchy, notification, and lifecycle assertions.

## Final Commands and Results

```bash
cd spikes/materials && bash test.sh
# Exit 0: 72 assertions passed, 0 failed, 0 skipped

cd spikes/materials && bash build.sh
# Exit 0: Swift 6 strict concurrency, warnings as errors

file build/AlcoveSpike.app/Contents/MacOS/AlcoveSpike
xcrun vtool -show-build build/AlcoveSpike.app/Contents/MacOS/AlcoveSpike
otool -L build/AlcoveSpike.app/Contents/MacOS/AlcoveSpike
plutil -p build/AlcoveSpike.app/Contents/Info.plist
codesign --verify --strict build/AlcoveSpike.app
# arm64; min macOS 15.0; SDK 26.5; system frameworks only; ad-hoc signature

open -n build/AlcoveSpike.app
osascript -e 'tell application id "com.alcove.spike.materials" to quit'
# Process found running; normal Apple-event quit confirmed
```

Automated evidence covers public type construction, view hierarchy, constraints, exact window levels, correct workspace notification delivery, stale-event suppression, ownership, artifact metadata, and process lifecycle. It does not cover pixels or a macOS 15 runtime.

## Manual Tests Not Executed

All remain `NR`: Glass appearance at normal/desktop levels; actual macOS 15 fallback; light/dark mode; Reduce Transparency and Increase Contrast appearance; readability; hit testing; resizing; active/inactive transitions; wallpaper variation; multiple displays.

## Remaining Uncertainty

1. Whether the Glass grouping, radius, and spacing look appropriate at the desktop candidate level.
2. Whether `.headerView`/`.behindWindow` is acceptable on a real macOS 15 runtime.
3. Whether accessibility settings produce sufficient contrast and readable controls in both paths.

## Scope and Gate

No baseline document, existing spike, production module, dependency, Git configuration, or remote was changed by MiMo. Full Spike 0.4 remains incomplete; Phase 0.4A is only a reviewed structural bootstrap and cannot select the production material boundary.
