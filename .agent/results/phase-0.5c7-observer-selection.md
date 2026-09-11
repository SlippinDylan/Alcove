# Phase 0.5C7 — Observer Selection Result

## Decision

FSEvents with `FileEvents`, `WatchRoot`, and `UseCFTypes` is selected as Alcove's
only production folder observer. DispatchSource remains useful evidence but is
not a production fallback or second observer.

The selection is based on the reviewed 0.5A–0.5C6 evidence and an independent
read-only review. Both candidates met lifecycle and load requirements. FSEvents
was selected for explicit root-change and dropped/wrapped-event signals; its
configured local latency of about 0.3 seconds is acceptable because Alcove
debounces events into full snapshot refreshes rather than applying item deltas.

## Recovery Contract

- Ordinary item records request a debounced full snapshot refresh.
- `MustScanSubDirs`, `UserDropped`, `KernelDropped`, `EventIdsWrapped`, or
  `RootChanged` rebuild observation and fully enumerate.
- Rebuild invalidates the generation, tears down the old stream, revalidates path,
  supported volume, and device/inode, then starts a fresh stream before enumerating.
- Missing or different root identity maps to `folderNotFound` and requires
  explicit `Locate Folder…`; replacement content is never adopted silently.
- All results remain subject to generation-based stale rejection.

## Verification

- Three consecutive `bash test.sh` runs: 17 assertions, 0 failures each.
- Standalone MustScanSubDirs/UserDropped probes: exit 0 and rebuild action.
- Invalid build, test, and probe arguments: exit 64.
- Artifact: arm64, macOS 15.0 minimum, SDK 26.5, system/Foundation/Swift only,
  linker-generated ad-hoc signature.
- `git diff --check`: exit 0 after documentation synchronization.

## Remaining Gate

Observer selection and recovery policy are complete. Full Spike 0.5 remains open
for production recovery orchestration, controlled TCC denial/retry evidence,
and an actual macOS 15 runtime check. Child-symlink enumeration is covered by
the extended Phase 0.5C1 real-filesystem test.
