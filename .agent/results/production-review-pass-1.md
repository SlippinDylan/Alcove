# Production Review Pass 1 Result — Module Audit

## Confirmed Defects Fixed

- Creation geometry could snap a minimum/mixed-direction rectangle away from
  both gesture points. Direction-aware outward snapping now guarantees the
  returned visible frame covers the clamped drag.
- Production folder enumeration only noticed cancellation after completing all
  child metadata. A synchronized cancellation flag now stops at real per-item
  boundaries; the batch `contentsOfDirectory` call remains inherently atomic.
- Quick Look wrote shared panel state without first proving it was
  `currentController`. Presentation now asks the panel to update its responder
  controller and mutates state only after Apple grants control.
- Clearing selection could leave a stale Quick Look panel; empty selection now
  dismisses and returns controller ownership, while a normal Space toggle keeps
  valid hidden-panel control for reopening.
- Closing and showing a Portal again detached Quick Look permanently. `present`
  now reinstalls the responder only when needed.
- Failed `NSWorkspace.open` calls were silent. A standard accessible alert now
  displays the failed path through an injected/tested presentation boundary.
- The portal-creation overlay lacked a keyboard/accessibility completion path.
  Return and the accessibility press action now choose a valid centered default
  frame; Escape still cancels and pointer dragging remains available.
- Startup persistence failure was retained internally but invisible and left
  creation permanently blocked. Startup now explains that saved data was not
  changed and offers Retry or Quit without overwriting the state file.

## Reviewed and Rejected Finding

A reported restore-time external-volume bypass was traced through the complete
production chain and rejected: restored tabs start empty, then
`viewDidAppear → observation start → FolderLocationValidator → identity → stream
install → load`. Validation failure displays recovery before observation or
enumeration. Keeping the invalid durable mapping is necessary for Locate Folder.

## Verification

- AlcoveCore: 110 tests passed.
- Hosted app: 122 tests passed.
- Unsigned Release build: universal `arm64` and `x86_64`, minimum macOS 15.0.
- Independent review of the resulting diff found no new Critical, High, or
  Medium issue.
