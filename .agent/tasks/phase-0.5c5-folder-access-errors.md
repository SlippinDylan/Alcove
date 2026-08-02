# Phase 0.5C5 — Folder Access and Error Classification

## Read First

Read and report success or exact failure for `~/.codex/AGENTS.md`, repository
`AGENTS.override.md`/`AGENTS.md` if present, `HANDOFF.md`, all four baseline
documents, and the Phase 0.5C1 enumeration source/tests/document plus other
Spike 0.5 error models directly relevant to this task.

Use English for code, comments, docs, and reports. Report inaccessible paths.

## Goal and Non-Goals

Create a disposable, read-only diagnostic harness that records actual local
enumeration outcomes for Desktop, Documents, and Downloads and verifies a typed
folder-access error classifier with owned temporary fixtures. This work must not
select an observer, change TCC settings, request Full Disk Access, implement
production UI, test physical volume ejection, or complete Spike 0.5.

## Modification Allowlist

Only create or modify:

```text
spikes/folder-access-errors/
docs/SPIKE_FOLDER_ACCESS_ERRORS.md
.agent/results/phase-0.5c5-folder-access-errors.md
```

No Git write/history/remote operations. Do not modify existing candidates,
baselines, HANDOFF, progress, memory, other spikes, protected folders, or any
system privacy database.

## Safety and Technical Constraints

- Swift 6 complete strict concurrency, warnings as errors, minimum macOS 15.0.
- Public Foundation, Dispatch, and Darwin APIs only; no dependency or private API.
- No `tccutil`, `sudo`, authorization reset, permission prompt automation, writes
  under Desktop/Documents/Downloads, or assumptions about Full Disk Access.
- Never print directory entries or user filenames. Record only path category,
  success/failure, entry count, and typed error metadata.
- Use a private temporary root for all mutations. Restore permissions before
  cleanup. Cleanup and permission-restoration failures are fatal and combined
  with the primary error.
- No `as!`, `try!`, normal-path force unwrap, `fatalError`, `nonisolated(unsafe)`,
  `@preconcurrency`, broad `Any`, swallowed errors, fake passes, or unbounded waits.
- Blocking `FileManager` enumeration must run on an explicit background queue;
  use a checked generation/result boundary and do not claim one-shot enumeration
  can be cancelled during the call.

## Required Diagnostic and Classifier

Provide a machine-readable CLI with a bounded outer test runner.

1. `protected-locations`
   - Resolve the current user's Desktop, Documents, and Downloads paths without
     enumerating or printing their children.
   - Attempt read-only immediate-child enumeration for each on an explicit
     background execution boundary.
   - Emit one result per category with actual success/count or exact NSError
     domain/code plus underlying POSIX domain/code where present.
   - A successful read is evidence only that this process was allowed now. It is
     not a denial test and not proof that TCC never applies.
   - Do not trigger or claim a permission prompt.

2. Owned real-filesystem fixtures
   - Accessible directory: success.
   - Missing path: typed `folderNotFound` with real underlying metadata.
   - Regular file used as a directory: typed `notDirectory` or an explicitly
     justified equivalent with real metadata.
   - Permission-denied directory created under the private root: remove read and
     search permission, require a real failure on this process, classify it as
     `permissionDenied`, restore permission, and clean up. If the current process
     can still enumerate it, fail honestly rather than synthesize an NSError.

3. Error model
   - Preserve original NSError domain/code and nested underlying error
     domain/code when available.
   - Distinguish at least `folderNotFound`, `permissionDenied`, `notDirectory`,
     and `enumerationFailed` without labeling every protected-location error as
     TCC. A path category may inform presentation wording but must not replace
     actual error metadata.
   - Document the evidence-supported banner/action mapping for the first three.
   - Do not claim `volumeNotAvailable` is validated without physical ejection.

All success JSON must be emitted only after owned fixture restoration and
cleanup. The test runner must use private `TMPDIR`, actively drain output,
enforce TERM then SIGKILL, confirm exit, and clean its run directory.

## Tests and Verification

Create deterministic `build.sh` and `test.sh`. Tests must strictly decode JSON
and cover the three protected categories, accessible control, actual ENOENT,
actual ENOTDIR/equivalent, actual EACCES/EPERM, mapping metadata, background
execution evidence, checked generation, invalid arguments, runtime timeout,
cleanup/restoration failure seams, large-output-safe runner behavior, and a
fail-closed source policy scan. Never use a fixed sleep as the only completion
proof.

Run `test.sh` three consecutive times, standalone diagnostics, invalid arguments,
and inspect the Mach-O with `file`, `xcrun vtool -show-build`, `otool -L`, and
`codesign -dv`.

## Documentation and Report

Create `docs/SPIKE_FOLDER_ACCESS_ERRORS.md` beginning exactly:

```text
Status: In Progress — Phase 0.5C5 local access evidence only
```

Separate actual protected-location results from owned-fixture classifier tests.
State the responsible process/runtime context, exact commands/exits, error
metadata, limitations, remaining authorization-UI/removable/network/macOS-15
work, no observer selection, and incomplete Spike 0.5.

Create `.agent/results/phase-0.5c5-folder-access-errors.md` within 120 lines with
reads, files, commands/exits, assertions, actual facts, three least-certain
areas, scope compliance, and gate status. Inspect status, diff check, and the
complete diff before returning.
