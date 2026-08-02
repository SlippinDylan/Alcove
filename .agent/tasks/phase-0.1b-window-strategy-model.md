# Phase 0.1B — NSWindow Strategy Model

You are the bounded implementation agent for a disposable Alcove technical spike. This is not production code and does not complete Spike 0.1.

## Read first

Before editing, read these files and list every successfully read path in your final report. If any cannot be read, report its exact path and error instead of claiming success:

1. `~/.codex/AGENTS.md`
2. Repository `AGENTS.override.md` or `AGENTS.md` if either exists
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DELIVERY_PLAN.md`
8. `docs/SPIKE_DESKTOP_WINDOW.md`
9. Every file in `spikes/desktop-window/Sources/`
10. `spikes/desktop-window/build.sh`

Follow the global instructions, especially explicit error handling, narrow changes, English code/comments/docs, real verification, and no unsupported completion claims.

## Objective

Extend the existing Phase 0.1A `NSWindow` disposable harness with a clear strategy data model, focused public-API strategy combinations, runtime switching, diagnostics, and automated structural checks.

Cover these independent candidate dimensions:

- `.stationary`
- `.moveToActiveSpace`
- `.fullScreenAuxiliary`
- use or omission of `.canJoinAllSpaces`
- key-window eligibility

Keep the actual window class as `NSWindow` (a small `NSWindow` subclass solely to expose configurable `canBecomeKey` is allowed). Do not add or mention a tested `NSPanel` implementation; that belongs to Phase 0.1C.

## Design requirements

- Represent strategy identity/configuration centrally with typed Swift values. Do not scatter collection-behavior flags through menu actions or controllers.
- Preserve a normal baseline and the original desktop candidate.
- Add a small, reviewable set of focused candidate presets that collectively exercise every dimension above. Do not generate an unwieldy Cartesian-product UI.
- Never combine `.stationary` and `.moveToActiveSpace` in one preset; treat them as mutually exclusive candidate modes.
- Keep `desktopIconWindow + 1` explicitly described as a candidate level, not a selected/final production strategy.
- Keep `.ignoresCycle` where appropriate for desktop candidates and make the normal baseline minimal.
- Runtime switching must apply a selected strategy predictably and preserve close/recreate behavior. Recreating a closed window must retain the selected strategy.
- Key-eligible candidates must be capable of becoming key. Key-ineligible candidates must accurately return `false` from `canBecomeKey`; activation must not falsely claim that such a window became key.
- Diagnostics must show both configured intent and actual state, including strategy name/identifier, configured key eligibility, actual `canBecomeKey`, actual window type, actual level, and actual collection behavior.
- Provide menu entries or simple controls for every focused preset with clear labels and deterministic keyboard shortcuts where practical.
- Keep stable strong-reference lifecycle ownership.
- Use native Swift, AppKit, CoreGraphics, and Foundation public APIs only.
- Minimum target remains macOS 15.
- No force casts, `try!`, or force unwraps on normal paths.
- No third-party dependencies, private APIs, copied reference-project code, production Alcove modules, or unrelated features.

## Automated checks

Add a deterministic test entry point (for example a small Swift test executable plus `test.sh`) that verifies the strategy model without pretending to test GUI/system behavior. It must at least prove:

- preset identifiers/names are unique;
- the normal baseline has normal level and minimal collection behavior;
- the original desktop candidate retains `desktopIconWindow + 1`, `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle`;
- the preset set covers stationary, move-to-active-space, full-screen auxiliary, both can-join-all-spaces values, and both key eligibility values;
- no preset combines stationary and move-to-active-space;
- collection behavior emitted by each preset matches its typed configuration.

Actually run both the tests and a clean app build. Do not label app launch, key-window behavior, Spaces, Show Desktop, Mission Control, Stage Manager, full-screen, lock, or sleep/wake as automatically verified.

## Allowed modifications

You may create or modify only:

- `spikes/desktop-window/`
- `docs/SPIKE_DESKTOP_WINDOW.md`
- `.agent/results/phase-0.1b-window-strategy-model.md`

Do not modify `HANDOFF.md`, the four baseline documents, README, `.gitignore`, any Memory file, the historical ChatGPT export, `.DS_Store`, Git configuration, or Git history. Do not run commit, push, reset, rebase, clean, or remote commands.

## Documentation

Update `docs/SPIKE_DESKTOP_WINDOW.md` to identify Phase 0.1B as implemented and automatically built/tested while preserving an `In Progress` status for the full Spike 0.1. Record:

- the strategy presets and dimensions;
- exact build/test commands actually run and their exit results;
- what structural tests prove;
- all GUI/system behavior as still pending manual verification;
- Phase 0.1C `NSWindow` versus `NSPanel` work as not yet implemented;
- explicit statement that full Spike 0.1 remains incomplete.

## Result report

Write `.agent/results/phase-0.1b-window-strategy-model.md`, at most 120 lines, containing:

1. Successfully read instruction/project files and any read failures.
2. Created/modified files.
3. Model/preset design and why it is focused rather than Cartesian.
4. Exact test and build commands, exit codes, errors, and warnings.
5. Automated facts actually established.
6. Manual behaviors not tested.
7. Known issues and the three least-certain points.
8. Whether the allowed modification scope was strictly followed.
9. Explicit statements that Phase 0.1C is not implemented and full Spike 0.1 is incomplete.

Do the implementation now. A prose-only answer is a failure.
