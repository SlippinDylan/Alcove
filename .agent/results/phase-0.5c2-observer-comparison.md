# Phase 0.5C2 Observer Comparison Result

Date: 2026-08-02
Status: Complete for the local comparison harness; Spike 0.5 remains incomplete

## Delegated Output

MiMo read the required global/project documents and the Phase 0.5A, 0.5B, and
0.5C1 harnesses. It created:

- `spikes/folder-observation-comparison/Sources/main.swift`
- `spikes/folder-observation-comparison/Tests/main.swift`
- `spikes/folder-observation-comparison/{build,test,compare}.sh`
- `docs/SPIKE_FOLDER_OBSERVATION_COMPARISON.md`

The single Claude Code call exited 0 and stayed within its allowlist. Its source
compiled, but its original verification evidence was not accepted.

## Codex Review Findings and Repairs

MiMo measured latency from observer start, accepted non-causal first events,
conflated FSEvents records with callbacks, used an unbounded polling work item,
and did not make all timeout/teardown/resource/cleanup failures fatal. Its matrix
accepted invalid or incomplete samples and its descriptor-baseline narrative was
contradicted by an original raw sample with delta 10.

Codex corrected those issues, added causal marker evidence, bounded process and
descriptor settling, typed failures, probe-owned cleanup checks, a real runtime
event-timeout test, an outer-watchdog test, strict sample semantics, and exact
three-sample aggregation. MiMo's original metrics are superseded.

## Final Commands and Results

| Command | Exit/result |
|---|---|
| `bash -n build.sh test.sh compare.sh` | 0 |
| `bash test.sh` three consecutive runs | 97 passed / 0 failed each |
| `bash compare.sh` | 18 valid samples / 0 failed |
| real FSEvents `--timeout 0.001` test | exit 1, typed timeout, fixture removed |
| outer watchdog test | probe terminated, parent cleanup completed |

The final matrix had three samples for both candidates at 500, 1,000, and 5,000
items. Every sample recorded causal event receipt, stopped teardown, successful
cleanup, consistent descriptor fields, and empty stderr. FSEvents bridge failures
were zero. Descriptor counts returned to the local pre-start baseline in all 18
samples after bounded settling.

Final first-event ranges:

- DispatchSource: 0.000119–0.000182 seconds.
- FSEvents with 0.3-second configured latency: 0.302067–0.310216 seconds.

`ru_maxrss` is process-wide historical peak memory, not observer-only RSS.
Callback and record counts are deliberately documented as different units.

## Scope and Remaining Risk

No prior observer source, baseline document, production module, dependency, or
private API was changed. This result does not select DispatchSource or FSEvents.
Symlinks, recovery, TCC, removable and network volumes, long-running load, actual
macOS 15, and user-driven system behavior remain open. Full Spike 0.5 remains
incomplete.
