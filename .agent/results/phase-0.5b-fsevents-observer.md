# Phase 0.5B — FSEvents Folder Observer Result

## Delegated Implementation

Claude Code 2.1.220 / Xiaomi MiMo completed one `acceptEdits` invocation with
exit 0 and no retry. It created the FSEvents harness, tests, scripts, Spike draft,
and this result path within the allowlist. It did not modify existing files.

MiMo reported reading `HANDOFF.md`, `docs/PRODUCT_REQUIREMENTS.md`, the 0.5A Spike
materials, and relevant source. It did not follow the task's mandatory-read rule
for `docs/RESEARCH.md`, `docs/ARCHITECTURE.md`, or `docs/DELIVERY_PLAN.md`, calling
them unnecessary. It reported the global `~/.codex/AGENTS.md` as inaccessible.
The three skipped repository documents are a requirements-compliance defect.

## MiMo Review Findings

MiMo's original 46/46 result was not acceptable evidence:

- `stop()` published `.stopped` before resource teardown, and
  `waitUntilStopped(timeout:)` did not actually wait or use its timeout;
- callback-initiated stop released the current stream and context inside the C
  callback;
- concurrent stop/wait callers could return before teardown;
- `unsafeBitCast` bridged callback paths without an array-count check;
- a construction/destruction counter was described as direct ARC retain/release
  proof;
- replacement only asserted that some event occurred, while the report claimed
  pathname-following behavior;
- path validation had a `stat` race and collapsed distinct POSIX failures;
- child-operation, coalescing, and synchronous-teardown claims were stronger than
  the tests.

MiMo also omitted required baseline reads. It stayed within the modification
scope and did not fabricate manual TCC, removable-volume, or macOS 15 evidence.

## Codex Corrections

Codex replaced the lifecycle core rather than accepting incremental patches:

- added explicit `idle/running/stopping/stopped` state and a registration-owned
  completion group;
- made stop an initiation boundary and `waitUntilStopped` a real bounded
  completion boundary;
- queued teardown after callbacks and ordered Stop, Invalidate, Release, context
  release, final state, and completion without inline C-callback destruction;
- added a single-consume callback-context lease and immutable registration
  identity/generation;
- replaced `unsafeBitCast` with checked `CFArray` access and recorded bridge
  failures;
- validated the opened object with `open`/`fstat`, preserving typed POSIX errors;
- used uptime timestamps and strengthened replacement, callback-stop, timeout,
  post-teardown, context lifetime, deinit, and fixture cleanup tests;
- updated the probe to use `stopAndWait` and corrected all evidence wording.

## Independent Verification

```text
bash -n build.sh test.sh: exit 0
bash test.sh × 3: exit 0 each; 69 passed, 0 failed each
bash build.sh: exit 0
bounded two-second mutation probe: exit 0
build invalid / test invalid / probe no args / missing path: 64 / 64 / 64 / 1
```

First-event latency samples were 0.312658, 0.279651, and 0.182934 seconds. The
replacement fixture retained the displaced original inode, mutated both old and
new directories, and observed only the uniquely named replacement child. Each
rapid-operation run delivered all 20 unique child paths in one callback batch.
The callback-stop fixture performed a post-teardown mutation, and each real-event
fixture asserted zero callback bridge failures. The bounded probe coalesced a
create/delete pair into one item record.

The final probe is arm64, minimum macOS 15.0, SDK 26.5, depends only on system
frameworks and Swift runtimes, and has a linker-generated ad-hoc signature.

## Remaining Uncertainty

1. TCC-protected folders, removable media/ejection, symlinks, network volumes,
   actual macOS 15, and long-running/load behavior remain untested.
2. Dropped-event recovery, production reattachment, resource cost, and latency
   alternatives remain unimplemented.
3. Context lifetime counts are lifetime evidence only. Exactly-once token
   consumption follows from the lock-protected lease structure, not an ARC
   retain-count measurement.

Neither candidate is selected. Phase 0.5C comparison and background enumeration,
stale-result, cancellation, access, and resource evidence remain required. Full
Spike 0.5 remains incomplete.
