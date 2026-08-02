# Alcove Session Handoff

**Updated:** 2026-08-02

**Repository:** `/Users/dylanwang/Repo/Products/Apps/Alcove`

**Current phase:** Phase 0 technical spikes are active. Phases 0.1A–0.1C produced an independently verified desktop-window strategy and class-comparison harness. Full Spike 0.1 remains in progress because its real system-transition matrix is unexecuted. No production Alcove module has started.

## 1. What We Are Building

Alcove is a native macOS menu-bar app that creates movable, resizable desktop folder portals. Each portal displays the direct children of a user-selected local folder in a native icon grid, supports multiple folder tabs, and can coexist with other portals across multiple displays.

Alcove is not WidgetKit, a Finder extension, a Finder replacement, or a full file manager. Its MVP is read-only.

### Product interaction contract

- Single-click selects one item.
- Command-click toggles an item in the selection.
- Shift-click extends selection from the anchor.
- Arrow keys move focus; Shift+arrow extends selection; Command-A selects all.
- Double-clicking a file opens it with its default application.
- Double-clicking a folder opens it in Finder; Alcove does not navigate into it.
- Command-O and Command-Down open the selection.
- Space presents Quick Look when selection is non-empty.
- Return is a no-op because Finder reserves it for rename and Alcove MVP has no rename.
- Runtime selection is independent per tab.

### Tab scope

MVP includes:

- Multiple tabs per portal.
- Add, switch, and close tab.
- Persist tab creation order and the selected tab.
- Prompt to remove the portal when the user closes its last tab; never silently destroy it.

Tab drag-to-reorder is Post-MVP. Do not reintroduce it into MVP slices, requirements, tests, or architecture.

### MVP boundaries

MVP includes portal creation, multiple portals, multiple tabs, icon grids, selection, opening, Quick Look, active-directory observation, local persistence, multi-display placement recovery, menu-bar management, accessibility, and macOS 15/26 visual compatibility.

MVP excludes rename, delete/trash, new folders, copy, move, drag-in, drag-out, in-portal directory navigation, cloud-provider status, telemetry, and network access.

## 2. Platform and Confirmed Design Direction

- Minimum deployment target: macOS 15.
- Build SDK and primary design target: macOS 26.
- Native AppKit app using `NSApplicationDelegate`, `NSStatusItem`, an evidence-selected `NSWindow` or `NSPanel` strategy, and `NSCollectionView`.
- Non-sandboxed `LSUIElement` menu-bar app with no Dock icon.
- Universal arm64 + x86_64 binary.
- macOS 26 design uses public Liquid Glass APIs where semantically appropriate.
- macOS 15–25 requires a deliberate `NSVisualEffectView` compatibility path.
- Glass belongs on chrome, navigation, tab, and control groups, not every file cell or the file-content canvas.

Local Xcode 26.6 / macOS 26.5 SDK headers confirmed:

- `NSGlassEffectView`: `contentView`, `cornerRadius`, `tintColor`, `style`.
- `NSGlassEffectContainerView`: `contentView`, `spacing`.
- Neither has `isInteractive` or `state`; standard controls provide interaction.

The visual behavior of both the macOS 26 and macOS 15 paths at Alcove's selected desktop window level is still provisional until Spike 0.4.

## 3. What Task Was Just Completed

Phase 0.1C added an independently switchable window-class dimension without selecting a production class:

- Added typed `NSWindow` and `NSPanel` candidates, both supporting eligible and ineligible `canBecomeKey` construction.
- Kept the six Phase 0.1B strategy presets orthogonal to class selection and preserved both selections across close/recreate.
- Applied one shared style/configuration path and documented two explicit experimental panel properties.
- Extended diagnostics to separate configured class from actual runtime type and actual main/key capability/state.
- Passed 140 Swift 6 strict-concurrency assertions after Codex corrected factory/diagnostics proxy tests and removed a style-mask confounder.
- Independently rebuilt, inspected, launched, and normally quit the final app.

