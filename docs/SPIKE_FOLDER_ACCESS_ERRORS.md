Status: In Progress — Phase 0.5C5 local access evidence only

# Spike 0.5C5 — Folder Access and Error Classification

## Scope

This disposable command-line harness records read-only local enumeration
outcomes for Desktop, Documents, and Downloads and validates error
classification with owned temporary fixtures. It does not change TCC settings,
request Full Disk Access, select an observer, test volume ejection, or complete
Spike 0.5.

## Commands

```bash
cd spikes/folder-access-errors
bash build.sh
bash test.sh
build/folder-access-probe protected-locations
build/folder-access-probe fixtures
build/folder-access-probe all
```

The scripts use Swift 6 complete strict concurrency, warnings as errors, and
`arm64-apple-macosx15.0`. Only Foundation, Dispatch, Darwin, and Swift runtimes
are linked.

## Evidence Boundary

The probe was launched from the current Codex shell as an ad-hoc-signed,
non-App-Sandbox CLI on macOS 26.6 (25G72), SDK 26.5. TCC attribution can depend
on the responsible process chain and prior user decisions. The harness does not
query whether Full Disk Access is enabled and does not identify which prior
decision allowed a successful read.

The protected-location command prints category, count or raw error metadata,
and generation/background evidence. It never prints child names or child paths.
Every `contentsOfDirectory` call runs on a dedicated background queue with a
bounded completion wait. The returned generation must still equal the current
request generation before the result is accepted. A one-shot FileManager call
is not described as cancellable while it is executing.

## Actual Protected-Location Result

One final local sample on 2026-08-02 produced:

| Category | Outcome | Entry count | Error |
|---|---|---:|---|
| Desktop | allowed | 30 | none |
| Documents | allowed | 12 | none |
| Downloads | allowed | 9 | none |

All three results carried distinct matching request/result generations and
reported `executedOnMainThread: false`. This proves only that this process was
allowed at that time. It is not a denial test, does not prove TCC is absent, and
does not prove another build identity or machine will receive the same result.
No permission prompt was observed or automated.

## Owned Real-Filesystem Evidence

All mutations occur under a unique private `TMPDIR`. Error evidence keeps the
original enumeration NSError domain/code and one nested underlying domain/code.
Independent Darwin directory-open probes record real POSIX errno separately;
the classifier never rewrites Cocoa metadata into a fabricated POSIX error.

| Fixture | Enumeration NSError | Underlying | Independent open |
|---|---|---|---:|
| Missing path | `NSCocoaErrorDomain` 260 | `NSOSStatusErrorDomain` -43 | `ENOENT` 2 |
| Regular file as directory | `NSCocoaErrorDomain` 256 | `NSPOSIXErrorDomain` 20 | `ENOTDIR` 20 |
| Mode-000 directory | `NSCocoaErrorDomain` 257 | `NSPOSIXErrorDomain` 13 | `EACCES` 13 |

The accessible control independently enumerated exactly two entries. Every
fixture enumeration ran off the main thread. The permission fixture was
restored before root cleanup. A classification mismatch, inability to produce
real EACCES/EPERM, restoration failure, or cleanup failure is fatal and prevents
success JSON.

## Error Presentation Boundary

| Classification | Supported presentation |
|---|---|
| `folderNotFound` | “Folder not found”; offer Locate Folder or portal removal |
| `notDirectory` | “This path is not a folder”; offer re-mapping |
| `permissionDenied` | “Permission denied” with the folder category/name and retry guidance |
| `enumerationFailed` | “Unable to read folder contents”; retain diagnostics and offer retry |

For a protected-location result that actually returns permission denied, Alcove
may explain that macOS Files and Folders privacy settings can be relevant. A
generic POSIX EACCES fixture does not prove TCC caused the denial, so the
classifier itself does not label errors as TCC. `volumeNotAvailable` remains
unvalidated without real ejection evidence.

## Automated Verification

Three consecutive final `bash test.sh` runs each passed **124 assertions with 0
failures**. The suite verifies:

- exact protected and fixture cardinalities, categories, mutually exclusive
  success/error fields, background execution, request/result generations, and
  unknown-key rejection at every machine-readable output layer;
- real Cocoa/underlying metadata plus independent ENOENT, ENOTDIR, and EACCES;
- raw metadata preservation without fabricated POSIX codes;
- rejection of a real background enumeration result made stale before apply;
- bounded background timeout followed by proven worker convergence;
- fatal real chmod-restoration failure and injected cleanup-failure seams;
- no-argument, unknown, and extra-argument exit 64 behavior;
- private runner TMPDIR cleanup, active stdout/stderr draining, a 620,000-byte
  output child, and a TERM-resistant child requiring real `SIGKILL`;
- fail-closed prohibited-pattern scans in both build scripts.

If a fixture enumeration reaches its deadline but the synchronous FileManager
call still has not returned, the probe waits a second bounded convergence window
and deliberately does not delete the root while I/O is active. The required
test runner then terminates the child and owns cleanup of its private `TMPDIR`.
A directly invoked standalone probe lacks that outer owner in this exceptional
path and can leave its uniquely named temporary root for later cleanup; this is
one reason the harness is not production recovery code.

The final probe is arm64, minimum macOS 15.0, SDK 26.5, system/Swift-only, and
linker ad-hoc signed. This inspects the deployment target; it is not a macOS 15
runtime result.

## Codex Review

MiMo produced a buildable first version and reported 46/46. Codex rejected that
evidence because typed results rewrote NSError metadata, cleanup/restoration
failures still exited 0, fixture I/O ran on the main thread, generation checks
were disconnected from work, `interrupt()` was mislabeled as SIGKILL, waits
were unbounded, and timeout/large-output/cleanup tests were self-proving. Codex
replaced those paths and the tests. The original MiMo metrics and conclusions
are superseded.

## Remaining Gate Work

- A real protected-location denial under a controlled TCC state and user-observed
  authorization UI.
- Physical removable-volume ejection and reattachment.
- An available network-volume mount.
- Dropped/revoke recovery and the observer/recovery policy decision.
- Actual macOS 15 execution.

No observer is selected. Full Spike 0.5 remains incomplete.
