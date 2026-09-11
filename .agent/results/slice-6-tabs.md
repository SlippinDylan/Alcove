# Slice 6 — Tabs Result

- Added AppKit TabBar with ordered folder titles, selected state, close buttons,
  add button, accessibility labels, and stable full-ID action targets.
- One PortalViewController/grid is reused; switching captures and restores each
  tab's runtime selection and scroll origin.
- Select/add/close mutations save domain state before updating the window.
- Added folders pass the same async fixed-internal-local validator and retry on error.
- Closing the last tab requires confirmation; confirm atomically removes the
  Portal and closes its window, cancel changes nothing.
- Concurrent tab mutations are suppressed; tab drag/reorder is absent.
- AlcoveCore: 34 tests, 0 failures. Hosted app: 46 tests, 0 failures.
- Manual TabBar/picker/confirmation interaction remains unverified.
