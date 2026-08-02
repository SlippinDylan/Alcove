Status: In Progress — Phase 0.5B FSEvents bootstrap only

# Spike 0.5B — FSEvents Folder Observation

## Scope

Phase 0.5B is a disposable Swift command-line harness for candidate B: one
`FSEventStream` observing one directory root. It measures local event records,
path replacement, latency, and lifecycle behavior. It does not implement
production `FolderAccess`, blocking enumeration, debounce, automatic
reattachment, or recovery from dropped events. It neither selects an observation
strategy nor completes Spike 0.5.

## Structure and Commands

```text
spikes/folder-observation-fsevents/
├── Sources/
│   ├── FSEventError.swift
│   ├── FSEventRecord.swift
│   ├── FSEventsFolderObserver.swift
│   └── main.swift
├── Tests/main.swift
├── build.sh
└── test.sh
```

```bash
cd spikes/folder-observation-fsevents
bash test.sh
bash build.sh
build/folder-observer-fsevents-probe <existing-directory> [duration-seconds]
```

Both scripts use Swift 6 complete strict concurrency, warnings as errors, and
`arm64-apple-macosx15.0`. The harness uses public CoreServices, CoreFoundation,
Foundation, Dispatch, and Darwin APIs only. The bounded probe accepts durations
up to 60 seconds.

## Candidate Configuration

The observer opens the target with `O_EVTONLY | O_CLOEXEC`, validates the opened
object with `fstat`, and closes that validation descriptor before creating the
stream. This narrows path-validation races without claiming that the validation
descriptor defines what the later path-based stream observes.

The stream starts at `kFSEventStreamEventIdSinceNow`, uses a provisional
0.3-second latency, and combines:

```swift
kFSEventStreamCreateFlagUseCFTypes
    | kFSEventStreamCreateFlagFileEvents
    | kFSEventStreamCreateFlagWatchRoot
```

`UseCFTypes` supplies a `CFArray` of paths, `FileEvents` requests item-level
records, and `WatchRoot` requests root-change evidence. Delivered flags are
evidence that consumers must use to invalidate and re-enumerate; they are not a
guaranteed one-record-per-operation journal.

## Ownership and Lifecycle

- Lifecycle state is `idle`, `running`, `stopping`, or `stopped` and is protected
  by a lock. The stream callback runs on one private serial lifecycle queue.
- Start performs validation, stream creation, queue assignment, stream start,
  and state publication as one locked transaction.
- `stop()` only invalidates event acceptance and schedules teardown. It is
  idempotent and safe when invoked inside the callback; it does not claim that
  resources have already been released.
- Teardown is queued after the active callback returns, then calls Stop,
  Invalidate, and Release, releases the callback-context token once, and marks
  the observer stopped.
- `waitUntilStopped(timeout:)` is the bounded completion boundary. Waiting on
  the lifecycle queue is rejected because it would deadlock. Repeated external
  waits share the same registration completion group.
- Each callback checks immutable registration identity and generation before
  user delivery. Once stopping begins, later records are suppressed.
- A lock-protected lease makes the `Unmanaged.passRetained` token single-consume.
  Runtime tests count `CallbackContext` construction and destruction as lifetime
  evidence; they do not pretend to observe ARC retain counts directly.
- Deinitializing a running observer schedules the same asynchronous teardown.
  The registration owns the resources until teardown finishes, while its owner
  reference remains weak.

The `@unchecked Sendable` conformances are limited to lock-protected reference
boundaries needed by the C callback and Dispatch closures. The event callback is
immutable.

## Automated Evidence Executed by Codex

On 2026-08-02, three consecutive clean `bash test.sh` runs each passed **69
assertions with 0 failures**. The observed first-event latency samples were
0.312658, 0.279651, and 0.182934 seconds. Local filesystem evidence included:

- missing paths preserve `ENOENT`; regular files are rejected; failed starts
  remain idle;
- duplicate start, terminal restart, wait-before-stop, bounded teardown timeout,
  and repeated stop errors are exercised;
- isolated child create, rename, and delete tests verify paths and relevant
  `ItemCreated`, `ItemRenamed`, `ItemRemoved`, and `ItemIsFile` flags;
- root rename and delete delivered `RootChanged` on this runtime;
- replacement moved the original inode aside, created a different inode at the
  observed path, and mutated both: only the uniquely named replacement child was
  delivered, providing positive and negative pathname evidence for this local
  stream;
- 20 rapid file creations produced 20 unique item paths in one callback batch in
  each final run; this is a local sample, not a no-coalescing guarantee;
- callback-initiated stop returned without deadlock, a blocked callback caused a
  real 100 ms teardown timeout, and new filesystem mutations after both callback-
  initiated and external teardown produced no user callbacks during bounded 400
  ms negative windows;
- every real-event fixture ended with zero callback bridge failures;
- callback-context construction/destruction balanced after explicit teardown and
  after observer deinitialization;
- temporary fixtures use transactional cleanup with cleanup failures reported.

`bash build.sh` exited 0. A two-second probe observed an actual create/delete
mutation as one coalesced item record and exited 0 after `stopAndWait`. Artifact
inspection reported an arm64 Mach-O executable, minimum macOS 15.0, SDK 26.5,
system/Swift runtime dependencies only, and a linker-generated ad-hoc signature.

| Error-path command | Exit |
|---|---:|
| `bash build.sh invalid` | 64 |
| `bash test.sh invalid` | 64 |
| probe without arguments | 64 |
| probe with a missing path | 1 |

These timings, flags, record counts, and negative-event windows are bounded local
observations, not platform guarantees.

## Candidate Comparison So Far

| Behavior | DispatchSource 0.5A | FSEvents 0.5B |
|---|---|---|
| Event scope | Directory invalidation flags; no child path | Item paths and flags with `FileEvents` |
| Root lifecycle | Descriptor `.rename` / `.delete` | `RootChanged` locally |
| Replacement | Continues following opened inode | Delivered a unique child below replacement pathname locally |
| Local latency samples | 0.000072–0.000085 s | 0.182934–0.312658 s |
| Local rapid-operation sample | Coalescing varied across probes | 20 item paths in one callback batch |
| Persistent descriptor | Yes | Validation descriptor closes before stream creation |

This table is incomplete. It does not establish resource cost, removable-volume
recovery, protected-folder behavior, long-running reliability, or a production
winner.

## Manual and Deferred Evidence

All entries remain not run (`NR`):

- TCC-protected Desktop, Documents, and Downloads access;
- removable volumes, physical ejection, and reattachment;
- an actual macOS 15 runtime;
- symlink roots and children, network volumes, and missing-root recovery;
- 500/1000/5000-item CPU and memory measurements;
- long-running load and multiple simultaneous observers;
- `NoDefer`, zero-latency, and alternative latency measurements;
- `MustScanSubDirs`, `KernelDropped`, and `UserDropped` recovery;
- resource comparison against DispatchSource.

Blocking directory enumeration is deferred to Phase 0.5C. It must prove an
explicit off-main execution boundary, stale-generation rejection, and truthful
cancellation granularity. A synchronous `FileManager` enumeration call must not
be described as interruptible midway.

## Gate Status

Neither DispatchSource nor FSEvents is selected. Phase 0.5C must compare the two
candidates and add background enumeration, stale-result, cancellation, resource,
and remaining access/lifecycle evidence. Full Spike 0.5 remains incomplete.
