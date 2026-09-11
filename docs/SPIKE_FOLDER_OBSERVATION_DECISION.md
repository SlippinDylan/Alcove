Status: Complete — Phase 0.5C7 observer selection and recovery contract

# Spike 0.5C7 — Folder Observation Decision

## Decision

Select FSEvents with `FileEvents`, `WatchRoot`, and `UseCFTypes` as Alcove's one
production observation mechanism. Do not combine it with DispatchSource.

This decision is for mapped folders on supported internal fixed local storage.
Removable, ejectable, external, and network-volume lifecycle behavior is outside
the product scope.

## Why FSEvents

Both reviewed candidates passed lifecycle, load, multiple-observer, teardown,
descriptor-settling, and local mutation evidence. DispatchSource delivered much
lower local latency, but Alcove does not consume child-level deltas: every event
invalidates and re-enumerates the current snapshot. The configured FSEvents
latency of about 0.3 seconds is acceptable for that refresh model.

FSEvents provides the stronger recovery contract for Alcove's high-reliability
MVP: explicit item paths, `RootChanged`, `MustScanSubDirs`, `UserDropped`,
`KernelDropped`, and `EventIdsWrapped`. DispatchSource has no equivalent dropped-
event signal and remains attached to the opened inode after pathname replacement.

## Folder Identity

FSEvents following a replacement pathname is evidence, not permission to adopt
unrelated content. Alcove records the observed root device/inode for the active
registration. On `RootChanged` or any recovery flag:

1. Invalidate the current generation and stop the old stream with bounded
   teardown.
2. Resolve and validate the mapped path and supported-volume policy again.
3. If the path is missing, present `folderNotFound`.
4. If device/inode differs, present `folderNotFound` and require explicit
   `Locate Folder…` re-mapping; do not silently adopt replacement content.
5. If identity matches, start a fresh stream before beginning a full background
   enumeration.
6. Apply the enumeration only if its generation remains current. An event that
   arrives during enumeration invalidates that result and schedules another full
   refresh.

Ordinary item records debounce into a complete snapshot refresh. Alcove never
applies FSEvents records as an incremental file-list patch.

## Verification

Three consecutive final `bash test.sh` runs each passed 17 assertions with zero
failures. The policy tests compile the reviewed Phase 0.5B FSEvents record
decoder directly and cover ordinary item evidence, every rebuild flag, mixed
ordinary/recovery flags, unchanged identity, missing roots, same-path inode
replacement, and device replacement.

Standalone probes decoded real public flag constants for `MustScanSubDirs` and
`UserDropped` and selected `rebuildObservation`. Invalid build, test, and probe
arguments each exited 64. The probe is arm64, targets macOS 15.0 with SDK 26.5,
uses system/Foundation/Swift dependencies, and has a linker-generated ad-hoc
signature.

## Remaining Gate Work

- Verify the recovery orchestration in production `FolderAccess` integration.
- Record controlled TCC denial and recovery with an actual Alcove app identity.
- Run the relevant compatibility matrix on an actual macOS 15 environment.

These remaining items keep full Spike 0.5 open, but they no longer block the
observer mechanism decision.
