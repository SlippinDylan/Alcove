# Slice 3 — Selection and Opening Result

## Implemented

- AlcoveCore `SelectionState` with selected IDs, anchor, focus, inclusive ranges,
  select all, clear, and stale-item reconciliation.
- Custom NSCollectionView input boundary for pointer modifiers and Finder keyboard commands.
- Plain click, Command toggle, Shift range, four-direction focus, Shift extension,
  and Command-A.
- Double-click, Command-O, and Command-Down through injected `WorkspaceOpening`.
- Return and keypad Enter are explicit no-ops; no mutation action exists.
- Failed workspace opens are retained as explicit URLs instead of being swallowed.

## Verification

- AlcoveCore: 17 tests, 0 failures (8 selection tests plus prior Core coverage).
- Hosted app suite: 22 tests, 0 failures on macOS 26.6.2 arm64.
- Tests cover forward/backward ranges, anchor/focus invariants, stale reconciliation,
  click modifiers, arrow movement/extension, key-code mapping, opening order, and failure retention.
- Swift 6 complete strict concurrency and warnings-as-errors pass.
- Universal unsigned Release build passed for arm64 + x86_64 before commit.

## Remaining Exit Gate

Automated selection and workspace-adapter behavior are complete. Real pointer,
keyboard, Finder/file opening, and desktop-window focus remain manual checks and
are not reported as passed.
