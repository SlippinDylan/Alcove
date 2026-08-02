# Alcove Session Handoff

**Updated:** 2026-08-02

**Repository:** `/Users/dylanwang/Repo/Products/Apps/Alcove`

**Current phase:** Phase 0 technical spikes are active. Phases 0.1A–0.1C produced an independently verified desktop-window comparison harness; its manual matrix remains unexecuted. Phases 0.2A–0.2C provide geometry, inventory/notification adapters, and an eviction-safe pure state machine; the display hardware matrix remains. Phase 0.3A provides a reviewed Quick Look responder bootstrap and non-visual system-panel integration evidence. Phase 0.4A provides reviewed Glass, visual-effect fallback, and opaque accessibility construction paths. Phases 0.5A/0.5B provide reviewed observer candidates, 0.5C1 provides reviewed background enumeration/stale/cancellation evidence, 0.5C2 provides a local observation/resource/teardown comparison, and 0.5C3 records local symlink/missing/moved/replacement path evidence; access, removable/network media, dropped-event recovery, and load remain open. Human GUI behavior and a macOS 15 runtime remain unverified. No production Alcove module has started.

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

Phase 0.5C3 added the disposable path-transition comparison harness:

- Runs missing-root, symlink-root, child-symlink, root-rename, and pathname-replacement scenarios for both reviewed candidates in isolated subprocesses.
- Arms a distinct evidence token immediately before every mutation; FSEvents marker steps require canonical path/flag evidence, while DispatchSource is recorded honestly as directory-level invalidation within an isolated window.
- Matches concrete missing-root error cases and errno, proves initial/moved/replacement identities independently, and uses throwing bounded teardown plus transactional cleanup.
- Passes 238 strict Codable/real-filesystem assertions in three consecutive runs, including typed runtime timeout, probe-owned cleanup, FSEvents marker-path identity, and outer-watchdog evidence.
- Locally, DispatchSource remained attached to the moved original inode; the FSEvents `WatchRoot` candidate reported the replacement pathname after `RootChanged`. Optional non-delivery results remain bounded local facts only.
- Builds an arm64, minimum-macOS-15.0, SDK-26.5, system-framework/Swift-runtime-only, linker-ad-hoc-signed probe.

MiMo created the initial buildable harness, but its second event window could never signal, move events were misattributed to later markers, missing-root errno was fabricated from strings, teardown failures were swallowed, and selective tests still reported 128/128. Codex replaced the evidence orchestration, error/lifecycle handling, identity proof, tests, and documentation.

Phase 0.5C3 does not select an observer or implement recovery policy. TCC, removable/network media, actual macOS 15, dropped/revoke recovery, multiple observers, and sustained load remain open. Full Spike 0.5 remains incomplete.

### Earlier Phase 0.5C2 resource and teardown comparison

Phase 0.5C2 added the disposable observer comparison harness:

- Runs the existing DispatchSource and FSEvents candidates in separate private-TMPDIR processes at 500, 1,000, and 5,000 pre-existing items.
- Measures latency from the unique marker mutation, requires marker-path evidence for FSEvents, and keeps directory invalidation, item-record, and callback-batch counts semantically separate.
- Treats marker, event timeout, teardown, resource, and cleanup failures as fatal; adds bounded descriptor settling and a matrix-level TERM/KILL watchdog.
- Passes 97 Swift 6 warning-as-error assertions in three consecutive runs, including real FSEvents timeout cleanup and outer-watchdog paths.
- The final 18-process matrix produced exactly three valid samples for every combination, empty stderr, zero FSEvents bridge failures, and local descriptor-baseline return in all samples.
- Builds an arm64, minimum-macOS-15.0, SDK-26.5, system-framework/Swift-runtime-only, linker-ad-hoc-signed probe.

MiMo created the initial buildable harness, but its original latency origin, event causality, callback semantics, polling lifetime, failure handling, matrix validation, and descriptor-baseline narrative were not acceptable. Codex corrected the implementation and replaced the invalid evidence. MiMo's original metrics are superseded.

