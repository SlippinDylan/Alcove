# Phase 0.5C6 — Folder Location Eligibility

## Goal

Record the confirmed product rule that Alcove accepts mapped folders only on the
Mac's internal, fixed local storage. Create a disposable Swift harness that
validates this rule at folder-selection and re-mapping boundaries.

## Scope

- Read public Foundation volume metadata from a resolved directory URL.
- Accept only local, internal, non-removable, non-ejectable volumes.
- Reject missing metadata, removable/ejectable storage, external volumes, and
  network volumes before a tab is created or changed.
- Resolve symbolic links before classifying the hosting volume.
- Keep DispatchSource/FSEvents selection, TCC behavior, and production UI out of
  this work unit.

## Verification

- Swift 6 complete strict concurrency, warnings as errors, macOS 15 target.
- Pure policy tests for every accepted/rejected metadata state.
- Real local directory, symlink, regular-file, and missing-path tests.
- Invalid CLI arguments and machine-readable live-volume inspection.
- Three consecutive final test runs plus artifact inspection.
