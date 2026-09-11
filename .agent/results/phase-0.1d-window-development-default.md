# Phase 0.1D — Window Development Default

- Selected a provisional, replaceable development default: key-eligible
  `NSWindow`, `desktopIconWindow + 1`, `canJoinAllSpaces`, `stationary`, and
  `ignoresCycle`.
- The default enables production scaffolding but is not reported as a final
  WindowServer behavior decision.
- Main-thread verification reran `spikes/desktop-window/test.sh`: 140 assertions,
  0 failures under Swift 6 warnings-as-errors.
- The complete manual 12-variant system-transition matrix remains required for
  full Spike 0.1 and MVP completion.
- Formal signing remains deferred and does not affect this decision.