Phase 0.5C2 does not select an observer and does not test recovery. Dropped/revoke recovery, TCC, removable media, networks, actual macOS 15, and long-running load remain open. Full Spike 0.5 remains incomplete.

### Earlier Phase 0.5C1 background enumeration

Phase 0.5C1 added the disposable background enumeration harness:

- Runs immediate-child FileManager enumeration through a bounded concurrent worker and a typed request runner, never on MainActor.
- Checks cancellation before scheduling, before filesystem work, and after the synchronous call without claiming mid-call interruption.
- Uses checked generations and rejects actual out-of-order stale results; maps validation/enumeration/timeout/cancellation/generation errors.
- Passes 67 Swift 6 warning-as-error assertions in three consecutive runs, including real stale ordering, deterministic cancellation handshakes, timeout-with-continuing-work, deterministic sorting, real error mapping, recovery, and injected cleanup failure.
- Builds an arm64, minimum-macOS-15.0, SDK-26.5, system-runtime-only, linker-ad-hoc-signed probe; an isolated three-child probe exited 0.

MiMo created the initial structure, but its serial worker made the required stale ordering impossible; the test waited for a 10-second timeout, discarded the real result, rebuilt a synthetic snapshot on MainActor, and still reported success. It also used unbounded waits and self-proving cancellation/cleanup tests. Codex replaced the orchestration and evidence. An independent Reviewer confirmed the original result was invalid; all listed defects were addressed before final verification.

Phase 0.5C1 does not select an observer. Recovery, TCC, removable media, symlinks, networks, actual macOS 15, and sustained-load evidence remain open. Full Spike 0.5 remains incomplete.

### Earlier Phase 0.5B FSEvents candidate

Phase 0.5B added the disposable FSEvents observation candidate:

- Uses `FileEvents`, `WatchRoot`, and `UseCFTypes` with a provisional 0.3-second latency, checked CFArray bridging, immutable registration identity/generation, and uptime timestamps.
- Uses explicit `idle/running/stopping/stopped` state; callback-safe `stop()` only initiates queued teardown, while `waitUntilStopped` provides a real bounded completion boundary.
- Owns the stream and callback context through a registration and single-consume context lease; teardown runs Stop, Invalidate, Release, context release, final state, and completion after active callbacks return.
- Passes 69 explicit Swift 6 warning-as-error assertions in three consecutive runs. Fixtures cover typed open/path failures, item create/rename/delete flags, root changes, old-inode-negative/new-path-positive replacement, one-batch rapid operations, callback-stop mutation suppression, real teardown timeout, bridge failures, context lifetime, deinit, and transactional cleanup.
- Builds an arm64, minimum-macOS-15.0, SDK-26.5, system-framework-only, linker-ad-hoc-signed probe. A bounded create/delete probe observed a real coalesced item event and exited cleanly.

MiMo created the initial harness shape, but Codex rejected its prematurely published stopped state, fake timeout wait, inline C-callback resource release, unsafe callback bridge, weak replacement proof, and overstated ownership/coalescing documentation. Codex replaced the lifecycle core and strengthened the tests. A second independent Reviewer found no remaining High/Critical code issue; Codex then added post-callback-stop mutation and zero-bridge-failure assertions before final verification.

This is candidate-B evidence only. Neither FSEvents nor DispatchSource is selected. Phase 0.5C comparison, explicit background enumeration/stale-result/cancellation evidence, TCC-protected folders, removable media/ejection, actual macOS 15, symlinks, network volumes, resources, and long-running behavior remain open. Full Spike 0.5 remains incomplete.

### Earlier Phase 0.5A DispatchSource candidate

Phase 0.5A added the disposable DispatchSource observation candidate:

