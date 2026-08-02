# Phase 0.5C2 — Observer Resource and Recovery Comparison

## Read First

Read and report success or exact failure for:

1. `~/.codex/AGENTS.md`
2. repository `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DELIVERY_PLAN.md`
8. all three `docs/SPIKE_FOLDER_*.md` files
9. source, tests, and scripts under `spikes/folder-observation/`,
   `spikes/folder-observation-fsevents/`, and `spikes/folder-enumeration/`

Use English for code, comments, docs, and reports. Do not claim inaccessible
files were read.

## Goal and Non-Goal

Create one disposable comparison harness that executes the already-reviewed
DispatchSource and FSEvents candidates in equivalent isolated subprocesses and
records bounded local resource, latency, event-count, descriptor, and teardown
evidence for directories containing 500, 1000, and 5000 pre-existing items.

Do not copy or modify either observer implementation. Compile their source files
directly into the comparison probe, excluding their `main.swift` files. This task
does not select a production observer, implement automatic recovery, add AppKit,
or complete Spike 0.5.

## Modification Allowlist

Only create or modify:

```text
spikes/folder-observation-comparison/
docs/SPIKE_FOLDER_OBSERVATION_COMPARISON.md
.agent/results/phase-0.5c2-observer-comparison.md
```

No Git commit/push/reset/rebase/clean/remote operations.

## Constraints

- Native Swift plus Foundation, Dispatch, CoreServices/CoreFoundation, Darwin,
  and other documented public system APIs only.
- Minimum macOS 15.0; Swift 6 complete strict concurrency; warnings as errors.
- No third-party dependencies, AppKit, private API, KVC, copied implementation,
  `as!`, `try!`, normal-path force unwrap, `fatalError`, `nonisolated(unsafe)`,
  `@preconcurrency`, broad `Any`, swallowed errors, or unconditional passes.
- Every wait and child process must have a bounded timeout and explicit teardown.
- Treat events as invalidation evidence. Do not compare the semantic value of one
  FSEvents item record directly with one DispatchSource directory callback.
- Measurements are local samples, not platform guarantees or benchmark-quality
  statistical conclusions.

## Probe Design

Build a single probe with arguments equivalent to:

```text
observer-comparison-probe --candidate dispatch|fsevents --items N --timeout S
```

For one candidate/process:

1. Create an isolated temporary directory and prepopulate exactly N empty regular
   files before starting the observer.
2. Record setup/start duration using uptime.
3. Record process resource evidence with public APIs: user/system CPU time,
   maximum resident set size, and current open descriptor count before start,
   while running, and after completed teardown. If a metric cannot be obtained
   through a documented public API, omit it and state why rather than inventing
   it. `/dev/fd` enumeration is acceptable local diagnostic evidence.
4. Create one uniquely named marker after start and wait for the candidate's real
   callback/record with a bounded timeout.
5. Record first-event latency, callback count, record count, and FSEvents callback
   batch count where applicable. Use `null`/not-applicable rather than fake equal
   semantics.
6. Perform the candidate's reviewed bounded teardown and record duration/state.
7. Verify the post-teardown descriptor count returns to the pre-start count (or
   record an honestly explained runtime delta).
8. Transactionally remove every fixture; cleanup failures are fatal.
9. Emit one machine-readable JSON object only after successful completion.

Avoid measuring source compilation. Prepopulation cost may be reported separately
but must not be attributed to observer overhead.

## Matrix Runner and Tests

Provide deterministic scripts:

- `build.sh`: clean compile of probe and tests.
- `test.sh`: structural plus real-filesystem tests for both candidates at a small
  item count; validate JSON encoding, timeout/error paths, real event receipt,
  setup/teardown states, descriptor accounting, cleanup, and metric sanity.
- `compare.sh`: clean build, then run 3 repetitions for each candidate at 500,
  1000, and 5000 items (18 isolated probe processes total). Save raw JSON lines
  and a deterministic aggregate summary under the ignored local build directory.
  Fail if any process fails; do not silently drop a sample.

Aggregation must retain every raw sample and report per candidate/item-count:
sample count, min/median/max event latency, setup duration, teardown duration,
CPU user/system time, max RSS, and descriptor deltas. Do not claim significance
from three samples.

Actually execute `test.sh` three consecutive times, `build.sh`, the full
`compare.sh` matrix, invalid arguments, missing executable inputs if applicable,
and inspect final Mach-O deployment target/dependencies/signature.

## Documentation

Create `docs/SPIKE_FOLDER_OBSERVATION_COMPARISON.md` beginning exactly:

```text
Status: In Progress — Phase 0.5C2 local comparison only
```

Document methodology, raw/aggregate output locations, actual commands/exits,
all measured samples/aggregates, descriptor accounting, limitations, and
remaining TCC/removable/symlink/network/macOS 15/long-running evidence. Explicitly
state neither mechanism is selected and full Spike 0.5 is incomplete.

Create `.agent/results/phase-0.5c2-observer-comparison.md` within 120 lines with
reads, files, exact commands/exits, assertion count, actual metrics, known issues,
three least-certain areas, scope compliance, and gate status.

Before finishing, inspect Git status, `git diff --check`, and the complete diff.
