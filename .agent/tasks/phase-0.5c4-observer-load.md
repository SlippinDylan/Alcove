# Phase 0.5C4 — Multiple Observer and Load Evidence

## Read First

Read and report success or exact failure for `~/.codex/AGENTS.md`, repository
`AGENTS.override.md`/`AGENTS.md` if present, `HANDOFF.md`, all four baseline
documents, and the Phase 0.5A/0.5B/0.5C1/0.5C2/0.5C3 source, tests, scripts,
and Spike documents directly relevant to observation and enumeration.

Use English for code, comments, docs, and reports. Report inaccessible paths.

## Goal and Non-Goals

Create a disposable real-filesystem harness that records bounded local behavior
of the existing DispatchSource and FSEvents candidates under multiple-observer
and mutation load. Compile reviewed sources directly; do not copy or modify
them. Do not select an observer, implement production code, claim benchmark
quality, induce artificial dropped-event flags, or complete Spike 0.5.

## Modification Allowlist

Only create or modify:

```text
spikes/folder-observation-load/
docs/SPIKE_FOLDER_OBSERVATION_LOAD.md
.agent/results/phase-0.5c4-observer-load.md
```

No Git write/history/remote operations. Do not modify existing candidates,
baselines, HANDOFF, progress, memory, or other spikes.

## Constraints

- Swift 6 complete strict concurrency, warnings as errors, minimum macOS 15.0.
- Public Foundation, Dispatch, CoreServices/CoreFoundation, and Darwin only.
- No dependency, AppKit, private API, KVC, copied implementation, `as!`, `try!`,
  normal-path force unwrap, `fatalError`, `nonisolated(unsafe)`, `@preconcurrency`,
  broad `Any`, swallowed errors, fake passes, or unbounded waits.
- Use monotonic time and isolated private `TMPDIR` fixtures.
- Every started observer must receive throwing bounded teardown on success and
  failure. Cleanup failures are fatal; preserve combined errors.
- Treat events as invalidation evidence. Callback/record counts are not mutation
  counts. FSEvents item evidence for unique markers must match canonical paths.
- Distinguish process-wide/high-water metrics from observer-only resources.

## Required Scenarios

Implement equivalent machine-readable scenarios for both candidates:

1. `independent-roots`
   - Start 8 simultaneous observer instances on 8 distinct roots.
   - Arm each observer before creating one unique marker in its root.
   - Require independent evidence for every registration; FSEvents must match
     each marker path. Record generation/registration identity where exposed.
   - Stop all observers with individual bounded teardown.

2. `shared-root`
   - Start 8 simultaneous instances on the same root.
   - Create one unique marker and require evidence from all 8 registrations.
   - Do not let one shared latch or one observer satisfy another observer's test.

3. `mutation-load`
   - Start one observer on one empty root.
   - Create 1,000 uniquely named regular files in deterministic batches.
   - Require causal evidence for a final unique sentinel after all batches.
   - After bounded quiescence, independently enumerate the directory and require
     exactly 1,001 files. Record callbacks, item records, FSE callback batches,
     known dropped/root-change flags, elapsed mutation time, process CPU,
     `ru_maxrss`, and descriptor snapshots. Do not claim every mutation produced
     an event or that absence of dropped flags proves drops cannot occur.

4. `lifecycle-churn`
   - Perform 25 sequential start → unique marker → required evidence → bounded
     stop cycles using fresh observer instances and roots.
   - Record descriptor baseline and bounded post-cycle settling. Require the
     final local descriptor count to return to baseline or fail honestly with
     raw counts; do not explain deltas without evidence.

All scenarios must emit success JSON only after teardown and fixture cleanup.
An external runner must bound every subprocess with TERM then SIGKILL and clean
its private run directory even after forced termination.

## Tests and Verification

Create deterministic `build.sh` and `test.sh`. Tests must:

- run all 8 candidate/scenario combinations as isolated subprocesses;
- strictly decode required JSON and reject missing/contradictory fields;
- prove all 8 independent/shared registrations received evidence;
- prove FSE marker path and registration identity separation;
- prove final enumeration count 1,001;
- validate count semantics, nonnegative/monotonic resource fields, stopped
  teardown, zero bridge failures, descriptor math, and probe-owned cleanup;
- cover invalid arguments, a real runtime event timeout, and outer watchdog;
- fail-closed source policy scan;
- never use fixed sleeps as the only proof of completion.

Run `test.sh` three consecutive times, valid standalone scenario commands,
script/probe invalid arguments, and inspect the final Mach-O using `file`,
`xcrun vtool -show-build`, `otool -L`, and `codesign -dv`.

## Documentation and Report

Create `docs/SPIKE_FOLDER_OBSERVATION_LOAD.md` beginning exactly:

```text
Status: In Progress — Phase 0.5C4 local load evidence only
```

Document methodology, commands/exits, factual results, count/resource semantics,
Codex-review-sensitive limitations, and remaining TCC/removable/network/dropped-
event/actual-macOS-15 work. State no observer is selected and Spike 0.5 remains
incomplete.

Create `.agent/results/phase-0.5c4-observer-load.md` within 120 lines containing
reads, files, commands/exits, assertions, actual facts, known issues, three least-
certain areas, scope compliance, and gate status. Inspect status, diff check, and
the complete diff before returning.
