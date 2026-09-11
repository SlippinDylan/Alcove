# Phase 0.5C7 — Observer Selection and Recovery Contract

## Goal

Use the reviewed Phase 0.5 evidence to select one production folder-observation
candidate for Alcove's supported internal fixed local folders and define the
minimum recovery contract for ordinary, dropped, wrapped, and root-change
events.

## Decision Boundary

- Preserve the complete MVP scope.
- Do not work on signing or distribution.
- Do not implement production UI or `FolderAccess` modules.
- Do not add a DispatchSource/FSEvents hybrid without evidence that it is needed.
- Preserve folder identity: a different device/inode at the same path requires
  explicit user re-mapping rather than silently adopting replacement content.

## Verification

- Compile the reviewed FSEvents record decoder directly.
- Verify every recovery flag maps to a full observation rebuild.
- Verify normal item evidence maps to snapshot refresh.
- Verify missing and replaced root identity decisions.
- Run three consecutive Swift 6 warning-as-error tests on the macOS 15 target.