Phase 0.1C is complete as an automated comparison-harness work unit. Neither `NSWindow` nor `NSPanel` is selected. Full Spike 0.1 still requires the manual system-transition matrix and an evidence-backed decision.

### Earlier Phase 0.1B strategy model

Phase 0.1B expanded the disposable `NSWindow` harness without selecting a production strategy:

- Added six focused presets covering stationary, move-to-active-Space, full-screen auxiliary, all-Spaces membership, and key eligibility.
- Replaced unchecked collection flag combinations with typed Space behavior and stable preset identifiers.
- Added a configurable `NSWindow.canBecomeKey` subclass and diagnostics that separate configured intent from actual state.
- Added Swift 6 strict-concurrency builds with warnings treated as errors and 66 structural assertions.
- Preserved selected strategy across close/recreate and cleared controller ownership for both menu and titlebar close paths.
- Independently rebuilt, inspected, launched, and normally quit the app after Codex review fixes.

Phase 0.1B is complete as an automated strategy-model work unit. It did not validate Spaces or system-transition behavior, resolve full Spike 0.1, select a production window strategy, or begin production implementation.

### Earlier Phase 0.1A bootstrap

Phase 0.1A validated the bounded Claude Code + Xiaomi MiMo implementation workflow and bootstrapped the disposable desktop-window harness:

- Added a `swiftc`-built AppKit experiment under `spikes/desktop-window/`.
- Added Normal Baseline and the initial Desktop Candidate strategy.
- Added live window/screen diagnostics and real delegate/notification logging.
- Added menu actions for strategy switching, activation, close, recreation, and quit.
- Added `docs/SPIKE_DESKTOP_WINDOW.md` with all GUI/system behavior left explicitly unverified.
- Independently cleaned, rebuilt, inspected, launched, and normally quit the generated app.
- Corrected the runtime window-type diagnostic, app-activation ordering, and inconsistent report wording during Codex review.

Phase 0.1A is complete as a bootstrap and capability validation. It did not resolve Spike 0.1, select a production window strategy, or begin production implementation.

## 4. Candidate Architecture Baseline

The intended responsibility boundaries remain useful but are provisional where they depend on spike results:

- `AlcoveCore`: UI-free domain values, selection state, and pure grid/placement math.
- `AlcoveApp`: application entry, status item, portal coordinator, and creation overlay.
- `PortalWindowing`: evidence-selected desktop window class, level, collection behavior, move/resize lifecycle, and key-window policy.
- `PortalPresentation`: portal chrome, tabs, material compatibility, and states.
- `FileGrid`: one reusable `NSCollectionView` controller per portal; tab switching replaces its model and restores per-tab runtime state.
- `FolderAccess`: explicit-background enumeration and Spike 0.5-selected observation mechanism.
- `QuickLookIntegration`: `QLPreviewPanel` ownership and responder integration selected from Spike 0.3 evidence.
- `DisplayPlacement`: display identity, geometry restoration, and user-versus-system movement state machine.
- `Persistence`: versioned Codable DTOs, domain mapping, and atomic storage.

Dependencies should remain acyclic. Domain aggregates must not become `Codable` merely to simplify storage; persistence DTOs own the JSON schema.

### Window strategy is not locked

The first Spike 0.1 candidate is:

```
desktopIconWindow + 1
canJoinAllSpaces
stationary
ignoresCycle
```

It is not the production configuration. The disposable experiment harness must compare public-API combinations including:

- `.stationary`
- `.moveToActiveSpace`
- `.fullScreenAuxiliary`
- Use or omission of `.canJoinAllSpaces`
- `NSWindow` versus `NSPanel`
- Whether the portal may become key

The final strategy comes from measured Show Desktop, Spaces, full-screen, Stage Manager, focus, lock, and sleep/wake behavior.

### Folder loading and observation

