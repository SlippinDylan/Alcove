# Slice 4 — Portal Creation Flow Result

## Implemented

- Enabled the New Portal status-menu command through an injected creation requester.
- Transparent per-screen overlay with pointer-screen selection, dashed live frame,
  Escape/click cancellation, and mouse drag completion.
- Pure finite creation geometry constrained to visibleFrame, grid-snapped in all
  drag directions, and sized to at least two grid columns/rows when the display permits.
- Async directory-only NSOpenPanel configured for a single resolved folder.
- One-session creation state machine; cancellation leaves no Portal, duplicate
  begins are ignored, and sequential requests can create multiple Portals.
- Folder validation completes off MainActor before a window is allocated; errors
  are presented and folder selection retries with the original frame.

## Verification

- AlcoveCore: 26 tests, 0 failures, including 9 creation-geometry tests.
- Hosted app suite: 28 tests, 0 failures on macOS 26.6.2 arm64.
- Creation tests cover success, frame cancel, picker cancel, unsupported retry,
  sequential portals, duplicate begin suppression, menu action, and panel policy.
- Source policy scan and `git diff --check` pass.
- Universal unsigned Release build passed for arm64 + x86_64 before commit.

## Remaining Exit Gate

The creation transaction and geometry are automated. Per UI policy, the visible
overlay, real pointer drag, Escape, NSOpenPanel, error alert, and multiple live
windows remain manual checks and are not reported as passed.
