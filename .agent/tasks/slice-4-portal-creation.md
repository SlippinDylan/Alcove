# Slice 4 — Portal Creation Flow

## Goal

Enable New Portal and implement the transactional overlay-drag, folder-choice,
eligibility-validation, and portal-commit flow.

## Scope

- Select the screen containing the pointer and display a transparent key overlay.
- Escape or a click without dragging cancels.
- Constrain and grid-snap the dragged frame inside `visibleFrame`, with a 2×2 minimum.
- Present a directory-only NSOpenPanel asynchronously.
- Retry folder choice after a classified validation failure without losing the frame.
- Commit a Portal only after fixed-internal-local validation succeeds.
- Suppress concurrent creation sessions; allow later sequential creations.

## Verification

- Pure geometry tests for directions, bounds, negative origins, snapping, and invalid input.
- Hosted transaction tests for success, cancellation, retry, sequential and duplicate requests.
- Menu action and NSOpenPanel configuration tests.
- Swift 6 warnings-as-errors and universal Release build.
