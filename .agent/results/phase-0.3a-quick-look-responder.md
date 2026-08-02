# Phase 0.3A — Quick Look Responder Bootstrap Result

## Agent Input and Scope

MiMo reported reading `~/.codex/AGENTS.md`, `HANDOFF.md`, the four baseline documents, `docs/SPIKE_DESKTOP_WINDOW.md`, and the desktop-window spike sources. It reported the repository-level agent file absent. It created only the allowed Phase 0.3A paths and made no commit.

Created files:

- six Swift app sources under `spikes/quick-look/Sources/`;
- `spikes/quick-look/Tests/main.swift`;
- `spikes/quick-look/build.sh` and `test.sh`;
- `docs/SPIKE_QUICK_LOOK.md`;
- this result report.

The deterministic `swiftc` harness is appropriate for a disposable spike and does not create a production Alcove module.

## MiMo Result Before Review

MiMo returned exit code 0 and reported 88 passing assertions. Codex rejected that result as an acceptance signal because the implementation used prohibited `nonisolated(unsafe)`, `@preconcurrency`, KVC, swallowed cleanup errors, and test `try!`; Space handling was attached to the wrong responder; panel `assign` references were not safely torn down; and several lifecycle tests only changed test-only flags. The original report also overstated those tests and treated unsafe workarounds as acceptable.

## Codex Review and Repairs

Codex retained the harness concept but corrected the implementation:

- merged Quick Look behavior into one main-actor `NSResponder`;
- replaced unchecked state and KVC with typed panel APIs and narrow runtime main-actor bridges;
- made panel reference release identity-aware and teardown-safe;
- cached a deterministic selection snapshot, reloaded controlled state, and guarded invalid indexes;
- moved Space handling into the actual collection-view first responder;
- established and tested the responder's path to `NSApplication`;
- added visible selection/window-level diagnostics and both required level controls;
- replaced fixture value ownership with a transactional directory owner and explicit cleanup errors;
- replaced unsafe, self-proving tests with a LaunchServices-hosted integration test app;
- corrected all automated/manual evidence claims.

## Exact Final Verification

```bash
cd spikes/quick-look && bash test.sh
# Exit 0: source policy pass; 40 assertions passed, 0 failed

cd spikes/quick-look && bash build.sh
# Exit 0: Swift 6 strict concurrency; warnings as errors

file build/AlcoveQLSpike.app/Contents/MacOS/AlcoveQLSpike
xcrun vtool -show-build build/AlcoveQLSpike.app/Contents/MacOS/AlcoveQLSpike
otool -L build/AlcoveQLSpike.app/Contents/MacOS/AlcoveQLSpike
plutil -p build/AlcoveQLSpike.app/Contents/Info.plist
codesign -dv --verbose=2 build/AlcoveQLSpike.app
# arm64; min macOS 15.0; SDK 26.5; system dependencies; ad-hoc signature

open -n build/AlcoveQLSpike.app
osascript -e 'tell application id "com.alcove.spike.quick-look" to quit'
# Process found running; normal Apple-event quit confirmed
```

Automated integration used a real key window and shared `QLPreviewPanel`. It verified responder discovery, typed data-source/delegate assignment and release, selection refresh, presentation-state observation, and idempotent teardown. It did not visually inspect rendered content or treat asynchronous dismissal visibility as an automated pass.

## Manual Tests Not Executed

All remain `NR`: human Space interaction; single-preview rendering; multiple carousel; second-Space and Escape dismissal; selection changes while visibly open; normal and desktop-candidate behavior; key/focus handoff; text/image/PDF/movie rendering; deactivate/reactivate; portal close while visible; cleanup/reopen.

## Remaining Uncertainty

1. Quick Look rendering and carousel behavior at `desktopIconWindow + 1`.
2. Focus return and repeated user-driven panel ownership transitions.
3. Behavior across the remaining viable key-window policies and window classes.

## Scope and Gate

The final workspace remains within the delegated allowlist before project-status updates. No production module or third-party dependency was added. Full Spike 0.3 is incomplete; Phase 0.3A provides only a reviewed bootstrap and non-visual integration evidence.
