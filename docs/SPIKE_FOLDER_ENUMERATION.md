Status: In Progress — Phase 0.5C1 enumeration bootstrap only

# Spike 0.5C1 — Background Directory Enumeration

## Scope

This disposable Swift harness proves one Phase 0.5C capability: immediate-child
enumeration runs on an explicit non-main worker boundary, and stale or cancelled
results do not publish. It is not production `FolderAccess`, does not compare or
select observers, and does not complete Spike 0.5.

## Commands

```bash
cd spikes/folder-enumeration
bash test.sh
bash build.sh
build/folder-enumeration-probe <existing-directory>
```

The scripts compile nine source files with Swift 6 complete strict concurrency,
warnings as errors, and `arm64-apple-macosx15.0`. Only public Foundation,
Dispatch, and Darwin APIs are used.

## Design

- `ChildEntry` and `DirectorySnapshot` are immutable Sendable values. Enumeration
  is immediate-child only. Directories sort first, then names use
  locale-independent lexical order with a path tie-breaker; this is not Finder
  sort equivalence.
- `DirectoryEnumerator` maps FileManager failures to typed path/domain/code
  evidence. Target validation uses `open(O_EVTONLY | O_CLOEXEC)` plus `fstat` and
  closes the descriptor before enumeration; it is a preflight, not an identity
  guarantee for the later call.
- `WorkerQueue` is concurrent so a newer request can finish while an older
  synchronous call is blocked. `execute` has a bounded wait. Timeout returns to
  the caller but does not pretend to stop the already-running closure.
- `EnumerationRequestRunner` checks cancellation before scheduling, immediately
  before filesystem work, and after the blocking call. It also verifies that the
  call ran off the main thread on the configured worker queue.
- `Coordinator` issues checked monotonically increasing generations. It publishes
  only the current, non-cancelled snapshot; counter exhaustion is a typed error.

## Automated Evidence Executed by Codex

On 2026-08-02, three consecutive clean test runs each passed **67 assertions with
0 failures**:

- empty and populated real directories produced typed immediate-child snapshots,
  deterministic directory/file ordering, and no grandchildren;
- missing path, regular file, injected FileManager failure, and generation
  exhaustion retained typed evidence and did not publish state;
- real enumeration ran off the main thread on the configured queue;
- generation N was blocked while N+1 completed and published, after which the
  actual N worker result was rejected as stale;
- a pre-cancelled request did not invoke its enumerator;
- cancellation during a semaphore-blocked synchronous call did not interrupt the
  call; after release, the runner returned typed cancellation and no snapshot;
- a 100 ms worker timeout returned a typed error while the released call later
  completed, proving the timeout is not fake cancellation;
- later requests recovered after stale/cancelled work;
- fixture creation/close helpers throw on failure, and an injected cleanup
  failure is observed and propagated rather than logged and ignored.

`bash build.sh` exited 0. An isolated probe enumerated one directory and two files
in deterministic order with zero metadata errors and exited 0. The arm64 Mach-O
has minimum macOS 15.0, SDK 26.5, system/Swift runtime dependencies only, and a
linker-generated ad-hoc signature.

| Error path | Exit |
|---|---:|
| `bash build.sh invalid` | 64 |
| `bash test.sh invalid` | 64 |
| probe without arguments | 64 |
| probe with missing path | 1 |

## Deferred Evidence

The following remain not run: TCC-protected folders, removable/ejected volumes,
actual macOS 15, symlink and network-volume behavior, 500/1000/5000-item resource
measurements, sustained load, incremental enumeration, and observer resource and
recovery comparison.

A synchronous `FileManager.contentsOfDirectory` call cannot be cancelled midway.
Cancellation and timeout can suppress acceptance before or after the call; they
do not interrupt it. Incremental/batched enumeration would require a separate
design and evidence.

This command-line bootstrap also waits synchronously for its background result.
A production AppKit integration must expose an async/completion boundary so the
MainActor does not block while the worker runs; that integration is not proven
here.

Neither DispatchSource nor FSEvents is selected. Phase 0.5C comparison and the
remaining access/resource matrix remain open. Full Spike 0.5 remains incomplete.