- Opens one directory with `O_EVTONLY | O_CLOEXEC`, validates the actual descriptor with `fstat`, and records device/inode identity.
- Uses an atomic start transaction, immutable callback, registration identity, independent fixed-FD cancellation owner, reentrant stop initiation, bounded teardown wait, and typed POSIX/teardown errors.
- Treats directory events as invalidation signals rather than inventing child paths.
- Passes 45 explicit Swift 6 warning-as-error assertions in three consecutive runs using isolated real temporary-directory mutations, including separate child create/rename/delete `.write` delivery, observed-directory rename/delete flags, inode-controlled replacement behavior, callback-stop and external-stop concurrency, post-teardown suppression, explicit/deinit FD closure, EBADF, and transactional cleanup.
- Builds an arm64, minimum-macOS-15.0, SDK-26.5, system/Swift-runtime-only, linker-ad-hoc-signed probe. Repeated bounded probes observed one or two `.write` callbacks for the same spaced create/delete operations and exited with descriptor teardown confirmed.

MiMo created the initial adapter/harness shape, but Codex rejected its weak-self FD teardown, start/stop race, callback deadlock, shared queue key, unsynchronized callback/group state, wall-clock/reversed latency, swallowed cleanup, and self-proving replacement/post-stop tests. Codex rebuilt the lifecycle and test evidence before independent verification.

This is candidate-A evidence only. DispatchSource is not selected. FSEvents, TCC-protected folders, removable media/ejection, an actual macOS 15 runtime, symlinks, network volumes, resource/load measurements, long-running behavior, and explicit background enumeration/cancellation evidence remain open. Full Spike 0.5 remains incomplete.

### Earlier Phase 0.4A material boundary

Phase 0.4A added the disposable material compatibility boundary:

- Builds equivalent representative chrome through automatic macOS 26 Glass, forced `NSVisualEffectView`, and Reduce Transparency opaque paths.
- Uses one `NSGlassEffectContainerView` with two real `NSGlassEffectView` descendants while keeping the file-content canvas outside every effect.
- Observes accessibility changes on the SDK-required `NSWorkspace.shared.notificationCenter`, rejects callbacks queued before stop, and owns the block observer through an explicit RAII token.
- Preserves candidate material and window-level intent across close/recreate without implementing tab state.
- Passes 72 explicit Swift 6 warning-as-error assertions in three consecutive runs, including real workspace notification delivery, hierarchy, constraints, resolver, stale-event, and ownership checks.
- Builds an arm64, minimum-macOS-15.0, SDK-26.5, system-framework-only, ad-hoc-signed app that launches and quits through an Apple event.

MiMo created the initial model and harness shape, but Codex rejected its container-without-Glass construction, hard-coded initial Glass path, wrong notification center, queued-task race, discarded recreation state, out-of-scope tab state, forbidden unavailable initializers, fake passes, and inflated 8115-assertion report. Codex corrected the implementation and replaced the tests before independent clean verification.

This is structural and lifecycle evidence, not pixel evidence. Glass/fallback appearance, actual macOS 15 runtime behavior, light/dark appearance, Reduce Transparency, Increase Contrast, readability, hit testing, resizing, desktop-level appearance, wallpaper variation, and multiple displays remain `NR`. Full Spike 0.4 remains incomplete.

### Earlier Phase 0.3A Quick Look bootstrap

Phase 0.3A added the disposable Quick Look responder bootstrap:

- Hosts read-only temporary fixtures in a multiple-selection `NSCollectionView` with visible diagnostics and an actual Space-handling first responder.
- Inserts one main-actor Quick Look responder between the portal window and `NSApplication`.
- Uses typed panel APIs and identity-aware cleanup for QuickLookUI's Objective-C `assign` data-source/delegate references.
- Supports the normal and `desktopIconWindow + 1` candidate levels without selecting a production strategy.
- Passes 40 Swift 6 warning-as-error assertions from a LaunchServices-hosted test app, including real key-window, shared-panel controller discovery, system begin/end ownership, selection refresh, safe bounds, and cleanup checks.
- Builds an arm64, minimum-macOS-15.0, system-framework-only, ad-hoc-signed app that launches and quits through an Apple event.

