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
- [x] Replaceable key-eligible `NSWindow` desktop development default recorded; not a final manual-gate decision.
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

- [x] Minimal collection host and responder ownership implemented.
- [x] Data-source/delegate lifecycle checks complete with real shared-panel controller discovery.
- [ ] Single- and multi-item presentation/dismissal manually recorded.
- [ ] Quick Look integration decision recorded.

### Spike 0.4 — Liquid Glass and Fallback

- [x] macOS 26 Liquid Glass chrome path implemented and built with real Glass descendants.
- [x] macOS 15–25 `NSVisualEffectView` fallback implemented and built; actual macOS 15 runtime remains unverified.
- [ ] Accessibility material responses manually recorded on available OS versions.
- [ ] Material boundary decision recorded.

### Spike 0.5 — Folder Observation and Permissions

- [x] DispatchSource adapter and automated fixture checks complete.
- [x] FSEvents adapter and automated fixture checks complete.
- [x] Observation coverage, teardown, latency, and resource comparison recorded.
- [x] Explicit background enumeration, stale-result, and truthful cancellation tests complete.
- [x] Multiple-observer, 1,001-file load, and 25-cycle lifecycle evidence recorded locally.
- [x] Local protected-path access and owned-fixture missing/not-directory/permission error metadata recorded.
- [x] Folder-source policy accepts only internal fixed local storage and rejects removable, ejectable, and network-volume locations.
- [x] FSEvents selected as the sole observer with ordinary-refresh and fail-closed rebuild policy.
- [x] Local missing-root, root/child-symlink, rename, replacement, and child-symlink enumeration evidence complete.
- [ ] Controlled TCC behavior and production recovery orchestration recorded.

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

- [ ] Slice 1 — App Shell and Menu Bar: production project, universal build, and host tests complete; manual menu-bar/Dock/Quit checks remain.
- [ ] Slice 2 — Minimal Single Portal: Core, FolderAccess, portal/grid, 28 automated tests, and universal build complete; manual desktop/window/scroll checks remain.
- [ ] Slice 3 — Selection and Opening: 8 Core selection tests and hosted input/opening tests complete; manual pointer/keyboard/NSWorkspace checks remain.
- [ ] Slice 4 — Portal Creation Flow: geometry, overlay, picker, validation transaction, menu action, and 28 hosted tests complete; manual UI flow remains.
- [ ] Slice 5 — Minimal Persistence: v1 DTO/store, atomic failure preservation, startup restore, and frame writeback complete; manual relaunch remains.
- [ ] Slice 6 — Tabs: ordered UI, add/select/close persistence, last-tab confirmation, and runtime state restoration complete; manual interaction remains.
- [ ] Slice 7 — Quick Look: production responder, ordered selection, ownership cleanup, 56 hosted tests, and universal build complete; real panel behavior remains manual.
- [ ] Slice 8 — Display Placement Persistence: production v2 migration, user-only commits, topology/wake recovery, 110 Core tests, 88 hosted tests, and universal build complete; physical hardware matrix remains.
- [ ] Slice 9 — Directory Observation and Auto-Refresh.
- [ ] Slice 10 — Hardening, Accessibility, and Release Preparation.

## MVP Acceptance

