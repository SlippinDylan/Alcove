# Slice 2 — Minimal Single Portal Result

## Implemented

- `AlcoveCore`: pure FileIdentity/FileItem/IconSize/GridLayout values; derived
  column count is not persistence state.
- FolderAccess: async dedicated-queue immediate-child enumeration, directories-
  first localized-standard sorting, hidden filtering, diagnostics, typed root
  errors with NSError metadata, fixed-internal-local eligibility, and generation
  stale/cancellation rejection.
- AppKit portal: replaceable desktop window strategy, resizable/movable NSWindow,
  scrollable native NSCollectionView icon grid, loading/empty/error states.
- Development composition: `Alcove --folder <path>` validates the location and
  creates one portal without introducing the Slice 4 production picker flow.

## Verification

- `swift test --package-path Packages/AlcoveCore`: 9 tests, 0 failures.
- Hosted `AlcoveTests`: 19 tests, 0 failures.
- Real filesystem tests cover localized-standard ordering, hidden filtering,
  immediate-child/symlink semantics, missing/not-directory metadata, current
  internal-volume eligibility, and off-main enumeration.
- UI-host tests cover domain-item grid application, loading results, empty state,
  provisional window configuration, startup success/failure, and status menu.
- Unsigned Release build succeeds for arm64 + x86_64 with macOS 15.0 minimum.
- `git diff --check` and prohibited-pattern scan pass before commit.

## Remaining Exit Gate

Automated Slice 2 behavior is complete. Per project UI policy, actual desktop
layering, visible content, dragging, resizing, and scrolling remain manual and
are not reported as passed. The window strategy remains replaceable until the
Spike 0.1 matrix is executed.
