# Phase 0.2A — Pure Display Placement Geometry

You are the bounded implementation agent for a disposable Alcove technical spike. This is not production code and does not resolve full Spike 0.2.

## Read first

Read and report every successfully read existing path. Report absent instruction files as absent:

1. `~/.codex/AGENTS.md`
2. Repository `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md` — especially DisplayPlacement and save/restore ordering
7. `docs/DELIVERY_PLAN.md` — especially Spike 0.2 and Slice 8
8. `.agent/results/alcove-autopilot-progress.md`
9. Existing spike build/test conventions under `spikes/desktop-window/`

Follow the global rules: narrow changes, explicit errors, no unsafe type bypass, English code/comments/docs, real verification, and no unsupported platform claims.

## Objective

Create a small Swift 6, macOS 15, UI-free disposable harness under `spikes/display-placement/` that models and tests only the pure placement geometry required by Spike 0.2.

Do not enumerate real screens, observe notifications, implement display UUID lookup, or implement disconnect/reconnect state. Those belong to Phase 0.2B. Do not create production `AlcoveCore`, `DisplayPlacement`, or an app project.

## Required model

Use typed values and public Apple APIs only. A Swift package is preferred for a pure model and XCTest suite; explain the choice.

Represent at least:

- normalized anchor `(x, y)`;
- an immutable placement record containing saved absolute frame, save-time `visibleFrame`, preferred size, and normalized anchor;
- an explicit geometry/input error type;
- a pure capture operation;
- a pure restore operation with a configurable positive grid spacing or an explicit no-snap choice.

Use `CGRect`/`CGSize` or equally precise typed geometry. Keep this harness UI-free; importing CoreGraphics/Foundation is acceptable, importing AppKit is not.

## Behavioral contract

Validate inputs explicitly:

- reject NaN/infinite coordinates or sizes;
- reject non-positive visible-frame dimensions;
- reject negative window/preferred dimensions;
- reject non-finite or non-positive grid spacing when snapping is requested;
- do not silently manufacture valid output from invalid inputs.

Capture:

1. Preserve the absolute frame and save-time visible frame.
2. Preserve the preferred window size.
3. Compute movable width/height as `max(0, visible dimension - window dimension)`.
4. Normalize origin relative to `visibleFrame.minX/minY` and the actual movable range, not full display dimensions.
5. Use anchor component `0` when the corresponding movable range is zero.
6. Clamp stored anchor components to `0...1`.

Restore:

1. Constrain preferred size to the current visible frame before computing the movable range.
2. If current visible geometry exactly matches the save-time visible geometry, prefer the saved absolute origin.
3. If geometry changed, clamp the stored normalized anchor and restore origin within the current movable range.
4. Grid-snap the restored origin relative to the current visible-frame origin when snapping is enabled.
5. Clamp only after grid snap so the final frame is wholly inside the current visible frame.
6. Preserve deterministic behavior for negative display origins and zero movable width/height.

Do not describe synchronous math as cancellable or asynchronous. Do not add persistence, Codable DTOs, generic migration machinery, display state machines, or UI.

## Automated tests

Actually execute clean `swift test` and `swift build` commands. Tests must include:

- center and all four corner anchors;
- non-zero and zero movable ranges independently on each axis;
- anchors clamped from below zero and above one;
- negative visible-frame origins;
- same geometry prefers saved absolute origin;
- changed geometry restores normalized origin;
- preferred size is constrained before movable range calculation;
- grid snap occurs before final clamp, including an edge case where snap overshoots;
- no-snap restore;
- invalid NaN/infinity, visible size, preferred size, and grid spacing errors;
- final-frame containment invariants across a table of representative geometries.

Tests must assert exact deterministic outputs where feasible and must fail on errors. Do not use tests that merely compare an accessor with itself.

## Allowed modifications

You may create or modify only:

- `spikes/display-placement/`
- `docs/SPIKE_DISPLAY_PLACEMENT.md`
- `.agent/results/phase-0.2a-placement-geometry.md`

Do not modify HANDOFF, README, `.gitignore`, the four baseline documents, existing desktop-window files/docs, Memory, historical documents, Git config, or Git history. Do not commit, push, reset, rebase, clean, or alter remotes.

## Documentation

Create `docs/SPIKE_DISPLAY_PLACEMENT.md` with:

- `Status: In Progress — Phase 0.2A pure geometry only` at the top;
- scope and package structure;
- exact capture/restore formulas and operation order;
- exact commands and exit results actually run;
- automatic evidence versus manual evidence;
- known issues;
- Phase 0.2B work still required: real `NSScreen` inventory, public display UUID adapter, screen-parameter notifications, screen ordering, disconnect/reconnect, resolution/scaling, rearrangement, sleep/wake, and eviction-safe state;
- explicit statement that UUID stability is not an Apple guarantee and full Spike 0.2 is incomplete.

## Result report

Write `.agent/results/phase-0.2a-placement-geometry.md`, at most 120 lines:

1. Read paths, absent instruction paths, failures.
2. Created/modified files.
3. Package/model design.
4. Exact clean test/build commands and exit codes.
5. Automated facts established.
6. Work/manual evidence not performed.
7. Known issues and three least-certain points.
8. Strict scope statement.
9. Explicitly state full Spike 0.2 is incomplete.

Do the implementation now. A prose-only answer is a failure.
