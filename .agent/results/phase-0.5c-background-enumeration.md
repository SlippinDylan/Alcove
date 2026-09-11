# Phase 0.5C1 — Background Directory Enumeration Result

## Delegation

Claude Code 2.1.220 / Xiaomi MiMo completed one `acceptEdits` invocation with
exit 0 and no retry. It read every required existing project document, reported
the absent repository AGENTS file, and stayed within the implementation allowlist.

MiMo created the harness shape, typed models, scripts, tests, and documentation.
Its reported 60/60 result was not acceptable evidence:

- a serial worker blocked generation N, so N+1 could run only after N's 10-second
  semaphore timeout;
- the test discarded the real N result and reconstructed a synthetic snapshot on
  MainActor, while the report still claimed real out-of-order completion;
- worker waits were unbounded and cancellation was test-only rather than part of
  a request pipeline;
- FileManager errors were not mapped, sorting lacked a stable tie-breaker,
  `createFile` swallowed failures, and the cleanup-failure test only threw a body
  error;
- the report acknowledged the serial limitation while also claiming the stale
  requirement passed.

## Codex Corrections

- Replaced the serial worker with a concurrent queue and bounded every caller
  wait; timed-out synchronous work is explicitly allowed to finish later.
- Added `EnumerationRequestRunner`, which checks cancellation before scheduling,
  before filesystem work, and after the synchronous call, verifies the worker
  boundary, and returns typed cancellation/timeout errors.
- Made the stale test retain the actual blocked N result while N+1 completes and
  publishes first.
- Added deterministic handshakes for pre-call cancellation, mid-call cancellation,
  and worker timeout; removed sleeps and swallowed errors.
- Mapped validation and enumeration failures, made generation exhaustion typed,
  used locale-independent lexical sorting with a path tie-breaker, and propagated
  fixture creation/close/cleanup failures.
- Routed every production-like test enumeration through the worker runner.

## Independent Verification

```text
bash -n build.sh test.sh: exit 0
bash test.sh × 3: exit 0 each; 67 passed, 0 failed each
bash build.sh: exit 0
isolated real-directory probe: exit 0; 3 immediate children, 0 metadata errors
build invalid / test invalid / probe no args / missing path: 64 / 64 / 64 / 1
```

On 2026-09-11, a real child-symlink non-traversal test was added. Three further
consecutive runs passed 71 assertions with 0 failures each. The returned entry
retained symlink identity through `lstat`, and no target child was enumerated.

The probe is arm64, minimum macOS 15.0, SDK 26.5, system/Swift runtime only, and
linker ad-hoc signed.

## Remaining Uncertainty

1. A timed-out or cancelled synchronous FileManager call continues until that
   call returns; this harness does not claim mid-call interruption.
2. The CLI waits synchronously for the background result; production still needs
   an async/completion boundary that never blocks MainActor.
3. An actual macOS 15 runtime and production AppKit async integration remain
   untested here; later Phase 0.5 work covers resource/load, access, observer,
   recovery-policy, and unsupported-volume boundaries.

DispatchSource/FSEvents resource and recovery comparison remains open.

Neither observer is selected. Phase 0.5C comparison and remaining access/resource
evidence are required. Full Spike 0.5 remains incomplete.