- Never run blocking directory enumeration on `MainActor`.
- `FolderLoadingActor` coordinates state; it is not proof that synchronous I/O runs on a background thread.
- Blocking file work requires an explicit, tested background execution boundary.
- Generation tokens reject stale results regardless of whether underlying synchronous I/O completes after cancellation.
- Fine-grained cancellation requires incremental or batched enumeration with cancellation checks.
- A one-shot `FileManager.contentsOfDirectory` call cannot be interrupted midway.
- The active tab only is observed; inactive tabs reload when activated.
- DispatchSource and FSEvents remain candidates until Spike 0.5 measures event coverage, teardown, directory replacement, removable volumes, TCC behavior, overhead, and latency.

### Persistence

State is intended to live at:

`~/Library/Application Support/Alcove/portals.json`

Use a versioned, human-readable JSON envelope, separate DTOs, validated domain mapping, temporary writes, and atomic replacement. Implement only data currently needed by each vertical slice. Do not build a fake v1-to-v2 migration or generic migration framework before a real second schema exists.

Do not add Core Data, SQLite, portal state in UserDefaults, App Groups, Keychain, helpers, XPC, or security-scoped bookmarks without a demonstrated requirement.

### Multi-display placement formula

For each user-confirmed move or resize, the candidate record contains:

- Display UUID.
- Absolute frame in points.
- Save-time `visibleFrame`.
- Preferred portal size.
- Normalized anchor within the actual movable range.
- Last display on which the user explicitly placed the portal.

Save or geometry-change restoration must use:

```
movableWidth = max(0, visibleFrame.width - windowFrame.width)
movableHeight = max(0, visibleFrame.height - windowFrame.height)

nx = movableWidth > 0
    ? (windowFrame.minX - visibleFrame.minX) / movableWidth
    : 0

ny = movableHeight > 0
    ? (windowFrame.minY - visibleFrame.minY) / movableHeight
    : 0
```

Restore with the size already constrained to the current `visibleFrame`:

```
x = visibleFrame.minX + clamp(nx, 0...1) * movableWidth
y = visibleFrame.minY + clamp(ny, 0...1) * movableHeight
```

Operation order is mandatory: constrain size, compute movable range, restore origin, grid-snap, then clamp. If display geometry is unchanged, prefer the saved absolute frame. If geometry changed, use the normalized anchor and preferred size.

Temporary system eviction to another display must never overwrite the user's remembered home placement.

## 5. Current Gate Status and What Is Blocked

The production architecture cannot be locked until Spikes 0.1–0.5 are resolved. Phase 0 is now active, but full Spike 0.1 still lacks its strategy matrix and manual system-transition evidence.

The harness now covers `.stationary`, `.moveToActiveSpace`, `.fullScreenAuxiliary`, optional `.canJoinAllSpaces`, key-window eligibility, and independently switchable `NSWindow`/`NSPanel` candidates. GUI evidence requiring Show Desktop, Spaces, Mission Control, Stage Manager, full-screen, lock, or sleep/wake remains a manual gate rather than an automated pass.

### Product-and-architecture gate

The following must be resolved before architecture lock and dependent production slices:

1. **Spike 0.1 — Desktop window behavior**
   - Compare window class, level, collection behaviors, and key-window policy.
   - Test Show Desktop, Spaces, full-screen, Stage Manager, lock, and sleep/wake.
2. **Spike 0.2 — Display identity and placement**
   - Measure display UUID stability.
   - Validate absolute-frame versus movable-range-normalized restoration.
   - Verify temporary eviction does not overwrite home placement.
3. **Spike 0.3 — Quick Look**
   - Validate responder ownership, key-window interaction, presentation, dismissal, and cleanup.
4. **Spike 0.4 — Liquid Glass and fallback**
   - Validate macOS 26 glass and macOS 15 `NSVisualEffectView` at the selected window level.
5. **Spike 0.5 — Folder observation and permissions**
   - Compare DispatchSource and FSEvents.
   - Validate TCC, missing directories, removable volumes, symlinks, enumeration execution, and cancellation granularity.

A spike does not need to pass. It must be resolved with recorded evidence and an explicit architecture or product-scope decision. Never relabel a failed gate as successful by naming an untested fallback.

### Separate release gate

