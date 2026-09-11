Status: Provisional — production development default; manual Spike 0.1 gate remains open

# Desktop Window Development Default

## Decision

Production development may begin with a replaceable window strategy using:

- `NSWindow`;
- `CGWindowLevelForKey(.desktopIconWindow) + 1`;
- `[.canJoinAllSpaces, .stationary, .ignoresCycle]`;
- key-window eligibility enabled.

Keyboard selection and Quick Look require a key-eligible window, so a non-key
candidate is not a useful development default. `NSWindow` is preferred over
`NSPanel` until the panel-specific runtime behavior has manual evidence.

## Evidence Boundary

The current Swift 6 test harness passes 140 assertions and proves that both
window classes and all strategy variants are constructed and configured as
declared. It does not prove WindowServer behavior.

This default therefore does not close Spike 0.1. Before MVP completion, the
manual matrix must still verify desktop-icon/normal-window ordering, actual key
focus, dragging, resizing, Spaces, Show Desktop, Mission Control, Stage Manager,
full-screen apps, lock, sleep/wake, and multi-display Spaces.

The production window configuration must remain isolated behind one internal
strategy value so evidence can change it without touching persistence or domain
models.
