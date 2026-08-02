# Phase 0.5C4 Implementation Result

## Reads

- Read `~/.codex/AGENTS.md` successfully.
- No repository `AGENTS.override.md` or `AGENTS.md` exists.
- Read `HANDOFF.md` and all four baseline documents successfully.
- Read the Phase 0.5A, 0.5B, 0.5C1, 0.5C2, and 0.5C3 candidate sources,
  scripts, tests, and Spike documents relevant to this harness.
- Read `.engramory-memory/MEMORY.md` and the bounded-agent review agreement.

## Files

- Created `spikes/folder-observation-load/Sources/main.swift`.
- Created `spikes/folder-observation-load/Tests/main.swift`.
- Created deterministic `build.sh` and `test.sh`.
- Created `docs/SPIKE_FOLDER_OBSERVATION_LOAD.md`.
- Created this report.
- Existing candidate sources are compiled directly and were not modified.

## Implementation and Review

- Implements both candidates for independent roots, shared root, 1,001-file
  mutation load, and 25-cycle lifecycle churn.
- Uses one callback and gate per observer; FSEvents requires canonical marker
  paths and distinct exposed registration UUIDs.
- Uses throwing bounded teardown, descriptor settling, transactional fixture
  cleanup, and combined primary/cleanup or teardown errors.
- Emits success JSON only after teardown and cleanup.
- Names CPU and `ru_maxrss` as process-wide cumulative/high-water evidence.
- MiMo produced no files. Codex implemented the task and found/fixed one initial
  shared-root bug: one shared marker was created once per gate instead of once.
- Independent review found two Medium issues. Codex added exact per-scenario
  cardinality/contradiction checks, derived concurrent observer counts from
  measurements, scanned every compiled source, and made subprocess pipe draining
  and post-launch failure termination bounded.

## Commands and Exits

- `bash build.sh`: 0.
- `bash test.sh`, three consecutive final runs after Codex fixes: 0, 0, 0.
- Each final run: 371 assertions passed, 0 failed.
- Eight standalone candidate/scenario commands: all 0 with strict JSON.
- Real FSEvents `--timeout 0.001`: 1, no success JSON, probe-owned cleanup.
- Outer watchdog test: TERM then bounded SIGKILL fallback, passed.
- `bash build.sh invalid`: 64.
- `bash test.sh invalid`: 64.
- Probe without arguments: 64.
- `file`, `vtool`, `otool`, and `codesign` inspections: 0.

## Actual Facts

- Independent/shared scenarios received 8/8 registration evidence for both
  candidates; FSEvents paths matched and registration UUIDs were distinct.
- Mutation scenarios independently enumerated exactly 1,001 files.
- Lifecycle churn received 25/25 evidence and settled to descriptor baseline
  after every cycle in all final local runs.
- Final separate sample descriptor counts were 4→4 for all eight combinations.
- No known dropped/root-change flag and no FSEvents bridge failure was observed.
- Count and resource values are bounded local process evidence, not benchmarks.

## Known Issues / Least-Certain Areas

1. DispatchSource cannot identify the sentinel path; its causal boundary combines
   bounded callback quiescence with post-arm invalidation evidence.
2. FSEvents batching and short-run process CPU/RSS vary by runtime and cache.
3. No actual macOS 15, TCC, removable, network, or induced dropped-event test
   was possible in this local automated task.

## Scope and Gate

- Only the three allowlisted paths were created or modified.
- No production module, dependency, private API, observer selection, or Git
  operation was introduced.
- No observer is selected. Spike 0.5 remains incomplete.
