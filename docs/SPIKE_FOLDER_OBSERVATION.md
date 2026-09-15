Status: In Progress — Phase 0.5A DispatchSource bootstrap only

# Spike 0.5 — Folder Observation and Permissions

## Scope

Phase 0.5A is a disposable command-line Swift harness for candidate A only: one `DispatchSourceFileSystemObject` observing one directory descriptor. It does not implement FSEvents, blocking enumeration, debounce, automatic reattachment, or a production `FolderAccess` module. It does not select an observation strategy or complete Spike 0.5.

## Structure

```text
spikes/folder-observation/
├── Sources/
│   ├── DispatchSourceFolderObserver.swift
│   ├── FolderObservationRecord.swift
│   ├── FolderObserverError.swift
│   └── main.swift
├── Tests/main.swift
├── build.sh
└── test.sh
```

The scripts compile with Swift 6 complete strict concurrency, warnings as errors, and `arm64-apple-macosx26.0`. The harness uses only Foundation, Dispatch, and Darwin public APIs.

## Commands

```bash
cd spikes/folder-observation
bash test.sh
bash build.sh
build/folder-observer-probe <existing-directory> [duration-seconds]
```

The probe duration is bounded to 60 seconds and invalid setup exits nonzero.

## Candidate Adapter

The adapter opens the target with `O_EVTONLY | O_CLOEXEC`, then validates the opened object with `fstat`. This avoids treating an earlier path lookup as proof about the descriptor actually being observed. The recorded device/inode identity is diagnostic evidence for replacement tests.

The candidate mask is:

```swift
[.write, .rename, .delete, .revoke]
```

On this runtime, immediate-child create, rename, and delete operations each produced a subsequent directory-level `.write` event. Renaming and deleting the observed directory itself produced `.rename` and `.delete`, respectively. `.revoke` is included for later removable-volume investigation but has not been observed.

DispatchSource does not report which child changed. Multiple operations and flags may coalesce, so a consumer must treat an event as an invalidation signal and re-enumerate rather than infer a child path.

## Ownership and Concurrency

- A condition lock protects lifecycle state, source ownership, registration identity, generation, inode identity, and active callback count.
- The user callback is immutable after initialization.
- Start validates, creates, configures, stores, and resumes the source as one locked transaction. A concurrent stop cannot return during an uncommitted start and later leave it running.
- A fixed-FD cancellation owner is captured independently of the observer. The cancel handler therefore closes and signals teardown even if the observer is deallocated.
- `stop()` invalidates delivery and initiates cancellation. An external caller waits for an active user callback to return; a callback may initiate stop without waiting on itself.
- `waitUntilStopped(timeout:)` provides bounded teardown proof and rejects use on the source event queue, where waiting would deadlock the cancel handler.
- Waiting completes only after the captured descriptor has been closed and observer state has been finalized. Close failures are mapped to a typed error.
- Each event checks the one-shot registration identity and generation before entering user delivery. After teardown completes, no callback can still be active or newly accepted.

The observer uses a narrowly scoped `@unchecked Sendable` conformance because Dispatch source and Foundation lock types do not provide a useful checked aggregate conformance. Mutable state is not left unprotected; this spike does not use `nonisolated(unsafe)` or `@preconcurrency` to silence diagnostics.

## Automated Evidence Executed by Codex

Final verification on 2026-08-02 ran `bash test.sh` three consecutive times. Each clean Swift 6 warning-as-error compile passed 45 explicit assertions with 0 failures:

- missing path retains `ENOENT`, regular files are rejected after descriptor `fstat`, and failed starts retain no descriptor;
- duplicate start, terminal restart, idempotent stop, and teardown-before-stop errors are explicit;
- isolated child create, rename, and delete fixtures each trigger a real `.write` event without relying on a preceding operation's callback;
- uptime-based first-event latency measured 0.000072–0.000085 seconds across the three final local runs;
- observed-directory rename and delete deliver real `.rename` and `.delete` flags on this runtime;
- directory replacement resolves to a different inode, mutation of the replacement produces no old-source callback within 500 ms, and mutation of the displaced original inode provides a positive callback control;
- a callback can initiate stop without deadlock;
- external stop does not return while a user callback is active;
- mutation after completed teardown produces no callback within 400 ms;
- teardown reports closure and `fcntl(F_GETFD)` returns `EBADF` for the captured descriptor;
- releasing a running observer initiates cancellation and closes its captured descriptor within the bounded test timeout;
- every temporary-directory transaction reports cleanup errors, and an explicit cleanup test confirms removal.

The latency values and negative-event windows are local bounded observations, not platform guarantees.

`bash build.sh` exited 0 and produced an arm64 Mach-O probe with minimum macOS 26.0, SDK 26.5, system/Swift runtime dependencies only, and a linker-generated ad-hoc signature. Repeated one-second probe runs observed one or two real `.write` callbacks for the same spaced create/delete sequence, demonstrating local coalescing variability; each exited 0 with descriptor teardown confirmed.

Error-path verification:

| Command | Exit |
|---|---:|
| `bash build.sh invalid` | 64 |
| `bash test.sh invalid` | 64 |
| probe without arguments | 64 |
| probe with a missing path | 1 |

## Directory Replacement Finding

The local test provides two-sided evidence that a source follows the opened object rather than a later object at the same pathname: the replacement has a different inode and does not notify the old source, while a write inside the renamed original directory does notify it. No automatic path reattachment is implemented. Phase 0.5B must compare the corresponding FSEvents path behavior and recovery options.

## Manual and Deferred Evidence

| Test | Status |
|---|---|
| TCC-protected Desktop/Documents/Downloads access | NR |
| Removable volume and physical ejection / `.revoke` | NR |
| Actual macOS 27 runtime | NR |
| Symlink root and child behavior | NR |
| Network volume behavior | NR |
| 500/1000/5000-item CPU and memory measurements | NR |
| Long-running observation and sustained mutation load | NR |
| Multiple simultaneous observers | NR |
| Synthetic descriptor-close failure injection | NR |

Blocking directory enumeration is also deferred. A later work unit must prove its explicit off-main execution boundary, stale-generation rejection, and truthful cancellation granularity. A one-shot synchronous enumeration call must not be described as interruptible midway.

## Gate Status

Phase 0.5B must implement and measure the FSEvents candidate before comparison. TCC, removable-volume, symlink, resource, long-running, and enumeration evidence also remains open.

DispatchSource is not selected as Alcove's production observation mechanism. Full Spike 0.5 remains incomplete.
