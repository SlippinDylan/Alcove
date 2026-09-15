Status: In Progress — Phase 0.5C2 local comparison only

# Spike 0.5C2 — Observer Resource and Teardown Comparison

## Scope

This disposable harness compares the reviewed Phase 0.5A `DispatchSource` and
Phase 0.5B FSEvents candidates in isolated processes. It records local event
latency, event-count semantics, process resource snapshots, descriptor settling,
and bounded teardown for directories with 500, 1,000, and 5,000 pre-existing
items.

It does not modify either candidate, select a production observer, implement
recovery, or complete Spike 0.5.

## Structure and Commands

```text
spikes/folder-observation-comparison/
├── Sources/main.swift   # one-process measurement probe
├── Tests/main.swift     # subprocess and real-filesystem tests
├── build.sh             # clean Swift 6 build
├── test.sh              # clean build and tests
└── compare.sh           # validated 18-process matrix and aggregate
```

```bash
cd spikes/folder-observation-comparison
bash build.sh
bash test.sh
bash compare.sh
```

All scripts reject arguments with exit 64. Builds use Swift 6 complete strict
concurrency, warnings as errors, and target `arm64-apple-macosx26.0`.

## Measurement Boundary

Each probe process:

1. Creates and prepopulates an isolated fixture under its private `TMPDIR`.
2. Starts one candidate and measures start duration with monotonic uptime.
3. Records process-wide CPU, `ru_maxrss` high-water, and `/dev/fd` snapshots.
4. Records the monotonic mutation time immediately before creating a unique
   marker.
5. Accepts DispatchSource directory invalidation after that mutation, or an
   FSEvents record whose canonical path matches the unique marker.
6. After first marker evidence, observes a fixed additional 50-millisecond
   window before sampling callback, record, and batch counts. These are bounded
   window counts, not the complete eventual event stream for the marker.
7. Treats marker creation/close, event timeout, teardown, resource measurement,
   and cleanup failures as fatal.
8. Performs bounded observer teardown and polls descriptors for at most two
   seconds to record whether the local pre-start count was reached.
9. Removes its fixture before emitting one success JSON object.

The matrix runner adds an outer process watchdog, a private `TMPDIR` per sample,
retained stderr, strict JSON/semantic validation, and exactly three required
samples per candidate/item-count pair. A terminated probe can bypass its own
cleanup; the runner still removes that sample's private directory.

## Counter Semantics

- DispatchSource `callbackCount` is the number of directory invalidation
  callbacks observed after marker mutation; `recordCount` mirrors it because
  this candidate has no item record type. `callbackBatchCount` is `null`.
- FSEvents `recordCount` is the number of Swift item records delivered.
  `callbackCount` and `callbackBatchCount` both count unique C callback batches
  using `callbackBatchIdentity`. They are intentionally equal in this harness.
- All three counters cover the bounded 50-millisecond post-evidence window; they
  do not claim a complete count of later coalesced delivery.
- A DispatchSource callback and an FSEvents record are different units and are
  not compared as equivalent events.

## Codex Review Corrections

MiMo produced the initial buildable harness, but its original evidence was not
accepted. Codex corrected the following before rerunning all evidence:

- moved latency origin from observer start to marker mutation;
- required causal marker-path matching for FSEvents;
- separated FSEvents record count from callback-batch count;
- replaced an unbounded polling work item with direct semaphore signalling;
- made marker, timeout, teardown, resource, and cleanup failures explicit;
- added bounded descriptor settling instead of treating two immediate samples
  as proof of eventual cleanup;
- made subprocess launch, TERM/KILL, pipe reads, and temporary cleanup bounded;
- made the matrix reject failed, invalid, incomplete, or contradictory samples.

MiMo's earlier raw values and claims about final descriptor baselines are
superseded by the results below.

## Automated Verification

Three consecutive final `bash test.sh` runs each passed **97 assertions with 0
failures**. Coverage includes valid runs for both candidates, required result
fields, causal event receipt, count semantics, descriptor settle consistency,
process metrics, probe-owned cleanup, a real FSEvents event-timeout failure, an
outer-watchdog termination, bridge failures, and invalid arguments.

The final `bash compare.sh` run produced 18 valid JSON samples and 0 failures.
All 18 had marker/event evidence, `timeoutExpired == false`, stopped teardown,
successful cleanup, consistent descriptor fields, and zero FSEvents bridge
failures. All 18 stderr files were empty.

### Final Local Matrix

Ranges below are min–max across three samples. RSS is the whole process's
historical maximum, not observer-only memory.

| Candidate | Items | First event (s) | Start (s) | Teardown (s) | Records | Max RSS (B) | FD baseline |
|---|---:|---:|---:|---:|---:|---:|---:|
| DispatchSource | 500 | 0.000156–0.000182 | 0.000096–0.000103 | 0.000048–0.000130 | 1 | 7,847,936 | 3/3 |
| DispatchSource | 1,000 | 0.000154–0.000170 | 0.000095–0.000168 | 0.000048–0.000092 | 1 | 8,241,152–8,273,920 | 3/3 |
| DispatchSource | 5,000 | 0.000119–0.000159 | 0.000102–0.000117 | 0.000063–0.000105 | 1 | 10,731,520 | 3/3 |
| FSEvents | 500 | 0.302067–0.309630 | 0.000822–0.000866 | 0.000130–0.000191 | 1–7 | 7,995,392–8,028,160 | 3/3 |
| FSEvents | 1,000 | 0.302663–0.309074 | 0.000732–0.000756 | 0.000128–0.000177 | 1–9 | 8,372,224–8,437,760 | 3/3 |
| FSEvents | 5,000 | 0.307801–0.310216 | 0.000719–0.000788 | 0.000132–0.000217 | 1–8 | 10,895,360–10,911,744 | 3/3 |

Every sample had one callback batch. Descriptor delta was zero after bounded
settling in this final local run; settle duration ranged from 0.000017 to
0.012641 seconds. This is local evidence, not a platform guarantee or a claim
about kernel-internal resources.

DispatchSource delivered the local directory invalidation much sooner than the
FSEvents candidate configured with a 0.3-second latency. That difference is
expected from these configurations and does not by itself select a production
observer.

## Artifact and API Boundary

The probe is arm64 with minimum macOS 26.0, uses Apple system frameworks and the
Swift runtime only, and has a linker-generated ad-hoc signature. It uses public
Foundation, Dispatch, CoreServices/CoreFoundation, and Darwin APIs. There are no
third-party dependencies or AppKit components.

## Remaining Evidence

Not run or not implemented here:

- root/child symlink behavior;
- missing-directory, move, revoke, and dropped-event recovery;
- TCC-protected Desktop, Documents, and Downloads behavior;
- removable media, physical ejection, and reattachment;
- actual macOS 27 runtime;
- network volumes;
- long-running mutation load and multiple simultaneous observers.

## Gate Status

Phase 0.5C2 records local observation, latency, resource, cleanup, and teardown
evidence. It does not record recovery evidence and does not select a candidate.
Full Spike 0.5 remains incomplete.
