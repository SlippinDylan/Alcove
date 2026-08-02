# Phase 0.2B — Display Inventory and Notification Probe

You are the bounded implementation agent for a disposable Alcove technical spike. This is not production code and does not resolve full Spike 0.2.

## Read first

Read and report every successfully read existing path; report absent instruction files as absent:

1. `~/.codex/AGENTS.md`
2. Repository `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md` — DisplayPlacement boundaries and evidence classifications
7. `docs/DELIVERY_PLAN.md` — Spike 0.2
8. `docs/SPIKE_DISPLAY_PLACEMENT.md`
9. Every existing file under `spikes/display-placement/`

Follow global rules: explicit errors, MainActor for AppKit state, no unsafe casts/unwraps, English code/comments/docs, actual verification, and no unsupported stability claims.

## Objective

Extend the disposable Swift package under `spikes/display-placement/` with a small AppKit-backed display inventory adapter and command-line diagnostic probe.

The probe must:

- take a one-time snapshot of `NSScreen.screens`;
- obtain the public `CGDirectDisplayID` from `NSScreen.deviceDescription` without force casts;
- call public `CGDisplayCreateUUIDFromDisplayID` and report a canonical UUID string or an explicit unavailable/error state;
- record each screen's current array index, localized name, display ID, UUID result, `frame`, `visibleFrame`, backing scale factor, and whether it is the current main screen;
- emit deterministic, human-readable JSON for evidence capture;
- support a bounded observe mode that records `NSApplication.didChangeScreenParametersNotification` events and fresh snapshots, then exits normally;
- keep snapshot sequencing explicit so array order can be compared without claiming it is stable.

## Boundaries

- Add AppKit only to new inventory/probe targets; keep the existing `DisplayPlacement` geometry target UI-free and unchanged unless a build-only adjustment is essential.
- All `NSScreen` and `NSApplication` access must occur on `MainActor`.
- Notification delivery must be safely handed to MainActor even if posted from another thread.
- Observer start/stop must be explicit, idempotent, and testable; teardown must not leave a registered observer.
- Bounded observe mode must validate duration and exit after the requested interval. Do not create a hanging default command.
- Use Foundation/AppKit/CoreGraphics/ColorSync public APIs only, no third-party dependency.
- Minimum macOS 15 and Swift 6, warnings treated as errors in Codex verification.
- Do not claim UUID stability, ordering stability, notification event coverage, or topology behavior from one snapshot or a synthetic notification.
- Do not implement persistence, production modules, disconnect eviction state, home-placement mutation, or the Phase 0.1 window harness.
- No `as!`, `try!`, normal-path force unwrap, `fatalError` for recoverable input, private API, copied reference code, Git mutations, or unrelated features.

## Suggested package shape

Keep the change focused. A suitable shape is:

- an AppKit library target containing typed snapshot DTOs, explicit adapter errors, inventory capture, JSON encoding, and notification observation;
- an executable target providing `snapshot` and `observe --seconds <positive finite value>` commands;
- an XCTest target using injected display records/NotificationCenter where practical plus a bounded real-current-session smoke test.

You may choose an equally small design and explain it. Do not duplicate rectangle DTO/encoding logic across the executable and library.

## Automated tests and commands

Actually run `swift package clean`, `swift test`, and `swift build`. Tests must include:

- typed/canonical JSON encoding with stable key ordering;
- explicit error for missing or wrongly typed `NSScreenNumber` device description using a testable extraction helper;
- UUID formatting helper behavior without inventing stability;
- current-session snapshot smoke test: at least one screen where the environment provides one, with finite/positive frame invariants and unique array indices;
- observer start is idempotent;
- a synthetic screen-parameter notification produces exactly one callback/snapshot while observing;
- stop is idempotent and prevents later callbacks;
- notification posted from a background queue is delivered to the MainActor callback;
- invalid CLI command/duration parsing is rejected without crash;
- bounded observe command can run for a short duration and exits 0;
- snapshot command exits 0 and produces decodable JSON.

Do not make tests depend on a specific display ID, UUID, name, screen count, or ordering. If the current session has no screen, report/skip the smoke condition honestly rather than manufacturing one.

## Allowed modifications

You may create or modify only:

- `spikes/display-placement/`
- `docs/SPIKE_DISPLAY_PLACEMENT.md`
- `.agent/results/phase-0.2b-display-inventory.md`

Do not modify HANDOFF, README, `.gitignore`, baseline documents, desktop-window files/docs, Memory, historical documents, Git config, or Git history. Do not commit, push, reset, rebase, clean Git files, or alter remotes.

## Documentation

Update `docs/SPIKE_DISPLAY_PLACEMENT.md` while keeping `Status: In Progress`. Preserve 0.2A evidence and add:

- inventory/probe structure and exact commands;
- the actual current-session snapshot facts observed, clearly scoped to timestamp/environment;
- the public API conversion path and explicit errors;
- notification lifecycle and what synthetic tests do/do not prove;
- manual matrix still required for disconnect/reconnect, resolution/scaling, rearrangement, ordering, and sleep/wake;
- eviction-safe state machine still not implemented;
- explicit statement that Apple does not guarantee UUID stability and full Spike 0.2 remains incomplete.

## Result report

Write `.agent/results/phase-0.2b-display-inventory.md`, at most 120 lines:

1. Read/absent/failure paths.
2. Created/modified files.
3. Adapter/probe design.
4. Exact commands and exit codes.
5. Actual current-session snapshot facts without sensitive identifiers if unnecessary.
6. Automated facts and limitations.
7. Known issues and three least-certain points.
8. Strict scope statement.
9. Explicitly state eviction state is not implemented and full Spike 0.2 is incomplete.

Do the implementation now. A prose-only answer is a failure.
