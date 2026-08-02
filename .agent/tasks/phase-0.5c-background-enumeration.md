# Phase 0.5C1 — Background Directory Enumeration

## Read First

Read and list successful reads or exact errors in the result report:

1. `~/.codex/AGENTS.md`
2. repository `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DELIVERY_PLAN.md`
8. `docs/SPIKE_FOLDER_OBSERVATION.md`
9. `docs/SPIKE_FOLDER_OBSERVATION_FSEVENTS.md`
10. both `spikes/folder-observation*` harnesses for conventions only

Use English for code, comments, documentation, and reports. Do not claim a read
that failed.

## Goal and Boundary

Create a disposable Swift command-line harness proving one small Phase 0.5C
capability: blocking immediate-child directory enumeration runs on an explicit
non-main worker boundary, and a coordinator rejects stale or cancelled results.

This is not the observer comparison, production `FolderAccess`, or completed
Spike 0.5. Do not select DispatchSource or FSEvents. Do not modify either existing
observer harness.

## Modification Allowlist

Only create or modify:

```text
spikes/folder-enumeration/
docs/SPIKE_FOLDER_ENUMERATION.md
.agent/results/phase-0.5c-background-enumeration.md
```

No Git commit/push/reset/rebase/clean/remote operations. Read-only status/diff is
allowed.

## Required Design

- Native Swift, Foundation, Dispatch, and Darwin public APIs only.
- Minimum macOS 15.0; Swift 6 complete strict concurrency; warnings as errors.
- No AppKit, third-party dependencies, private API, KVC, copied code, `as!`,
  `try!`, normal-path force unwrap, `fatalError`, `nonisolated(unsafe)`,
  `@preconcurrency`, broad `Any`, or swallowed errors.
- Define a typed immutable immediate-child entry/snapshot model. No recursive
  traversal and no file mutation beyond isolated test fixtures.
- Execute each synchronous enumeration call on an explicit worker queue, never
  `MainActor`. Do not describe an actor by itself as a background thread.
- Give every request a monotonically increasing generation. Only the current
  generation may be accepted into coordinator state.
- Use a worker arrangement that permits an older blocked request to finish after
  a newer request, so stale-result rejection is real rather than self-proving.
- Model cancellation truthfully: cancellation may suppress acceptance before or
  after a synchronous enumeration call, but does not interrupt that call midway.
- Check cancellation before starting work and after the blocking call. Return a
  typed cancelled outcome/error without publishing state.
- Map missing path, non-directory, enumeration, and metadata failures to typed
  errors with useful path/POSIX evidence where available.
- Sort the final immediate-child snapshot deterministically without claiming
  Finder sort equivalence.
- Keep worker/coordinator lifecycles explicit and bounded. No indefinite waits.

## Required Tests

Use transactional temporary directories and explicit timeouts. Tests must prove:

1. Empty and populated immediate-child enumeration, deterministic ordering, and
   file/directory kind evidence.
2. No recursive grandchildren in the result.
3. Missing path and regular-file errors, with failed results not published.
4. The blocking enumeration body actually runs off the main thread and on the
   configured worker queue.
5. A deliberately blocked generation N finishes after N+1 and is rejected;
   accepted coordinator state remains N+1.
6. Cancellation before worker execution suppresses the call when deterministically
   arranged.
7. Cancellation during an injected blocking call does not pretend to interrupt
   that call; after release, the completed result is rejected and not published.
8. A later successful request still works after stale/cancelled requests.
9. Fixture cleanup errors are propagated.

Injection seams may be internal to the disposable harness, but production-like
paths must use real `FileManager`/POSIX filesystem evidence. Do not inflate pass
counts or use unconditional passes.

## Build, Probe, and Documentation

Provide `build.sh` and `test.sh` that clean their own ignored build directory,
reject unsupported arguments, propagate failure, and compile with:

```text
-swift-version 6
-strict-concurrency=complete
-warnings-as-errors
-target arm64-apple-macosx15.0
```

The bounded probe accepts one existing directory, prints a deterministic snapshot
and generation/worker diagnostics, and exits nonzero on failure.

Create `docs/SPIKE_FOLDER_ENUMERATION.md` beginning exactly:

```text
Status: In Progress — Phase 0.5C1 enumeration bootstrap only
```

Separate automated evidence from unexecuted evidence. State explicitly that a
synchronous enumeration cannot be cancelled midway, observation mechanism and
resource comparison remain open, neither observer is selected, and full Spike
0.5 is incomplete.

Create `.agent/results/phase-0.5c-background-enumeration.md` within 120 lines,
including reads, files, design, exact commands/exits, assertion count, real
evidence, known issues, three least-certain areas, scope compliance, and remaining
gate status.

Actually run tests at least three times, build, and a real bounded probe. Inspect
status, `git diff --check`, and the complete diff before finishing.
