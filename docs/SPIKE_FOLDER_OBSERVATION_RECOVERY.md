Status: In Progress — Phase 0.5C3 local path evidence only

# Spike 0.5C3 — Observer Path and Recovery Evidence

## Scope

This disposable harness compares local DispatchSource and FSEvents behavior for
missing roots, symlink roots, child symlinks, renamed roots, and pathname
replacement. It compiles the reviewed candidate sources directly.

It does not implement recovery, select an observer, change production
architecture, or complete Spike 0.5.

## Commands and Structure

```text
spikes/folder-observation-recovery/
├── Sources/main.swift
├── Tests/main.swift
├── build.sh
└── test.sh
```

```bash
cd spikes/folder-observation-recovery
bash build.sh
bash test.sh
```

The probe interface is:

```text
recovery-probe --candidate dispatch|fsevents \
  --scenario missing-root|symlink-root|child-symlink|root-rename|path-replacement \
  --timeout S
```

## Evidence Design

Each process uses a private fixture under its own `TMPDIR`. Every filesystem
mutation arms a new evidence token immediately before the mutation. A callback
can satisfy only the active token.

- DispatchSource tokens match the required directory-level flag. Its callback
  has no child path, so the evidence means a directory invalidation arrived in
  that isolated, bounded mutation window.
- FSEvents item tokens match the canonical unique marker path where available
  plus an item flag. Root rename tokens match `RootChanged`; symlink creation
  matches `ItemIsSymlink`.
- Required windows use the requested timeout. Optional absence windows are
  bounded to at most 0.75 seconds and are recorded as local data, not proof of
  permanent absence.
- A 0.4-second disarmed quieting interval separates transition, old-inode, and
  replacement-path windows. This reduces cross-window delivery but is not a
  platform guarantee.

Every started observer uses throwing, bounded teardown. Primary and teardown or
cleanup errors are preserved together. JSON is emitted only after fixture
cleanup succeeds. Missing-root errors are extracted by matching concrete enum
cases and retain the actual POSIX code.

## Final Local Results

These results are from the final independent matrix on macOS 26.6 with SDK
26.5. Each result had `cleanupOK == true`; every started observer ended in
`stopped`; every FSEvents bridge count was zero.

| Scenario | DispatchSource | FSEvents |
|---|---|---|
| Missing root | `openFailed`, `ENOENT` | `pathNotFound`, `ENOENT` |
| Symlink root marker | received `.write`; observed identity equaled target identity | received target `ItemCreated` record |
| Child symlink creation | received `.write` | received `ItemCreated, ItemIsSymlink` record |
| External target marker | not received in optional window | not received in optional window |
| Root rename | received `.rename` | received `RootChanged` |
| Marker in moved root | received `.write` | not received in optional window |
| Replacement transition | received `.rename` | received `RootChanged` |
| Marker in moved old inode | received `.write` | not received in optional window |
| Marker at replacement pathname | not received in optional window | received replacement `ItemCreated` record |

Independent stats proved the renamed/moved directory retained its original
device/inode and the replacement directory had a different inode. The
DispatchSource observer identity equaled the original/moved identity.

This local evidence distinguishes the candidates' current registrations:
DispatchSource remained attached to the opened inode, while this FSEvents
`WatchRoot` stream reported the replacement pathname after `RootChanged` and did
not report markers under the moved path in the bounded windows. Alcove still
needs an explicit product recovery policy; neither behavior is selected here.

## Automated Verification

Three consecutive final `bash test.sh` runs each passed **238 assertions with 0
failures**. The strict Codable test matrix covers all ten candidate/scenario
combinations, unique step sequences, required evidence, latency/flag
consistency, concrete missing-root errors, independent identities, FSEvents
bridge state, throwing teardown, and probe-owned cleanup.

Error coverage includes invalid arguments (exit 64), a real FSEvents 0.001-second
event timeout (exit 1 with the named evidence step and probe cleanup), and an
outer TERM/SIGKILL watchdog that confirms process exit before reading pipes.

`bash build.sh` exited 0. The probe is an arm64 Mach-O with minimum macOS 26.0,
SDK 26.5, Apple system frameworks/Swift runtime only, and a linker-generated
ad-hoc signature. This is build-target evidence, not an actual macOS 27 run.

## Codex Review Corrections

MiMo produced a buildable initial harness, but its 128/128 report was rejected:
the second-window signal was never called, replacement events were conflated
with the earlier move, missing-root errno was fabricated from strings, teardown
errors were converted into success strings, and tests accepted missing fields.

Codex replaced the event/window model, typed error handling, lifecycle wrapper,
identity evidence, strict schema tests, and the inaccurate documentation. The
MiMo metrics and behavioral claims are superseded.

## Limitations and Remaining Evidence

- Optional false results are bounded local absence, not guaranteed non-delivery.
- DispatchSource cannot identify the child path that caused `.write`.
- FSEvents latency/coalescing and results may differ across OS/filesystems.
- Actual macOS 27, TCC-protected folders, removable/ejected volumes, network
  volumes, dropped-event/revoke recovery, sustained load, and multiple observers
  remain unverified.

## Gate Status

Phase 0.5C3 records local path-transition evidence only. No observer is selected,
no recovery policy is implemented, and full Spike 0.5 remains incomplete.
