# Phase 0.1C — NSWindow / NSPanel Comparison Harness

You are the bounded implementation agent for a disposable Alcove technical spike. This is not production code and does not complete Spike 0.1.

## Read first

Before editing, read and report every successfully read existing path. Report absent files as absent, not successfully read:

1. `~/.codex/AGENTS.md`
2. Repository `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DELIVERY_PLAN.md`
8. `docs/SPIKE_DESKTOP_WINDOW.md`
9. Every current file in `spikes/desktop-window/Sources/`
10. Every current file in `spikes/desktop-window/Tests/`
11. `spikes/desktop-window/build.sh`
12. `spikes/desktop-window/test.sh`

Follow the global rules: narrow changes, explicit MainActor boundaries, no unsafe type bypass, English code/comments/docs, real verification, and no unsupported GUI claims.

## Objective

Extend the existing Phase 0.1B harness to compare public AppKit `NSWindow` and `NSPanel` classes independently from the existing collection-behavior presets. Support both key-eligible and key-ineligible variants, stable close/recreate lifecycle, runtime switching, and honest diagnostics.

This is Phase 0.1C only. Do not execute or claim Show Desktop, Spaces, Mission Control, Stage Manager, full-screen, lock, or sleep/wake validation. Do not choose a production class or mark full Spike 0.1 complete.

## Required design

- Keep the six Phase 0.1B strategy presets and their typed Space semantics intact.
- Introduce a central typed window-class candidate with exactly two cases: `NSWindow` and `NSPanel`.
- Make window class independently switchable at runtime; every existing strategy preset must be creatable with either class.
- Preserve the selected strategy and selected window class across close/recreate.
- Use a focused comparison, not a huge Cartesian menu. A Strategy menu plus a Window Class menu is acceptable.
- Reuse one clear window construction path. Avoid duplicating the full style/material/level setup between the two classes.
- A small public-API subclass for each class is allowed to expose immutable configurable `canBecomeKey` behavior.
- Both class candidates must support key-eligible and key-ineligible construction. The existing `Desktop (No Key)` preset may remain the focused key-ineligible variant; do not add redundant key presets unless needed for clarity.
- For `NSPanel`, explicitly and centrally choose relevant public panel properties (for example `hidesOnDeactivate` and `isFloatingPanel`) and document that they are experimental choices, not final behavior.
- Do not use `becomesKeyOnlyIfNeeded` as a substitute for a hard key-ineligible `canBecomeKey == false` policy.
- Do not imply `canBecomeKey == true` proves the window actually became key.
- Activation/order-front behavior must branch only where class/key eligibility actually requires it and must not claim success from configured labels.
- Diagnostics must show configured class, actual runtime class, configured key eligibility, actual `canBecomeKey`, actual `canBecomeMain`, `isKeyWindow`, `isMainWindow`, level, behaviors, frame, screen, display ID, and activation policy.
- Keep AppKit UI/controller operations on `MainActor`.
- Maintain the owner close callback so both titlebar and menu closes release the controller exactly once and recreate a fresh selected variant.
- Use only Swift, AppKit, CoreGraphics, and Foundation public APIs; minimum macOS 15; no third-party dependencies or production modules.
- No `as!`, `try!`, normal-path force unwraps, private APIs, copied reference code, swallowed errors, Git mutation commands, or unrelated features.

## Automated checks

Extend the deterministic Swift 6 strict-concurrency test entry point. Actually run tests and a clean app build with warnings treated as errors. Tests must establish at least:

- exactly two unique class candidates exist;
- a central factory creates the requested actual runtime class;
- both `NSWindow` and `NSPanel` concrete candidates report `canBecomeKey == true` when eligible and `false` when ineligible;
- diagnostics/configuration class labels come from the typed class candidate, not the selected strategy label;
- all six existing strategy presets remain available and retain Phase 0.1B invariants;
- each class can be constructed with normal baseline, desktop candidate, and no-key preset without changing requested level/collection behavior;
- controller close callback still fires exactly once for both class candidates;
- no test claims that actual GUI focus, activation, Space behavior, or system transitions passed.

If a runtime fact cannot be tested reliably without UI automation, leave it manual rather than inventing a proxy.

## Allowed modifications

You may create or modify only:

- `spikes/desktop-window/`
- `docs/SPIKE_DESKTOP_WINDOW.md`
- `.agent/results/phase-0.1c-window-class-comparison.md`

Do not modify HANDOFF, README, `.gitignore`, the four baseline documents, Memory, the historical ChatGPT export, `.DS_Store`, Git config, or Git history. Do not commit, push, reset, rebase, clean, or alter remotes.

## Documentation

Update `docs/SPIKE_DESKTOP_WINDOW.md` while keeping `Status: In Progress`. Record:

- the two window classes and focused key variants;
- exact experimental `NSPanel` property choices;
- exact commands and exit codes actually run;
- structural/runtime-object facts automated tests establish;
- GUI/system behaviors still unverified;
- a reproducible manual matrix still required before full Spike 0.1 can resolve;
- explicit statement that neither class is selected and full Spike 0.1 remains incomplete.

Do not erase useful Phase 0.1A/0.1B evidence.

## Result report

Write `.agent/results/phase-0.1c-window-class-comparison.md`, at most 120 lines:

1. Successfully read files, absent instruction files, and failures.
2. Created/modified files.
3. Window-class/factory design and panel property choices.
4. Exact tests/builds with exit codes and warnings.
5. Facts automatically established.
6. Manual behaviors not tested.
7. Known issues and three least-certain points.
8. Strict modification-scope statement.
9. Explicitly state no class is selected and full Spike 0.1 is incomplete.

Do the implementation now. A prose-only answer is a failure.