**Spike 0.6 — Apple Development/ad-hoc DMG and Gatekeeper** may run in parallel with Phase 1 and must not block MVP feature work. It must finish before the first public GitHub Release.

It must inspect actual artifacts and record:

- Signing identity and embedded provisioning profile, if any.
- Seven-day expiry behavior after actual expiry.
- Gatekeeper and `spctl` behavior.
- Quarantine and right-click Open behavior.
- Whether and when `xattr` is needed.
- DMG installation and launch behavior on available macOS 15 and 26 systems.

Until this is resolved, Apple Development signing is a provisional self-hosted distribution hypothesis, not a validated final-user distribution solution.

## 6. Repository State and Validation

The repository contains the documentation baseline and a disposable Phase 0.1 AppKit harness. It still has no production Xcode project, production Swift package, test target, workflow, app icon, CI artifact, or release DMG.

The initial local Git baseline includes:

- Product, research, candidate architecture, delivery, handoff, and historical-intent documents.
- The Phase 0.1A source harness and deterministic build script.
- Agent task specifications and concise result reports; full `.agent/logs/` remain ignored.
- `.gitignore` rules for build products, DerivedData, SwiftPM state, Xcode user state, local configuration, credentials, runtime logs, and project-local memory.

The literal handoff filename is `HANDOFF.md`; the earlier `HANDOFFmd` text was a typo.

The current baseline verification includes:

- FR-01 through FR-18 are unique and continuous.
- AC-01 through AC-17 are unique and continuous.
- SP-01 through SP-08 are unique and continuous.
- Slice 1 through Slice 10 headings and cross-references are consistent.
- Old fixed-window, fixed-DispatchSource, tab-reorder-in-MVP, actor-as-background-thread, mid-call-cancellation, full-screen-normalization, and single-six-spike-gate wording was searched and removed.
- Phase 0.1A builds with minimum macOS 15.0 using Xcode 26.6 / SDK 26.5.
- The generated app passes Info.plist, dependency, and ad-hoc signature inspection.
- The generated app launches and exits through a normal Quit event.
- Phase 0.1B passes 66 strategy/window/lifecycle assertions and both app/test targets compile in Swift 6 strict-concurrency mode with warnings treated as errors.
- Phase 0.1B independently launches and exits normally after Codex review corrected conflicting Space semantics, MainActor isolation, non-key ordering, and close ownership.
- Phase 0.1C passes 140 strategy/class/window/lifecycle assertions; actual factory output and diagnostics text are tested for both concrete classes.
- Phase 0.1C independently launches and exits normally after artifact, deployment-target, dependency, and ad-hoc signature inspection.
- `git diff --check` passes before each commit.

Do not modify or delete `ChatGPT-macOS 小组件与文件夹管理.md` unless the user explicitly requests it. Do not delete `.DS_Store` unless explicitly asked.

## 7. Next Plan

The immediate next work is:

1. Record a reproducible manual matrix for all required desktop/system transitions; do not call unexecuted cells passes.
2. Continue every independent automated part of Spikes 0.2–0.5 while manual Spike 0.1 evidence remains outstanding.
3. Update the candidate architecture only from recorded spike evidence and lock it only after the product-and-architecture gate resolves.
4. Implement the ten Phase 1 vertical slices only after their documented entry gates pass.
5. Run Spike 0.6 independently before the first public release.

Do not resurrect the old infrastructure-first sequence. The first user-visible value after App Shell is a minimal single Portal, not a complete persistence/migration/display foundation.

## 8. Pitfalls That Must Never Be Repeated

### Do not turn candidates into facts

- Do not call `desktopIconWindow + 1` plus `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle` the final configuration.
- Do not test only one window strategy.
- Do not assume `NSWindow` instead of `NSPanel`, or assume the portal can or cannot become key.
- Do not claim `CGDisplayCreateUUIDFromDisplayID` is stable through every reconnect.
- Do not claim `NSScreen.visibleFrame` guarantees notch-safe placement.
- Do not turn a reference-project observation or architecture inference into an Apple-confirmed fact.
- Do not hide a failed spike behind an unverified fallback.