- [ ] AC-01 through AC-06 — creation, grid, interaction, opening, Quick Look, and tabs.
- [ ] AC-07 through AC-10 — persistence, display restoration, Spaces, and Stage Manager.
- [ ] AC-11 through AC-13 — macOS 15/26 materials and folder refresh.
- [ ] AC-14 through AC-17 — read-only boundary, menu-bar behavior, universal build, and supported folder locations.
- [ ] AC-18 — selected release artifact installation and launch procedure verified.

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
- 2026-08-02: Phase 0.3A passed 40 Swift 6 warning-as-error assertions plus clean artifact inspection, process launch, and Apple-event quit after Codex replaced MiMo's unsafe actor/KVC workarounds, incorrect Space responder, incomplete panel teardown, and self-proving lifecycle tests.
- 2026-08-02: Phase 0.4A passed 72 explicit Swift 6 warning-as-error assertions in three consecutive runs plus clean artifact/launch/quit checks after Codex replaced MiMo's missing Glass descendants, wrong workspace notification center, stale observer tasks, fake passes, and inflated assertion report.
- 2026-08-02: Phase 0.5A passed 45 real-filesystem Swift 6 warning-as-error assertions in three consecutive runs plus probe/artifact/error-path checks after Codex replaced MiMo's racy FD lifecycle, callback deadlocks, wall-clock latency, and self-proving replacement/post-stop tests.
- 2026-08-02: Phase 0.5B passed 69 real-filesystem Swift 6 warning-as-error assertions in three consecutive runs plus probe/artifact/error-path checks after Codex replaced MiMo's premature stop state, fake timeout wait, inline C-callback teardown, unsafe bridge, and weak replacement evidence; a second Reviewer found no remaining High/Critical code issue.
- 2026-08-02: Phase 0.5C1 passed 67 Swift 6 warning-as-error assertions in three consecutive runs plus isolated probe/artifact/error-path checks after Codex replaced MiMo's serial stale-test deadlock, synthetic result, unbounded wait, test-only cancellation, and self-proving cleanup evidence.
- 2026-08-02: Phase 0.5C2 passed 97 Swift 6 warning-as-error assertions in three consecutive runs and a strict 18-process local matrix after Codex corrected MiMo's latency origin, event causality, callback semantics, unbounded polling, failure handling, and invalid descriptor narrative; no observer was selected.
- 2026-08-02: Phase 0.5C3 passed 238 strict real-filesystem assertions in three consecutive runs after Codex replaced MiMo's dead second window, move/marker conflation, fabricated missing-root error, swallowed teardown, and selective JSON tests; no observer or recovery policy was selected.
- 2026-08-02: Phase 0.5C4 passed 371 strict real-filesystem assertions in three consecutive final runs after MiMo exited 0 with no task output and Codex implemented the harness; independent review found and Codex fixed scenario-cardinality and subprocess-pipe/failure-convergence gaps. Eight standalone scenarios, timeout/error paths, and artifact inspection passed; no observer was selected.
- 2026-08-02: Phase 0.5C5 passed 124 strict assertions in three consecutive final runs after Codex replaced MiMo's fabricated NSError metadata, non-fatal cleanup/restoration, main-thread fixture I/O, disconnected generation, false SIGKILL, unbounded waits, and self-proving tests. Local Desktop/Documents/Downloads access succeeded, owned fixtures preserved raw Cocoa/underlying metadata plus independent POSIX evidence, and final independent review found no Critical/High/Medium issue; controlled TCC denial remains open.
- 2026-09-11: Production Slice 1 added the Swift 6 AppKit LSUIElement shell. Three host tests passed and the unsigned Release app built as universal arm64/x86_64 with minimum macOS 15.0; manual menu-bar, Dock, and Quit checks remain.
- 2026-09-11: Production Slice 2 added AlcoveCore, async FolderAccess, fixed-internal folder validation, the provisional desktop NSWindow, native icon grid, and loading/empty/error states. Nine package tests and 19 hosted tests pass; manual desktop-layer and interaction checks remain.
- 2026-09-11: Production Slice 3 added Finder-style selection, keyboard navigation, and injected workspace opening. Seventeen Core tests and 22 hosted tests pass; real desktop focus and NSWorkspace behavior remain manual.
- 2026-09-11: Production Slice 4 enabled New Portal and added constrained grid-snapped overlay geometry, async folder choice, fail-closed location validation, cancellation/retry, and concurrent-session suppression. Twenty-six Core tests and 28 hosted tests pass; visible creation remains manual.
- 2026-09-11: Production Slice 5 added a validated non-Codable Portal aggregate, readable v1 DTOs, atomic PortalStore, startup restoration, and serialized frame persistence. Thirty-four Core tests and 38 hosted tests pass; manual relaunch remains.
- 2026-09-11: Production Slice 6 added ordered multi-tab UI, validated addition, persisted selection/closure, final-tab Portal confirmation, and per-tab runtime state. Thirty-four Core tests and 46 hosted tests pass; manual TabBar interaction remains.
- 2026-09-11: Production Slice 7 added ordered single/multi-selection Quick Look, explicit shared-panel ownership, second-Space dismissal, tab-switch invalidation, takeover-safe updates, synchronous window-close cleanup, and reversible responder-chain installation. Thirty-four Core tests and 56 hosted tests pass; real panel rendering/navigation/focus behavior remains manual.
- 2026-09-11: Production Slice 8A migrated the verified placement geometry and eviction-safe reducer into AlcoveCore with 51 geometry and 22 state tests. AlcoveCore passes 107 tests, hosted tests pass 56/56, and Release remains universal; no persistent schema changed.
- 2026-09-12: Production Slice 8 completed canonical display identity, v2 placement migration with write-once backup, explicit user drag/resize commits, screen/wake reconciliation, durable mutation serialization, pending-placement retry, and termination flush. AlcoveCore passes 110 tests and the hosted app passes 88; physical display behavior remains manual.
