# Phase 0.1C — Window Class Comparison Result

## Read Status

Claude successfully read `~/.codex/AGENTS.md`, HANDOFF, all four baseline documents, the existing desktop-window Spike document, every existing Spike source/test file, and both build scripts. Repository `AGENTS.override.md` and `AGENTS.md` were absent. No requested existing file failed to read.

## Files

Created:

- `spikes/desktop-window/Sources/WindowClassCandidate.swift`
- `spikes/desktop-window/Sources/AlcoveSpikePanel.swift`

Modified the existing window/controller/diagnostics/menu sources, tests, build scripts, and `docs/SPIKE_DESKTOP_WINDOW.md`. This report is the only result file.

## Design

- `WindowClassCandidate` has exactly `.nsWindow` and `.nsPanel`, independent of the six strategy presets.
- The controller factory creates `AlcoveSpikeWindow` or `AlcoveSpikePanel`; all style, level, collection behavior, material, and diagnostics setup then shares one path.
- Both final subclasses receive immutable key eligibility and override `canBecomeKey`.
- Panel candidates explicitly set `isFloatingPanel = false` and `hidesOnDeactivate = false`. These are experimental inputs, not observed behavior or production decisions.
- Strategy and class menus switch independently; both selected values survive close/recreate.

## Commands and Results

Claude executed:

- `bash spikes/desktop-window/test.sh` — exit 0, 133 assertions passed.
- `bash spikes/desktop-window/build.sh` — exit 0, no warnings reported.

Codex independently found that two named tests did not exercise their claimed production paths and that class candidates used different style masks. After review fixes:

- `bash spikes/desktop-window/test.sh` — exit 0, 140 assertions passed.
- `bash spikes/desktop-window/build.sh` — exit 0.
- Both compile in Swift 6 strict-concurrency mode with warnings treated as errors, target arm64 macOS 15.
- Final `.app` passed plist/signature/dependency inspection, launched with a live process, and exited through a normal Quit request.

## Automated Evidence

1. Exactly two unique typed class candidates exist.
2. Controller construction produces the requested concrete runtime class.
3. Both concrete classes return the configured `canBecomeKey` value.
4. Diagnostics output contains both the typed configured class and actual runtime type.
5. All six Phase 0.1B presets retain their reviewed invariants and construct with both classes.
6. Both classes use the same style mask and preserve requested level/collection behavior.
7. Panel experimental property values are applied.
8. Close callback fires exactly once for both concrete classes.
9. App build and structural/runtime-object tests pass; this does not establish GUI behavior.

## Manual Evidence Still Missing

- Actual key/main transitions and keyboard/mouse focus for both classes.
- Runtime menu switching and close/recreate interaction.
- Finder icon/normal-window ordering, movement, resize, and diagnostics refresh.
- Spaces, Show Desktop, Mission Control, Stage Manager, full-screen, lock, and sleep/wake.
- Actual ordering/visibility effects of the two panel property choices.

## Known Issues / Least-Certain Points

- Artifact is arm64 only; universal production output is later work.
- No status item means reactivation ergonomics remain limited in this disposable harness.
- Least certain: panel ordering at desktop level; panel visibility during system transitions; actual key activation for either class at desktop level.

## Scope and Gate

Claude stayed within `spikes/desktop-window/`, `docs/SPIKE_DESKTOP_WINDOW.md`, and this result file. It did not mutate Git or protected files.

Neither `NSWindow` nor `NSPanel` is selected. Full Spike 0.1 remains incomplete until the manual system-transition matrix produces evidence and an explicit architecture or product-scope decision.