MiMo created the initial harness structure, but Codex rejected its unsafe actor/KVC workarounds, incorrect Space responder, incomplete `assign` reference teardown, swallowed fixture errors, and self-proving lifecycle tests. Codex retained the bounded harness concept, corrected the implementation and evidence, then independently ran clean tests, artifact inspection, launch, and normal quit.

Automated controller discovery does not prove preview rendering or human interaction. Single/multiple preview behavior, carousel navigation, focus handoff, candidate desktop level, repeated cleanup/reopen, and common content types remain `NR`. Full Spike 0.3 remains incomplete.

### Earlier Phase 0.2C eviction state

Phase 0.2C added the UI-free eviction state machine:

- Separates durable user-confirmed placement/home from active, temporarily displaced, and awaiting presentation state.
- Makes user interaction end the only durable write path; system moves and topology reconciliation preserve every saved record.
- Centers and constrains temporary primary-screen fallback, defers when no screen is available, and restores remembered home when it returns.
- Prevents a historical non-home display from stealing placement.
- Treats an explicit user move on fallback as selecting a new home, while retaining the old record.
- Passes 102 total clean Swift 6 warning-as-error tests, including 22 state-machine cases.

This is pure automated evidence. Real disconnect/reconnect, resolution/scaling, rearrangement, ordering, notification coverage, and sleep/wake remain manual and unverified. Full Spike 0.2 remains incomplete.

### Earlier Phase 0.2B inventory bootstrap

Phase 0.2B added a disposable AppKit-backed display inventory and notification probe:

- Captures current `NSScreen.screens` index, name, exact display ID result, UUID result, frame, visible frame, scale, and main-screen state on MainActor.
- Converts `CGDisplayCreateUUIDFromDisplayID` under the Core Foundation Create rule without forced bridging or ownership leaks.
- Uses synchronous, idempotent notification registration and removal, with background posts handed to a MainActor snapshot handler.
- Provides bounded `snapshot` and `observe --seconds` commands with decodable, sorted-key JSON.
- Passes 80 XCTest cases from clean Swift 6 warning-as-error builds; standalone snapshot and 0.2-second observe probes exit 0 and decode as JSON.
- Produces an arm64 diagnostic executable with minimum macOS 15.0, SDK 26.5, system frameworks only, and an ad-hoc signature.

The current session contained three screens and one main screen; all frames were positive/finite and all three UUID calls returned canonical strings. Values are not recorded because one snapshot does not establish stable identity. The unchanged bounded observation captured zero events and proves only normal bounded exit.

MiMo produced the initial module structure but its test suite recursively launched `swift build` inside `swift test`, deadlocking the package lock. Codex stopped the failed invocation, removed the recursive test, replaced the leaking observer lifecycle, tightened display-ID and CLI validation, removed unsafe test constructs, and independently rebuilt and ran the probes. Full Spike 0.2 remains incomplete.

### Earlier Phase 0.2A placement geometry

Phase 0.2A added a disposable, UI-free Swift package for placement geometry:

- Captures absolute frame, save-time visible frame, preferred size, and movable-range-normalized anchor.
- Restores with the required order: constrain size, choose absolute or normalized origin, snap, then clamp.
- Rejects non-finite anchor, frame, saved-record, preferred-size, and grid inputs with explicit errors.
- Uses an explicit nearest-away-from-zero grid rounding rule and handles negative display origins and zero movable ranges.
- Passes 51 XCTest cases from clean Swift 6 builds with warnings treated as errors and a real macOS 15.0 test-binary deployment target.

Phase 0.2A alone does not enumerate screens, claim UUID stability, observe topology notifications, or implement eviction state. Phase 0.2B provides the adapters and Phase 0.2C provides pure eviction state, while real-hardware evidence remains outstanding. Full Spike 0.2 remains in progress.

### Earlier Phase 0.1C window-class harness

