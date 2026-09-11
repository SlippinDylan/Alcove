# Slice 10C Result — Folder Recovery

## Implemented

- Missing, replaced, and non-directory mappings display Locate Folder with the
  affected path.
- Permission and read failures display Retry; permission guidance accurately
  says macOS *may* require Files and Folders access rather than claiming every
  POSIX denial is TCC.
- Unknown load and observation failures also provide a Retry path.
- Retry rebuilds observation before reloading so recovery does not leave a
  visible but permanently unobserved portal.
- Locate Folder reuses the directory-only system picker and fixed-internal-disk
  validator. Removable, ejectable, external, and network volumes remain rejected.
- A successful remap preserves `FolderTabID`, portal placement, selected tab,
  icon size, and other tabs. The complete state is persisted before the live
  window changes.
- Save failure and picker cancellation preserve the existing mapping.

## Manual Verification

The real system picker, controlled TCC denial, and replacement-inode UI flow
remain manual checks. Automated tests cover state/action mapping and the
persistence transaction boundary.

## Automated Verification

- AlcoveCore: 110 tests passed.
- Hosted app: 111 tests passed.
- Unsigned Release build: universal `arm64` and `x86_64`, minimum macOS 15.0.
