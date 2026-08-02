# Phase 0.5A — DispatchSource Folder Observer Bootstrap

## Read First

Before changing files, attempt to read these instructions and sources in order. In the final report, list every file actually read and report the exact path/error for anything inaccessible; do not claim inaccessible files were read.

1. `~/.codex/AGENTS.md`
2. repository-root `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DELIVERY_PLAN.md`
8. `docs/SPIKE_MATERIALS.md` only for spike-document evidence style
9. existing build/test scripts under `spikes/` only for repository conventions

The global contract applies: use English for code, comments, documentation, and the result report; make bounded, maintainable changes; handle errors explicitly; run the real tests/build; do not claim unexecuted behavior passed.

## Purpose and Boundary

Create a disposable, command-line Swift spike harness for **only candidate A** of Spike 0.5: a `DispatchSourceFileSystemObject` adapter observing one directory. This is Phase 0.5A, not a production `FolderAccess` module and not a completed Spike 0.5.

Do not implement FSEvents. Do not select DispatchSource as Alcove's production mechanism. Do not modify baseline architecture or product documents. This bootstrap exists to produce independently reviewable lifecycle and event evidence before candidate B is implemented separately.

## Modification Allowlist

You may create or modify only:

```text
spikes/folder-observation/
docs/SPIKE_FOLDER_OBSERVATION.md
.agent/results/phase-0.5a-dispatch-source-observer.md
```

Do not modify, delete, or rename any other path. Do not run Git commit, push, reset, rebase, clean, or remote commands. Read-only `git status` and `git diff` are allowed.

## Technical Constraints

- Native Swift using only Apple public APIs from Foundation, Dispatch, and Darwin.
- Minimum deployment target macOS 15.0; use the installed Apple toolchain.
- No AppKit UI, third-party dependencies, Homebrew tools, private APIs, KVC, copied reference-project code, or production Alcove modules.
- Compile Swift 6 with complete strict concurrency and warnings as errors.
- No `as!`, `try!`, normal-path force unwraps, `fatalError` for recoverable cases, `nonisolated(unsafe)`, `@preconcurrency`, broad `Any`, or swallowed errors.
- Do not claim synchronous filesystem calls can be cancelled in progress.
- Keep callback concurrency and ownership explicit. Do not move blocking test filesystem work onto `MainActor`.

## Required Adapter Behavior

Implement a small typed `DispatchSource` directory observer with a clear state/lifecycle model:

- Open an existing directory using the appropriate read-only event descriptor (`O_EVTONLY` where public/available).
- Create one `DispatchSourceFileSystemObject` with a documented candidate event mask sufficient to investigate immediate-child writes/add/remove/rename and observed-directory rename/delete/revoke behavior.
- Deliver typed observation records containing at least the source event mask and a monotonic timestamp. Never invent a child path: DispatchSource directory notifications do not identify which child changed.
- `start` must reject an invalid path/non-directory and must not leak a descriptor if source creation or setup fails.
- Repeated or invalid lifecycle transitions must have explicit behavior (typed error or documented idempotence), not undefined behavior.
- `stop` must be idempotent, suppress late callbacks, cancel the source, and close the descriptor exactly once from a safe cancellation lifecycle.
- Expose a deterministic way for the harness to wait until cancellation/descriptor teardown has completed. Do not use arbitrary sleeps as teardown proof.
- Prevent queued callbacks from a stopped registration from being delivered as current observations (generation/registration identity or an equivalent typed mechanism).
- Do not silently auto-reattach after the observed directory is renamed, deleted, or replaced at the same pathname. Record this as a candidate limitation for later comparison.

Avoid unnecessary abstraction: one adapter, its typed records/errors, and a deterministic harness are enough.

## Required Automated Harness

Use temporary directories owned and cleaned by the test harness. Execute real filesystem mutations and real DispatchSource delivery. Include explicit timeouts that fail with useful diagnostics.

At minimum verify:

1. Starting on a missing path fails with the mapped POSIX error and no active observer.
2. Starting on a regular file is rejected as not-a-directory.
3. Start/stop state behavior is deterministic; stop is idempotent.
4. Creating a child triggers at least one real relevant directory event.
5. Renaming and deleting immediate children trigger real relevant events. Account honestly for kernel event coalescing; do not require one callback per operation unless the runtime actually guarantees it.
6. Capture measured first-event latency for at least one child mutation using monotonic time; report the measurement as an observation, not a universal guarantee.
7. Rename or remove the observed directory and record the real source lifecycle flags received.
8. Replace a directory at the same pathname and prove the old source remains attached to the old object or terminates; do not claim automatic path reattachment.
9. Stop during or after queued activity and verify no post-stop user callback is accepted.
10. Cancellation completion is observed and the owned descriptor is closed; do not manually count this as passed without inspecting real state.
11. Temporary fixtures are removed transactionally, with cleanup errors reported rather than swallowed.

Tests may aggregate/coalesce multiple operations where necessary, but their assertions must correspond to actual adapter state, callback delivery, event data, or descriptor state. Do not inflate assertion counts with source lines or manual pass increments.

## Build Entry

Use deterministic `build.sh` and `test.sh` scripts or an equally clear SwiftPM entry. Scripts must clean their own build directory, reject unsupported arguments, and propagate nonzero exits. If using `swiftc`, compile with:

```text
-swift-version 6
-strict-concurrency=complete
-warnings-as-errors
-target arm64-apple-macosx15.0
```

The build entry should produce a small executable probe that can observe a supplied existing directory for a bounded duration and print typed event diagnostics. It must validate arguments and exit nonzero on setup/runtime errors; it must not run forever by default.

Actually run the tests and the build. Also run the built probe once against a temporary directory if the harness can do so deterministically. Record exact commands and exit codes.

## Spike Document

Create `docs/SPIKE_FOLDER_OBSERVATION.md` beginning exactly with:

```text
Status: In Progress — Phase 0.5A DispatchSource bootstrap only
```

Document:

- scope and structure;
- exact build/test/probe commands;
- adapter ownership, callback, stop, and descriptor-close lifecycle;
- candidate event mask and the fact that events identify directory-level changes, not child paths;
- actual automated evidence and measured latency from this machine;
- event coalescing and directory replacement findings;
- errors and limitations;
- manual/not-run matrix for TCC-protected folders, removable media/ejection, macOS 15 runtime, large directories/resource use, and long-running behavior;
- Phase 0.5B FSEvents comparison still required;
- blocking enumeration/background-boundary and cancellation-granularity work still required separately;
- explicit statement that DispatchSource is not selected and full Spike 0.5 remains incomplete.

Do not turn a single local run into a platform guarantee.

## Result Report

Create `.agent/results/phase-0.5a-dispatch-source-observer.md`, at most 120 lines, containing:

1. files successfully read and any inaccessible instruction path/error;
2. files created/modified;
3. implementation form and why;
4. actual commands and exit codes;
5. assertion totals based only on explicit executed assertions;
6. observed event masks, coalescing/replacement behavior, and latency measurements;
7. unexecuted/manual tests;
8. known issues;
9. the three least-certain areas;
10. modification-scope compliance;
11. explicit statement that DispatchSource is not selected and full Spike 0.5 remains incomplete.

Before finishing, inspect `git status --short`, `git diff --check`, and the complete diff. A Claude exit code of zero is not acceptance; Codex will independently review, rebuild, rerun, and repair the implementation.
