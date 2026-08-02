# Phase 0.5A — DispatchSource Folder Observer Result

## MiMo Invocation

- One Claude Code 2.1.220 non-interactive call used `acceptEdits` and bounded tools.
- MiMo reported reading the global contract, HANDOFF, four baseline documents, material Spike style, and material scripts. It reported no inaccessible file.
- The outer zsh wrapper used the reserved variable name `status`, so it failed after Claude returned and did not preserve Claude's numeric exit code. The log tail states completion and all required artifacts exist; no retry was used.
- MiMo stayed inside `spikes/folder-observation/`, `docs/SPIKE_FOLDER_OBSERVATION.md`, and this report.

## MiMo Initial Result Rejected by Codex

MiMo reported 21/21 assertions, but the result was not acceptable evidence:

- cancel teardown depended on `weak self`, risking an unclosed FD and unbalanced group;
- start/stop raced across an exposed `.starting` state;
- callback-initiated stop deadlocked on the observer queue;
- a shared static queue key confused different observer instances;
- callback mutation and cancellation-group reads were unsynchronized;
- timestamps used wall time while claiming monotonic behavior, and latency subtraction was reversed;
- replacement and post-stop tests were self-proving; child rename/delete assertions could pass from the earlier create event;
- cleanup errors were swallowed with `try?`;
- path `stat` followed by `open` had a descriptor-validation race;
- documentation overstated replacement, latency, teardown, and operation coverage.

## Codex Repairs

- Rebuilt setup as one locked open/`fstat`/source transaction.
- Added immutable callback injection and per-instance event-queue identity.
- Added independent fixed-FD cancellation ownership, deinit cancellation, typed close errors, and bounded teardown waiting.
- Made callback stop reentrant while external stop waits for active callback completion.
- Replaced wall time with `DispatchTime.uptimeNanoseconds`.
- Replaced the test harness with real per-operation events, inode positive/negative replacement controls, callback concurrency, EBADF, and transactional fixture checks.
- Removed unreachable errors, fake assertions, swallowed cleanup, and unsupported flag interpretation.

## Final Verification

```text
bash test.sh × 3: exit 0 each; 45 passed, 0 failed each
bash build.sh: exit 0
bounded temp-directory probes: exit 0; one or two write callbacks for the same spaced operations; descriptor closed
build/test invalid argument: 64 / 64
probe missing argument / missing path: 64 / 1
```

Artifact: arm64 Mach-O, minimum macOS 15.0, SDK 26.5, system/Swift runtime dependencies only, linker-generated ad-hoc signature.

Observed final local first-event latency: 0.000072–0.000085 seconds across three runs. This is not a platform guarantee.

## Remaining Uncertainty

1. FSEvents coverage, path semantics, latency, and resource cost are not yet compared.
2. TCC, removable-volume/ejection, macOS 15, symlink, network-volume, and sustained-load behavior are untested.
3. Blocking enumeration background execution, stale-result rejection, and cancellation granularity remain separate work.

## Gate

DispatchSource is not selected. Phase 0.5A is a reviewed candidate-A bootstrap only; full Spike 0.5 remains incomplete.
