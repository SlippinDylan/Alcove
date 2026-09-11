# Production Review Pass 2 Result — State and Failure Audit

## Confirmed Defects Fixed

- One global `tabTask` allowed an open folder picker in Portal A to silently
  discard selection/close requests from Portal B. Folder selection remains
  globally single-owner because `NSOpenPanel` is shared, while ordinary tab
  mutations can now start independently and still serialize through the durable
  FIFO.
- Icon-size layout reload could leave AppKit selection visuals/accessibility out
  of sync with the durable `SelectionState`. Selection is now replayed after
  reload.
- Keyboard up/down navigation requested horizontal scrolling in a vertically
  scrolling grid. Horizontal and vertical commands now request the corresponding
  nearest edge.
- Startup restore Retry now has a direct regression proving a transient failure
  performs a second restore without overwriting data or terminating the app.

## Verification

- AlcoveCore: 110 tests passed.
- Hosted app: 124 tests passed.
- Unsigned Release: universal `arm64` and `x86_64`, minimum macOS 15.0.
- Coverage-enabled hosted run completed before the fixes to route review toward
  unexercised system adapters and failure branches.
- Independent fix re-review found no Critical, High, or Medium issue.
