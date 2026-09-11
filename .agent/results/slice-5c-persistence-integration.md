# Slice 5C — Persistence Integration Result

- AppDelegate restores persisted portals before optional development startup creation.
- PortalCoordinator owns ordered domain state and windows keyed by PortalID.
- Creation validates folder location, waits prior persistence, saves the new
  aggregate list, then allocates and presents the window.
- Stored portals restore in array order through an injected window factory.
- Window move/end-resize updates validated domain frame and serializes snapshots;
  failures remain in `persistenceError`.
- Store boundary now rejects duplicate Portal IDs and non-absolute folder paths.
- AlcoveCore: 34 tests, 0 failures. Hosted app: 38 tests, 0 failures.
- Save-failure tests prove no domain state or window is committed partially.
- Manual relaunch and real window movement remain unverified.