### Do not hallucinate Apple APIs

- `QLPreviewPanel.shared().toggle(nil)` is not valid.
- Present with the shared panel and evidence-backed ownership/data source/delegate lifecycle; candidate calls are `makeKeyAndOrderFront(nil)` and `orderOut(nil)`, still subject to Spike 0.3.
- Do not invent `NSGlassEffectView.isInteractive`, `state`, or any property absent from inspected SDK headers.
- Do not claim GUI Quick Look, Spaces, Stage Manager, or desktop-window behavior is proven by ordinary headless XCTest.

### Do not repeat concurrency mistakes

- An actor is an isolation and coordination boundary, not a guarantee that blocking synchronous I/O runs on a separate thread.
- Never enumerate folders on `MainActor`.
- Never claim `FileManager.contentsOfDirectory` can be cancelled in the middle of the synchronous call.
- Always reject stale generations.
- If fine-grained cancellation is required, design incremental or batched enumeration and test its actual boundaries.
- Do not preselect DispatchSource or FSEvents before Spike 0.5.

### Do not corrupt placement logic

- Do not divide position by the full screen width or height.
- Normalize within `visibleFrame - constrainedWindowSize`.
- Constrain size before computing movable range.
- Grid-snap before the final clamp.
- Prefer absolute frame when display geometry is unchanged.
- Preserve save-time `referenceVisibleFrame` and preferred size.
- Never let a system-driven move overwrite remembered home placement.

### Do not overbuild infrastructure

- Do not build a complete migration chain before a real second schema exists.
- Do not make domain aggregates `Codable`; persistence DTOs own the schema.
- Do not use unrelated UUIDs for file selection identity; use `FileIdentity`.
- Keep one reusable grid controller per portal.
- Do not add Core Data, SQLite, App Groups, Keychain, helpers, XPC, sandboxing, telemetry, or network access without a demonstrated requirement.

### Do not expand the MVP

- No tab drag-to-reorder in MVP.
- No rename, delete, trash, new folder, copy, move, drag-in, drag-out, or in-portal navigation.
- Do not read private Finder preferences for icon size; Alcove owns Small/Medium/Large presets.

### Do not misrepresent signing or testing

- Apple Development signing is for development/testing, not official customer distribution.
- Do not assume an embedded seven-day provisioning profile; inspect the built artifact.
- Do not call `spctl` rejection successful trust.
- Do not silently switch a selected release workflow to ad-hoc signing.
- Do not state that right-click Open or `xattr` is universally required until Spike 0.6 measures it.
- macOS 15 has no macOS simulator. Runtime testing needs real hardware, a VM, self-hosted runner, or another confirmed launch-capable environment.
- Unavailable compatibility cells are `unverified risk`, not passes.

### Do not blindly copy references or delegated output

- TileTop stores per-display absolute frames; Alcove's movable-range-normalized scheme is our candidate design, not a TileTop feature.
- Pocket Finder is GPL-3.0. Do not copy its code or derivative expressive implementation.
- No TileTop or Pocket Finder code has been copied.
- Complex, cross-file, Apple-API-sensitive Alcove work stays with Codex. Any delegated small task requires explicit acceptance criteria, full diff review, and independent verification.

## 9. Source of Truth Order for a New Session

Read in this order:

1. Current repository/global `AGENTS.md` instructions supplied by the user/session.
2. `.engramory-memory/MEMORY.md`, then only relevant linked detail files.
3. This `HANDOFF.md`.
4. `docs/PRODUCT_REQUIREMENTS.md` for product scope and interaction contract.
5. `docs/RESEARCH.md` for evidence classification.
6. `docs/ARCHITECTURE.md` for the provisional candidate architecture.
7. `docs/DELIVERY_PLAN.md` for gates and execution order.
8. `README.md` for the short public overview.
9. `ChatGPT-macOS 小组件与文件夹管理.md` for historical intent only; do not overwrite it.

If a remembered API, version, runner label, signing behavior, path, or external fact conflicts with the repository or current environment, verify it again before acting.
