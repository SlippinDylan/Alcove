# Alcove Autopilot Progress

Updated: 2026-08-02

This checklist mirrors `docs/DELIVERY_PLAN.md`. A checked item means its required automated verification and documentation are complete. Manual-only evidence remains unchecked until it is actually observed.

## Repository Baseline

- [x] Requirements, research, candidate architecture, delivery plan, README, and HANDOFF reviewed.
- [x] Palmos `.gitignore` and macOS/Xcode/Swift build layout inspected read-only.
- [x] Alcove `.gitignore` covers local memory, logs, build products, user state, local configuration, and credentials.
- [x] Initial local baseline commit created.

## Phase 0 — Technical Spikes

### Spike 0.1 — Desktop Window Behavior

- [x] Phase 0.1A disposable AppKit harness created, built, inspected, launched, and quit.
- [x] Phase 0.1B `NSWindow` strategy model and switchable combinations complete.
- [x] Phase 0.1C `NSWindow`/`NSPanel` and key-window lifecycle comparison complete.
- [x] Reproducible 12-variant manual system-transition protocol prepared with every result `NR`.
- [ ] Finder icon and normal-window layer ordering manually recorded.
- [ ] Spaces, Show Desktop, and Mission Control manually recorded.
- [ ] Stage Manager and full-screen behavior manually recorded.
- [ ] Lock/unlock and sleep/wake behavior manually recorded.
- [ ] Evidence-backed window class, level, collection behavior, and key policy selected.

### Spike 0.2 — Display Identity and Placement

- [x] Display inventory, UUID diagnostics, bounded notification probe, and lifecycle tests implemented.
- [x] Pure movable-range placement model and automated tests complete.
- [ ] Resolution/scaling and screen-order behavior recorded on available hardware.
- [ ] Real display disconnect/reconnect and rearrangement manually recorded.
- [x] Eviction-safe pure-state semantics and automated decision recorded; hardware evidence remains open.

### Spike 0.3 — Quick Look Responder Chain

- [ ] Minimal collection host and responder ownership implemented.
- [ ] Data-source/delegate lifecycle checks complete.
- [ ] Single- and multi-item presentation/dismissal manually recorded.
- [ ] Quick Look integration decision recorded.

### Spike 0.4 — Liquid Glass and Fallback

- [ ] macOS 26 Liquid Glass chrome path implemented and built.
- [ ] macOS 15–25 `NSVisualEffectView` fallback implemented and built.
- [ ] Accessibility material responses manually recorded on available OS versions.
- [ ] Material boundary decision recorded.

### Spike 0.5 — Folder Observation and Permissions

- [ ] DispatchSource adapter and automated fixture checks complete.
- [ ] FSEvents adapter and automated fixture checks complete.
- [ ] Observation coverage, teardown, latency, and resource comparison recorded.
- [ ] Explicit background enumeration and stale-result tests complete.
- [ ] TCC, missing folder, removable volume, and symlink behavior recorded where available.
- [ ] Observation strategy decision recorded.

### Product-and-Architecture Gate

- [ ] Spikes 0.1–0.5 resolved with evidence or explicit scope decisions.
- [ ] `docs/ARCHITECTURE.md` updated and locked from spike evidence.

### Spike 0.6 — Release Gate

- [ ] Ad-hoc artifact, DMG, quarantine, and Gatekeeper checks complete.
- [ ] Apple Development artifact inspected when credentials are available.
- [ ] Seven-day expiry behavior observed after the required wait period.
- [ ] macOS 15/26 installation matrix recorded.
- [ ] Release signing and installation decision recorded.

## Phase 1 — Vertical Slices

- [ ] Slice 1 — App Shell and Menu Bar.
- [ ] Slice 2 — Minimal Single Portal.
- [ ] Slice 3 — Selection and Opening.
- [ ] Slice 4 — Portal Creation Flow.
- [ ] Slice 5 — Minimal Persistence.
- [ ] Slice 6 — Tabs.
- [ ] Slice 7 — Quick Look.
- [ ] Slice 8 — Display Placement Persistence.
- [ ] Slice 9 — Directory Observation and Auto-Refresh.
- [ ] Slice 10 — Hardening, Accessibility, and Release Preparation.

## MVP Acceptance

- [ ] AC-01 through AC-06 — creation, grid, interaction, opening, Quick Look, and tabs.
- [ ] AC-07 through AC-10 — persistence, display restoration, Spaces, and Stage Manager.
- [ ] AC-11 through AC-13 — macOS 15/26 materials and folder refresh.
- [ ] AC-14 through AC-16 — read-only boundary, menu-bar behavior, and universal build.
- [ ] AC-17 — selected release artifact installation and launch procedure verified.

## Execution Log

- 2026-08-02: Phase 0.1A independently rebuilt with Xcode 26.6 / SDK 26.5, minimum macOS 15.0; app launch and normal quit passed.
- 2026-08-02: Long-running unattended development mode started; `.gitignore` prepared for the initial baseline commit.
- 2026-08-02: Created local baseline commit `efecc73`; no push performed.
- 2026-08-02: Phase 0.1B passed 66 Swift 6 strict-concurrency assertions, clean app build, artifact inspection, launch, and normal quit after Codex review fixes.
- 2026-08-02: Phase 0.1C passed 140 Swift 6 strict-concurrency assertions, clean app build, artifact inspection, launch, and normal quit after Codex corrected proxy tests and a style-mask confounder.
- 2026-08-02: Prepared the full Phase 0.1 manual protocol; no manual matrix cell was executed or marked passed.
- 2026-08-02: Phase 0.2A passed 51 clean Swift 6 warning-as-error geometry tests after Codex added saved-record validation and corrected rounding semantics.
- 2026-08-02: Phase 0.2B passed 80 clean Swift 6 warning-as-error tests and standalone JSON probe checks after Codex replaced MiMo's recursive-build deadlock and leaking observer lifecycle.
- 2026-08-02: Phase 0.2C passed 102 clean Swift 6 warning-as-error tests; system eviction preserves home records, empty topology defers, and only explicit user moves change home.
