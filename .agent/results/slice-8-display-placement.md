# Slice 8 — Display Placement Persistence Result

Production portals now persist a v2 `PlacementRecord` keyed by canonical display
UUID. Legacy v1 frames migrate using largest visible-frame intersection or the
explicit primary display, after a write-once `portals.v1.json.bak` is preserved.

Only application-tracked titlebar drag mouse-up and live-resize end events commit
user placement. Screen changes, wake, Spaces/Stage Manager frame notifications,
and topology directives remain transient. Missing home displays evict to primary
without changing durable state and restore when the home identity returns.

All durable mutations use one cancellable FIFO task chain. Interleaving tests cover
creation, placement, topology, cancellation, pending-frame generations, save
failure, and termination flush without stale aggregate overwrite.

Automated verification completed on 2026-09-12:

- AlcoveCore: 110 tests, 0 failures.
- Hosted Alcove tests: 88 tests, 0 failures.
- Swift 6 strict concurrency and warnings-as-errors compilation passed.
- Unsigned Release app built for arm64 and x86_64 with minimum macOS 15.0.
- Independent review found no remaining Critical, High, or Medium correctness issue.
- Xcode project plist validation and `git diff --check` passed.

Real display disconnect/reconnect, rearrangement, scaling, sleep/wake, Spaces,
Stage Manager, and desktop-window positioning remain manual hardware/system gates.
