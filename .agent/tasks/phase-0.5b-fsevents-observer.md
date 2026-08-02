# Phase 0.5B — FSEvents Folder Observer Bootstrap

## Read First

Attempt to read, in order, and list successful reads plus exact inaccessible path/errors in the final report:

1. `~/.codex/AGENTS.md`
2. repository-root `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DELIVERY_PLAN.md`
8. `docs/SPIKE_FOLDER_OBSERVATION.md`
9. `spikes/folder-observation/` for candidate-A evidence and repository conventions

Use English for code, comments, documentation, and reports. Follow the global contract. Do not claim a file was read if access failed.

## Purpose and Boundary

Create a disposable command-line Swift harness for **candidate B only** of Spike 0.5: an FSEvents stream scoped to one mapped directory. This is not production `FolderAccess`, not the candidate comparison/decision, and not completed Spike 0.5.

Do not modify Phase 0.5A. Do not select FSEvents or DispatchSource. Do not implement blocking folder enumeration, debounce, persistence, AppKit UI, TCC workarounds, or removable-volume recovery.

## Modification Allowlist

You may create or modify only:

```text
spikes/folder-observation-fsevents/
docs/SPIKE_FOLDER_OBSERVATION_FSEVENTS.md
.agent/results/phase-0.5b-fsevents-observer.md
```

Do not modify/delete/rename any other path. Do not run Git commit, push, reset, rebase, clean, or remote commands. Read-only Git status/diff is allowed.

## Technical Constraints

- Native Swift; Apple public APIs only: Foundation, Dispatch, CoreServices/FSEvents, and Darwin when needed.
- Minimum deployment target macOS 15.0 with installed Apple toolchain.
- No AppKit, third-party dependencies, private API, KVC, Homebrew, or copied reference code.
- Swift 6 complete strict concurrency, warnings as errors.
- No `as!`, `try!`, normal-path force unwrap, `fatalError` for recoverable cases, `nonisolated(unsafe)`, `@preconcurrency`, broad `Any`, or swallowed errors.
- Unsafe pointers/`Unmanaged` are allowed only where required by the public C FSEvents callback API. Confine them to a small reviewed bridge, document ownership, and never use them to bypass concurrency checking.
- Filesystem events are invalidation evidence, not permission to mutate user content.

## Required Candidate Behavior

Implement one typed FSEvents observer and a minimal record/error model:

- Observe one existing directory root with `FSEventStreamCreate` and `FSEventStreamSetDispatchQueue` (or the current public equivalent).
- Use `kFSEventStreamCreateFlagFileEvents` so immediate-child path evidence can be investigated.
- Include `kFSEventStreamCreateFlagWatchRoot` so root rename/delete behavior can be measured.
- Choose and document a small candidate latency and whether `NoDefer` is used. Treat it as a spike candidate, not a production constant.
- Use `kFSEventStreamEventIdSinceNow`; do not replay unrelated historical events.
- Deliver typed records containing path, event ID, raw flags, decoded known flag names, monotonic delivery timestamp, and one-shot registration identity/generation.
- Do not turn a path into a claim that a specific operation occurred unless the flags/evidence support it. FSEvents may coalesce and may emit multiple records.
- Validate setup path and opened-object type before creating the stream, with typed POSIX/setup errors.
- Check and map both stream creation failure and `FSEventStreamStart` failure without leaking the callback context or stream.
- Make callback bridge ownership explicit. The callback context must stay alive through callbacks and be released exactly once after stream invalidation/release.
- Stop must invalidate acceptance before teardown, then perform public stop/invalidate/release in a safe order on an explicit lifecycle queue.
- Repeated stop must be safe. A callback may request stop without self-deadlock.
- Provide a bounded deterministic teardown wait. After successful teardown, no user callback may still be active or newly accepted.
- Deinitializing a running observer must initiate safe teardown without leaking the context/stream.

Prefer a one-shot lifecycle rather than speculative restart support. Keep the adapter small.

## Required Real-Filesystem Harness

Use isolated transactional temporary-directory fixtures. Every cleanup failure must be reported. Use explicit timeouts rather than indefinite waits.

At minimum verify with real FSEvents delivery:

1. Missing path and regular-file setup errors retain useful POSIX/path evidence with no active stream.
2. Start, duplicate start, stop, repeated stop, terminal restart, and teardown-before-stop behavior.
3. Isolated immediate-child create, rename, and delete fixtures each deliver at least one record whose path/flags are recorded. Do not let a preceding operation's delayed record prove the next operation.
4. Record and sanity-check monotonic first-event latency from operation start; report samples as local observations only.
5. Root rename and root delete with `WatchRoot`; record actual root-related flags and paths.
6. Directory replacement at the same path: use device/inode identity plus negative/positive controls to determine whether the stream follows the pathname, old object, or reports root change. Record actual behavior without assuming it matches DispatchSource.
7. Rapid operations and coalescing: record number of operations versus callbacks/records without demanding a one-to-one mapping.
8. Callback-initiated stop does not deadlock; external stop semantics are deterministic.
9. After completed teardown, further mutations do not reach the user callback within a bounded window.
10. Callback context/stream teardown is observed through real lifecycle state or an explicit injected ownership counter, not a manual pass increment.
11. Deinit of a running observer completes the owned callback-context release within a bounded test hook.
12. Transactional fixture cleanup succeeds.

Do not inflate assertion counts or use unconditional pass assertions. Negative event windows are local bounded evidence, not universal guarantees.

## Build and Probe

Create deterministic `build.sh` and `test.sh` (or an equally clear SwiftPM entry) that clean their build directory, reject unsupported arguments, propagate failures, and compile with:

```text
-swift-version 6
-strict-concurrency=complete
-warnings-as-errors
-target arm64-apple-macosx15.0
```

Link only required system frameworks. Produce a bounded probe:

```text
folder-observer-fsevents-probe <existing-directory> [duration-seconds]
```

It must validate arguments, exit nonzero on setup/teardown failures, print typed event diagnostics, and never run forever by default.

Actually run tests at least three times, build, and a deterministic temporary-directory probe. Record commands and exit codes.

## Spike Document

Create `docs/SPIKE_FOLDER_OBSERVATION_FSEVENTS.md` beginning exactly:

```text
Status: In Progress — Phase 0.5B FSEvents bootstrap only
```

Document scope, structure, commands, callback-context/stream lifecycle, flags/latency candidates, actual path/flag/coalescing/replacement evidence, automated versus manual evidence, known issues, and the not-run matrix: TCC, removable/ejection, macOS 15 runtime, symlinks, network volumes, 500/1000/5000-item resource measurements, sustained load, and multiple observers.

State that Phase 0.5C comparison plus blocking enumeration/background/cancellation evidence remain required. Explicitly state neither mechanism is selected and full Spike 0.5 is incomplete. Do not copy Phase 0.5A conclusions into FSEvents evidence without measuring them.

## Result Report

Create `.agent/results/phase-0.5b-fsevents-observer.md`, maximum 120 lines, with:

1. successful/inaccessible reads;
2. created/modified files;
3. implementation/bridge ownership form;
4. exact test/build/probe commands and exits;
5. honest explicit assertion totals;
6. actual paths, flags, coalescing, replacement, latency, and lifecycle observations;
7. unexecuted/manual evidence;
8. known issues and three least-certain areas;
9. scope compliance;
10. explicit statement that neither mechanism is selected and full Spike 0.5 remains incomplete.

Before finishing, inspect Git status, `git diff --check`, and the complete diff. Claude exit 0 is not acceptance; Codex will independently review and repair.
