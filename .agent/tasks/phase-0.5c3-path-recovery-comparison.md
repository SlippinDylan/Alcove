# Phase 0.5C3 — Observer Path and Recovery Evidence

## Read First

Read and report success or exact failure for:

1. `~/.codex/AGENTS.md`
2. repository `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DELIVERY_PLAN.md`
8. `docs/SPIKE_FOLDER_OBSERVATION.md`
9. `docs/SPIKE_FOLDER_OBSERVATION_FSEVENTS.md`
10. `docs/SPIKE_FOLDER_OBSERVATION_COMPARISON.md`
11. source and tests under `spikes/folder-observation/`,
    `spikes/folder-observation-fsevents/`, and
    `spikes/folder-observation-comparison/`

Use English for code, comments, docs, and reports. Do not claim an inaccessible
file was read.

## Goal

Create one disposable, local, real-filesystem harness that compares factual
DispatchSource and FSEvents behavior for missing roots, symlink roots, child
symlinks, renamed roots, and replacement paths. This is evidence gathering, not
a production recovery implementation and not an observer selection.

Compile the existing reviewed observer sources directly. Do not copy or modify
their implementation.

## Modification Allowlist

Only create or modify:

```text
spikes/folder-observation-recovery/
docs/SPIKE_FOLDER_OBSERVATION_RECOVERY.md
.agent/results/phase-0.5c3-path-recovery-comparison.md
```

Do not modify any existing observer, comparison harness, baseline document,
HANDOFF, memory, or production code. Do not run Git commit, push, reset, rebase,
clean, remote, or history operations.

## Constraints

- Native Swift plus Foundation, Dispatch, CoreServices/CoreFoundation, and
  Darwin public APIs only.
- Minimum macOS 15.0; Swift 6 complete strict concurrency; warnings as errors.
- No third-party dependency, AppKit, private API, KVC, copied implementation,
  `as!`, `try!`, normal-path force unwrap, `fatalError`, `nonisolated(unsafe)`,
  `@preconcurrency`, broad `Any`, swallowed errors, or unconditional passes.
- Every event wait and subprocess must be bounded. Every started observer must
  receive bounded teardown on success and failure.
- Every filesystem fixture must be transactionally removed. Preserve both a
  primary error and a cleanup/teardown error when both occur.
- Use monotonic time. Treat callbacks/records as invalidation evidence; do not
  infer a file operation solely from one event flag.
- Separate factual observation from an expected product recovery policy.
- Results are local macOS 26 evidence, not a platform guarantee.

## Harness Scenarios

Provide a single probe or deterministic scenario runner for both candidates.
Use an isolated private temporary root per process and unique marker names.
Record machine-readable results with explicit timeout and teardown fields.

Implement these scenarios:

1. `missing-root`
   - Start against a unique nonexistent path.
   - Record the concrete typed error category and POSIX code where available.
   - Success means the start fails truthfully; do not turn it into a pass by
     comparing a string produced by the same helper as the test.

2. `symlink-root`
   - Create a real directory plus a symlink root pointing to it.
   - Start through the symlink path, mutate a unique marker in the target, and
     record whether/where/with which flags an event arrives.
   - Record the observed DispatchSource device/inode identity and independently
     stat the target so identity evidence is not self-proving.

3. `child-symlink`
   - Observe a real root, create a symlink child whose target is outside it, and
     record the bounded event evidence and FSEvents item flags.
   - Then mutate the external target and record in a separate bounded window
     whether the observed root reports anything. Do not assume symlinks are or
     are not followed; report the local fact.

4. `root-rename`
   - Start on a real root, rename that root within the same parent, and record
     root-change evidence.
   - After the rename evidence, create a unique marker inside the moved
     directory and record in a separate bounded window whether the existing
     registration reports it.

5. `path-replacement`
   - Start on a real root, move it aside, create a new directory at the original
     pathname, then use unique markers in the moved old inode and the replacement.
   - Record independently which inode/path each candidate continues to observe.
   - Stat old and replacement directories and prove they have different inode
     identities. Do not describe replacement observation as automatic recovery.

For scenarios whose second window may legitimately produce no event, record a
bounded `false`/timeout observation as data without making the process fail.
Setup failure, first required evidence failure, teardown failure, cleanup
failure, invalid JSON, or an unbounded wait must fail.

## Tests and Build

Create deterministic `build.sh` and `test.sh`. Tests must use real filesystem
fixtures and must:

- exercise all five scenarios for both candidates in isolated subprocesses;
- validate decoded JSON/schema and candidate/scenario identity;
- validate independent inode/device evidence where applicable;
- validate typed missing-root failure categories without self-proving helpers;
- validate required first event evidence and bounded optional second windows;
- validate FSEvents bridge failure count is zero;
- validate stopped teardown and fixture cleanup before parent cleanup;
- cover invalid arguments and one real runtime timeout/error path;
- use an outer TERM then KILL watchdog and confirm exit before pipe reads;
- reject missing, malformed, or contradictory results;
- scan source/tests fail-closed for the prohibited patterns above.

Run `test.sh` three consecutive times. Inspect the final binary with `file`,
`xcrun vtool -show-build`, `otool -L`, and `codesign -dv`. Run invalid argument
paths. Do not claim actual macOS 15 runtime evidence.

## Documentation and Report

Create `docs/SPIKE_FOLDER_OBSERVATION_RECOVERY.md` beginning exactly:

```text
Status: In Progress — Phase 0.5C3 local path evidence only
```

Document methodology, exact commands/exits, every local scenario result, event
and flag/count semantics, automatic versus not-run evidence, limitations, and
remaining TCC/removable/network/load/actual-macOS-15 work. Explicitly state no
observer is selected, no recovery policy is implemented, and Spike 0.5 remains
incomplete.

Create `.agent/results/phase-0.5c3-path-recovery-comparison.md` within 120 lines
with reads, files, commands/exits, assertion count, factual scenario summary,
known issues, three least-certain areas, scope compliance, and gate status.

Before finishing, inspect Git status, `git diff --check`, and the complete diff.