Phase 0.1C added an independently switchable window-class dimension without selecting a production class:

- Added typed `NSWindow` and `NSPanel` candidates, both supporting eligible and ineligible `canBecomeKey` construction.
- Kept the six Phase 0.1B strategy presets orthogonal to class selection and preserved both selections across close/recreate.
- Applied one shared style/configuration path and documented two explicit experimental panel properties.
- Extended diagnostics to separate configured class from actual runtime type and actual main/key capability/state.
- Passed 140 Swift 6 strict-concurrency assertions after Codex corrected factory/diagnostics proxy tests and removed a style-mask confounder.
- Independently rebuilt, inspected, launched, and normally quit the final app.

Phase 0.1C is complete as an automated comparison-harness work unit. Neither `NSWindow` nor `NSPanel` is selected. Full Spike 0.1 still requires the manual system-transition matrix and an evidence-backed decision.

The complete 12-variant procedure is prepared in `docs/SPIKE_DESKTOP_WINDOW_MANUAL_MATRIX.md`. Every result remains `NR`; authoring the procedure is not evidence that any GUI or system behavior passed.

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
- Phases 0.2A–0.2C together pass 102 tests from clean Swift 6 warning-as-error builds; the probe has minimum macOS 15.0 and emits independently decoded JSON.
- Phase 0.3A passes 40 Swift 6 warning-as-error assertions, including a real shared-panel responder discovery and ownership lifecycle integration; its app has minimum macOS 15.0 and launches/quits normally.
- Phase 0.4A passes 72 explicit Swift 6 warning-as-error assertions in three consecutive runs; the app contains real Glass/fallback/opaque construction paths, has minimum macOS 15.0, and launches/quits normally.
- Phase 0.5A passes 45 real-filesystem Swift 6 warning-as-error assertions in three consecutive runs; its DispatchSource probe has minimum macOS 15.0 and independently confirmed descriptor teardown.
- Phase 0.5B passes 69 real-filesystem Swift 6 warning-as-error assertions in three consecutive runs; its FSEvents probe has minimum macOS 15.0 and independently confirmed bounded teardown.
- Phase 0.5C1 passes 67 Swift 6 warning-as-error assertions in three consecutive runs; its background enumeration probe has minimum macOS 15.0 and its stale/cancellation tests use real request results.
- Phase 0.5C2 passes 97 Swift 6 warning-as-error assertions in three consecutive runs; its validated 18-process local matrix records causal event latency, count semantics, bounded teardown, process resources, and descriptor settling without selecting an observer.
- Phase 0.5C3 passes 238 Swift 6 warning-as-error assertions in three consecutive runs; its tokenized local matrix separates root transitions, moved-inode markers, and replacement-path markers without selecting an observer or policy.
- `git diff --check` passes before each commit.

Do not modify or delete `ChatGPT-macOS 小组件与文件夹管理.md` unless the user explicitly requests it. Do not delete `.DS_Store` unless explicitly asked.

## 7. Next Plan

The immediate next work is:

1. Continue automated Phase 0.5 evidence for accessible TCC-path diagnostics, sustained load/multiple observers, and explicit dropped/revoke recovery; do not select either observer before the remaining gates.
2. Manually verify material appearance on macOS 26 and an actual macOS 15 runtime, including accessibility settings and desktop-candidate level.
3. Manually verify Quick Look rendering, carousel navigation, dismissal/focus behavior, desktop-candidate level behavior, and cleanup/reopen.
4. Complete Spike 0.2's hardware matrix; geometry, inventory/UUID/notification bootstrap, and eviction-safe pure state are complete.
5. Continue every independent automated part of Spikes 0.3–0.5 while manual Phase 0 evidence remains outstanding.
6. Update the candidate architecture only from recorded spike evidence and lock it only after the product-and-architecture gate resolves.
7. Implement the ten Phase 1 vertical slices only after their documented entry gates pass.
8. Run Spike 0.6 independently before the first public release.

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
