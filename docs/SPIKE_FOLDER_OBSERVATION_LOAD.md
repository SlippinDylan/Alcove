Status: In Progress — Phase 0.5C4 local load evidence only

# Spike 0.5C4 — Multiple Observer and Load Evidence

## Scope

This disposable real-filesystem harness compares the reviewed Phase 0.5A
DispatchSource and Phase 0.5B FSEvents candidates under bounded local
multiple-observer, mutation-load, and lifecycle-churn scenarios. It compiles the
reviewed candidate sources directly and does not copy or modify them.

This work does not select an observer, implement production recovery, claim
benchmark-quality measurements, or complete Spike 0.5.

## Commands and Structure

```text
spikes/folder-observation-load/
├── Sources/main.swift
├── Tests/main.swift
├── build.sh
└── test.sh
```

```bash
cd spikes/folder-observation-load
bash build.sh
bash test.sh
build/observer-load-probe \
  --candidate dispatch|fsevents \
  --scenario independent-roots|shared-root|mutation-load|lifecycle-churn \
  --timeout 10
```

The build uses Swift 6 complete strict concurrency, warnings as errors, and
`arm64-apple-macosx26.0`. It links only Apple system frameworks and Swift
runtimes.

## Evidence Method

- `independent-roots` starts eight simultaneous instances on eight roots. Each
  instance owns a separate gate and unique marker. FSEvents accepts only its
  canonical marker path and records its exposed registration UUID.
- `shared-root` starts eight simultaneous instances on one root. The instances
  share the filesystem mutation, but not gates or callbacks; all eight must
  independently receive evidence.
- `mutation-load` creates 1,000 deterministic files, waits for bounded callback
  quiescence, arms a new sentinel gate, creates one unique sentinel, waits for
  its evidence, then independently enumerates exactly 1,001 regular files.
- `lifecycle-churn` creates a fresh observer and root for each of 25 sequential
  cycles. Every cycle requires marker evidence, bounded teardown, and a bounded
  descriptor return to the pre-scenario baseline.

DispatchSource has no child path, so its sentinel result is directory-level
invalidation after a bounded quiet boundary, not proof that the callback names
or uniquely represents the sentinel. FSEvents sentinel evidence requires an
exact canonical path match. Every started observer receives individual throwing
teardown on both success and failure. Success JSON is emitted only after fixture
cleanup. The test runner gives each subprocess a private `TMPDIR`, drains both
output pipes while the child runs, applies bounded TERM-then-SIGKILL convergence
on timeouts and post-launch failures, confirms exit, and removes its run
directory.

## Count and Resource Semantics

- DispatchSource callback and record counts both count directory invalidation
  callbacks; there is no callback-batch identifier.
- FSEvents record count counts delivered item records. Callback and batch counts
  count unique exposed `callbackBatchIdentity` values and are equal by design.
- Counts are invalidation evidence, not mutation counts. Coalescing is expected.
- Dropped/root-change fields count records carrying known flags. Zero observed
  dropped flags does not prove that drops cannot happen.
- CPU snapshots are cumulative process user/system CPU from `getrusage`.
  `ru_maxrss` is the whole process's historical high-water value, not
  observer-only or current memory.
- `/dev/fd` values are local process descriptor snapshots. Bounded baseline
  return does not describe kernel-internal FSEvents resources.

## Automated Results

On 2026-08-02, three consecutive final `bash test.sh` runs each passed **371
assertions with 0 failures**. The suite strictly decoded all eight
candidate/scenario combinations and checked independent evidence, FSEvents path
and registration identity separation, callback/record semantics, exact 1,001
file enumeration, process resource monotonicity, per-cycle descriptor settling,
zero bridge failures, stopped teardown, probe-owned cleanup, invalid arguments,
a real FSEvents event timeout, active draining of 620,000 output bytes, and the
outer watchdog.

A separate final eight-command local sample recorded:

| Candidate | Scenario | Evidence | Callbacks | Records | CPU delta (s) | Process max RSS high-water (B) | FD |
|---|---|---:|---:|---:|---:|---:|---:|
| DispatchSource | independent roots | 8/8 | 8 | 8 | 0.002128 | 6,930,432 | 4→4 |
| DispatchSource | shared root | 8/8 | 8 | 8 | 0.001349 | 6,897,664 | 4→4 |
| DispatchSource | mutation load | 1/1 | 998 | 998 | 0.080144 | 8,585,216 | 4→4 |
| DispatchSource | lifecycle churn | 25/25 | 25 | 25 | 0.007775 | 7,094,272 | 4→4 |
| FSEvents | independent roots | 8/8 | 8 | 8 | 0.005458 | 7,192,576 | 4→4 |
| FSEvents | shared root | 8/8 | 8 | 16 | 0.004272 | 7,143,424 | 4→4 |
| FSEvents | mutation load | 1/1 | 35 | 1,002 | 0.088896 | 8,683,520 | 4→4 |
| FSEvents | lifecycle churn | 25/25 | 25 | 50 | 0.024266 | 7,372,800 | 4→4 |

The mutation loop took 0.069874 seconds for DispatchSource and 0.070574 seconds
for FSEvents in this sample. Both independent enumerations found exactly 1,001
files. No known dropped or root-change flag was observed. These are short local
samples affected by process startup, filesystem cache, candidate latency, and
the test machine; they are not comparative benchmarks or platform guarantees.

`bash build.sh invalid`, `bash test.sh invalid`, and a probe without arguments
each exited 64. The probe is an arm64 Mach-O with minimum macOS 26.0 and SDK
26.5, Apple system/Swift dependencies only, and a linker-generated ad-hoc
signature. This is deployment-target inspection, not an actual macOS 27 run.

## Codex Review Notes and Limitations

The MiMo attempt exited without creating task files, so no MiMo code or evidence
was accepted. Codex implemented and reviewed this harness. Review corrected one
shared-root orchestration defect found by the first test run: the initial code
attempted to create the one shared marker eight times. The final implementation
deduplicates filesystem mutations while retaining eight independent gates. A
second independent review found that scenario cardinalities and subprocess
failure convergence needed stronger proof. Codex derived concurrent observer
counts from the measurement structure, added scenario-specific contradiction
checks, extended the fail-closed scan to every compiled source, and replaced
post-exit synchronous pipe reads with bounded active draining and failure-path
termination. The reviewer rechecked those changes separately.

Remaining uncertainty includes scheduler timing around DispatchSource's bounded
quiet boundary, short-run cache effects in process resource snapshots, and
FSEvents batching variation across filesystems and OS versions. The harness does
not induce dropped-event flags and does not claim their absence proves reliable
delivery.

## Remaining Gate Work

TCC-protected folders, removable-media ejection/reattachment, network volumes,
real dropped/revoke recovery, longer-duration observation, and an actual macOS
15 runtime remain unverified. Hardware-, permission-, and OS-interaction work
must remain manual or be run in an appropriate environment.

No observer is selected. Full Spike 0.5 remains incomplete.
