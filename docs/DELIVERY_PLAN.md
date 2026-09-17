# Delivery Plan — Alcove

## Phase 0: Technical Spikes

Spikes are time-boxed investigations that produce **evidence, not production code**. The six work packages below cover the eight prototype evidence cases (`SP-01` through `SP-08`) tracked in `RESEARCH.md`. Spikes may create disposable prototype harnesses; they produce evidence and are not production implementation. A spike may fail; resolution requires a recorded result and an explicit architecture or product-scope decision, not a forced pass or an unverified fallback.

There are two independent gates:

- **Product-and-architecture gate:** Spikes 0.1–0.5 must be resolved before the production architecture is locked or dependent production slices begin.
- **Release gate:** Spike 0.6 may run in parallel with Phase 1. It does not block App Shell, Portal, or other MVP feature development, but it must be resolved before the first public GitHub Release. Until then, free Apple Development signing is a provisional distribution hypothesis, not a confirmed end-user distribution solution.

The disposable harnesses and per-spike reports were removed after their production decisions and automated coverage moved into `ARCHITECTURE.md`, `RESEARCH.md`, and the maintained test suites. This document retains the historical work packages and the manual release checks that still apply.

### Spike 0.1 — Desktop Window Behavior

**Question:** Which public AppKit window strategy, if any, reliably provides Alcove's desktop-layer behavior across Show Desktop, Spaces, full-screen apps, and Stage Manager without permanent eviction?

**Approach:**
- Build a disposable AppKit experiment harness whose window class, level, collection behaviors, and key-window eligibility can be switched at runtime or launch.
- Use `desktopIconWindow + 1`, `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle` only as the first candidate configuration.
- Compare `.stationary`, `.moveToActiveSpace`, `.fullScreenAuxiliary`, use or omission of `.canJoinAllSpaces`, `NSWindow` versus `NSPanel`, and whether the portal is allowed to become key.
- Test manually: trigger Show Desktop (F11 / trackpad gesture), switch Spaces, enter/exit Stage Manager, sleep/wake, lock screen.
- Record each strategy's level relative to Finder icons and normal windows, focus/keyboard behavior, animation, position, visibility, and recovery after every transition.

**Exit Gate:**
- [ ] Document the compared combinations and select the evidence-backed `NSWindow.Level`, `NSWindow.CollectionBehavior`, window class, key-window policy, and any supplementary properties.
- [ ] If no strategy meets the product requirement, record the failure and make an explicit product-feasibility or scope decision; do not mask it with an untested workaround.

---

### Spike 0.2 — Display Identity and Placement

**Question:** Can we identify remembered display layouts via `CGDisplayCreateUUIDFromDisplayID` while always presenting the complete runtime layout on the current menu-bar primary display?

**Approach:**
- On a multi-display setup, enumerate `NSScreen.screens` and record each screen's `CGDisplayCreateUUIDFromDisplayID(displayID)` (stability through disconnect/reconnect is inference, not guaranteed) alongside its `frame` and `visibleFrame`.
- Disconnect and reconnect the external display; verify the UUID is stable.
- Change resolution and scaling; verify UUID stability.
- Rearrange displays in System Settings; verify UUID stability.
- Test sleep/wake with external display connected and disconnected.
- Test `NSScreen.screens` ordering stability across these events.
- Validate the normalized anchor against the actual movable range: constrain preferred size to `visibleFrame`, compute `max(0, visibleFrame dimension - window dimension)`, then normalize or restore the origin within that range.

**Exit Gate:**
- [ ] Record observed UUID stability across disconnect/reconnect, resolution change, and rearrangement; retain the limitation that Apple does not document this as a universal guarantee.
- [ ] Document the `NotificationCenter` notifications to observe for display topology changes (e.g., `NSApplication.didChangeScreenParametersNotification`).
- [ ] Define the placement scheme: store absolute frame, save-time `visibleFrame`, preferred size, and normalized anchor within the actual movable range. Same geometry prefers the absolute frame; changed geometry constrains size, computes movable range, restores the anchor, grid-snaps, then clamps.

---

### Spike 0.3 — Quick Look Responder Chain

**Question:** Can `QLPreviewPanel` be presented from a custom `NSWindow` hosting an `NSCollectionView`, with the responder chain correctly wired, and does it work when the window is at desktop-icon level?

**Approach:**
- Create a minimal `NSCollectionView` host using the leading viable window strategies from Spike 0.1, including their key-window policies.
- Implement `QLPreviewPanelDataSource` and `QLPreviewPanelDelegate` on the window controller or a responder subclass.
- Wire `nextResponder` correctly so `QLPreviewPanel.sharedPanel` can find the data source.
- Test: select an item, press Space → panel should appear. Press Space again → dismiss.
- Test with multiple items selected.
- Test with the candidate desktop-level strategies specifically; responder behavior may differ by level, window class, and key eligibility.

**Exit Gate:**
- [ ] `QLPreviewPanel` presents and dismisses correctly from the desktop-level window.
- [ ] Multi-item Quick Look works (carousel navigation).
- [ ] Document any responder-chain wiring requirements.

---

### Spike 0.4 — Portal Background and Accessibility

**Question:** Which background remains visually stable for a desktop-level Portal across Spaces while Reduce Transparency switches cleanly to an opaque accessibility surface?

**Approach:**
- Compare `NSGlassEffectView`, behind-window `NSVisualEffectView`, and a plain static translucent surface at the selected desktop window level and `.canJoinAllSpaces` behavior.
- With Reduce Transparency enabled: create the same layout using an explicitly opaque AppKit surface.
- Verify both approaches respect `Reduce Transparency` in Accessibility settings.
- Measure the material behavior at the leading window strategies from Spike 0.1 rather than assuming one fixed level.
- Confirm the selected production surface uses no WindowServer backdrop sampling.

**Exit Gate:**
- [x] Space-transition evidence rejects both dynamic backdrop surfaces and selects static translucency.
- [x] The opaque accessibility surface preserves the same layout and ownership boundaries.
- [x] Static translucency and the opaque accessibility surface respect Reduce Transparency.
- [x] The macOS 26 minimum target uses one production surface without runtime availability branches.

---

### Spike 0.5 — Folder Observation and Permissions

**Question:** What is the most reliable, low-overhead mechanism to observe eligible internal-local folder changes, and what happens when the mapped folder is TCC-protected or missing?

**Approach:**
- Compare `DispatchSourceFileSystemObject` (kqueue) vs. `FSEvents` for observing a directory's immediate children.
- For `DispatchSource`: open the directory file descriptor, create a source, verify it fires on file add/remove/rename.
- For `FSEvents`: create a stream for the directory, verify it fires for child changes.
- Measure CPU and memory overhead for each approach on a folder with 500, 1000, and 5000 items.
- Test TCC: attempt to enumerate `~/Desktop`, `~/Documents`, `~/Downloads` without Full Disk Access. Document the error behavior.
- Test missing folder: delete or move the mapped folder; document what error the enumeration returns.
- Test folder-source eligibility: accept internal fixed local storage and reject removable, ejectable, and network-volume metadata before tab creation or re-mapping.
- Test symbolic links: map a folder containing symlinks; verify enumeration returns the links, not targets.

**Exit Gate:**
- [x] Select FSEvents as the primary observation mechanism with a documented recovery contract.
- [ ] Document TCC error handling: what `NSError` domain/code to catch, and how to present it to the user.
- [x] Document missing-folder handling and unsupported folder-location rejection.
- [x] Confirm blocking enumeration crosses an explicit background execution boundary. Record cancellation granularity accurately: incremental/batched enumeration may check cancellation at boundaries, while a one-shot `FileManager.contentsOfDirectory` call cannot be interrupted midway.

---

### Spike 0.6 — Apple Development DMG Launch Behavior

**Question:** What is the actual user experience when installing and launching the selected free Apple Development-signed artifact across macOS 26 and 27?

**Scheduling:** This release-gate spike may run in parallel with Phase 1 and does not block product implementation. It must be resolved before the first public GitHub Release.

**Approach:**
- Build a minimal arm64 test app, sign with the free Apple Development identity, and package it as a drag-to-Applications DMG.
- On macOS 26 and 27: mount DMG, drag to Applications, attempt to launch.
- Document every Gatekeeper dialog, quarantine warning, and `xattr` removal step required.
- Inspect the signature, embedded provisioning profile if present, and certificate lifetime.
- Test: does the 7-day profile expiry actually kill the app silently, or does it show a dialog?
- Test: does `sudo xattr -rd com.apple.quarantine /Applications/Alcove.app` reliably remove quarantine?
- Test: does right-click → Open bypass the warning on both macOS versions?

**Exit Gate:**
- [ ] Document the exact installation and first-launch UX for the selected signing method.
- [ ] Document the quarantine removal steps to include in README/DMG.
- [ ] Spike 0.6 must inspect the built artifact and launch after expiry to confirm the 7-day expiry behavior (dialog vs. silent kill). Do not assert Alcove's non-sandboxed manually signed build necessarily embeds a Personal Team provisioning profile until inspected.
- [x] Select Apple Development signing for CI releases; do not fall back automatically.

---

## Phase 1: Vertical Slices to MVP

Each slice produces a runnable, observable increment and adds only the domain or infrastructure required by that increment. Recorded, replaceable development defaults may unblock implementation while manual Phase 0 gates continue; unresolved gates still block the affected MVP acceptance criteria and architecture from being called final. Spike 0.6 may continue in parallel and blocks only the first public GitHub Release.

### Slice 1 — App Shell and Menu Bar

**Goal:** Launchable LSUIElement app with a menu-bar icon, disabled "New Portal" item, and "Quit"; no portal window yet.

**Entry Gate:** The production module boundaries and replaceable development defaults are recorded. Phase 0.1D supplies the provisional window default; unresolved manual system behavior remains an MVP exit gate rather than a blocker for the app shell. Spike 0.6 is not an entry requirement.

**Deliverables:**
- Xcode project with an Apple Silicon (`arm64`) distribution target.
- `Info.plist` with `LSUIElement = true`.
- `NSStatusItem` with Alcove icon.
- Menu with disabled "New Portal", separator, and "Quit".
- App lifecycle: launch, show menu-bar icon, quit.

**Tests:**
- Unit: app delegate registers the status item and expected menu commands.
- Build: deployment target macOS 26 with the selected macOS SDK for arm64.
- Manual: app launches, menu-bar icon appears, no Dock icon, Quit works.

**Exit Gate:**
- [x] The distribution target builds for arm64.
- [ ] Menu-bar icon is visible; no Dock icon appears.
- [ ] Quit exits cleanly.

---

### Slice 2 — Minimal Single Portal

**Goal:** Show one movable, resizable portal with a scrollable native icon grid for one user-selected or injected test directory.

**Entry Gate:** Slice 1 exit gate passed and Spike 0.1's selected window strategy plus Spike 0.4's selected material boundary are documented.

**Deliverables:**
- Minimal `PortalWindowing` implementation using the evidence-backed window class, level, collection behaviors, and key-window policy from Spike 0.1.
- One reusable `NSCollectionView` inside an `NSScrollView`.
- System file/folder icons and names; directories first, then localized standard name.
- A development/test composition-root folder picker or fixture URL; no production hardcoded path.
- Minimal loading, empty, and root-enumeration error states.
- Blocking enumeration crosses an explicit background execution boundary; no `FileManager` enumeration on `MainActor`.
- Only the domain values needed for this slice: file identity/item and grid layout inputs.

**Tests:**
- Unit: enumerate normal, empty, and missing test directories; verify ordering and error mapping.
- Unit: grid layout and minimum-size math.
- Integration: selected Spike 0.1 window configuration is applied and the grid displays items.
- Manual: window is movable/resizable, remains at the intended desktop layer, and scrolls smoothly for fewer than 500 items.

**Exit Gate:**
- [ ] A visible portal displays one directory as a native icon grid.
- [ ] Window movement, resize, and scrolling are observable and usable.
- [x] Enumeration does not block the main actor.
- [x] No persistence, tabs, or speculative migration framework is required yet.

---

### Slice 3 — Selection and Opening

**Goal:** Add Finder-consistent selection and read-only opening behavior to the minimal portal.

**Entry Gate:** Slice 2 exit gate passed.

**Deliverables:**
- Single-click selection, Command-click toggle, Shift-click range, arrow navigation, Shift+arrow extension, and Command-A.
- Double-click, Command-Down, and Command-O open the selection through an injected `WorkspaceOpening` adapter.
- Files open with their default app; folders open in Finder.
- Return remains a no-op; no file mutation actions are exposed.
- Runtime `SelectionState` keyed by `FileIdentity`.

**Tests:**
- Unit: every selection-state transition, including empty and stale identities.
- Unit: keyboard navigation and range-anchor behavior.
- Integration: opening adapter receives the expected file and folder URLs.
- Manual: selection and opening with real files and folders.

**Exit Gate:**
- [ ] Finder-style pointer and keyboard selection work.
- [ ] Opening paths work without file mutation.
- [x] No rename, delete, copy, move, drag-in, or drag-out action is available.

---

### Slice 4 — Portal Creation Flow

**Goal:** Enable "New Portal" and create one or more portals by drawing a desktop rectangle and choosing a folder.

**Entry Gate:** Slice 3 exit gate passed.

**Deliverables:**
- Enable the menu-bar "New Portal" command.
- Transparent overlay on the menu-bar primary display (`NSScreen.screens[0]`), constrained to `visibleFrame`.
- Immediate dashed `3×1` card with title/item skeletons, Escape cancellation,
  translucent partial-cell feedback, and whole-column/whole-row snapping at
  half-cell thresholds.
- Persist and present an empty Portal after mouse-up; its in-content Choose Folder action opens the directory-only `NSOpenPanel`.
- Validate the resolved folder's hosting volume and reject removable, ejectable, and network-volume locations without changing the empty Portal.
- Create a runtime portal for the selected folder; repeating the flow can create multiple portals.
- No durable storage yet.

**Tests:**
- Unit: rectangle constraint, cancellation, `3×1` default, half-cell threshold,
  and whole-capacity grid-snap math.
- Integration: overlay → drag → folder selection → portal appears.
- Manual: create multiple portals on available displays.

**Exit Gate:**
- [ ] Creation works end to end.
- [x] Cancel leaves no partial portal.
- [x] Unsupported folder locations leave no partial portal and keep folder selection available.
- [ ] Multiple runtime portals can coexist.

---

### Slice 5 — Minimal Persistence

**Goal:** Restore the portal state that exists at this point: portal identity, one mapped tab, whole grid capacity, current placement, icon-size preference, and creation order.

**Entry Gate:** Slice 4 exit gate passed.

**Deliverables:**
- Small validated domain model for current portal state.
- Versioned v1 JSON envelope at `~/Library/Application Support/Alcove/portals.json`.
- Separate Codable persistence DTOs mapped to domain values.
- Persist the committed `columns × rows` capacity independently from the pixel frame so icon-metric changes retain the user's layout intent.
- Atomic temporary-write and replace behavior with explicit errors.
- Persist only current needs while representing the mapped folder as a one-element tab list so Slice 6 can extend it without an artificial schema migration.
- Reserve schema-version handling; do not build a mock migration chain. Add the first migration only when a real second schema exists.

**Tests:**
- Unit: v1 DTO encode/decode and DTO-domain validation.
- Unit: save/load/relaunch round trip for one and multiple portals.
- Unit: unsupported future version, malformed JSON, and atomic-write failure preserve existing data.
- Manual: created portals and their current frames restore after relaunch.

**Exit Gate:**
- [ ] Current portal state survives restart.
- [x] JSON is versioned and human-readable.
- [x] Domain types are not Codable persistence DTOs.
- [x] No speculative migration framework or display-topology state machine has been added.

---

### Slice 6 — Tabs

**Goal:** Add, switch, close, and reorder multiple folder tabs while preserving runtime selection per tab and durable order.

**Entry Gate:** Slice 5 exit gate passed.

**Deliverables:**
- A centered scrollable folder-title strip with capsule emphasis on the selected
  tab, direct switching, and a fixed trailing settings icon. Full-width separators
  divide the top controls and bottom path row from the file grid. The icon
  opens a centered standalone settings window with a close-only titlebar, a native
  preference-style Folders/Style toolbar, and an explicit separator above content.
- The Folders page lists each tab's abbreviated path with trailing drag and remove controls,
  keeps a Glass Add Folder action in the section heading, and places Remove Panel in a
  descriptive danger card using the standard content material.
- Closing the last tab prompts to remove the portal; it never silently destroys it.
- One reusable grid controller per portal; tab switches replace its model.
- Per-tab runtime selection and scroll state.
- Persist the current tab order and selected tab; the native table drop interaction provides gap
  feedback and performs one atomic reorder.

**Tests:**
- Unit: add, switch, close, reorder, selected-tab validation, order preservation, and last-tab prompt decision.
- Integration: tab switching replaces grid contents and restores per-tab runtime state.
- Integration: add opens `NSOpenPanel`; close follows the last-tab prompt.
- Persistence: reordered tabs and selected tab survive restart.
- Manual: add three tabs, switch among them, close one, relaunch, and verify state.

**Exit Gate:**
- [x] Add, switch, close, and reorder work for multiple tabs at the automated domain/integration boundary.
- [x] Per-tab runtime selection is restored on switch.
- [x] Current order and selected tab persist.
- [x] No tab drag-to-reorder behavior is present.

---

### Slice 7 — Quick Look

**Goal:** Space presents and dismisses `QLPreviewPanel` for the current selection.

**Entry Gate:** Slice 3 exit gate passed and Spike 0.3's responder ownership is reflected in the locked architecture. This slice may follow Slice 6 or proceed independently once those conditions hold.

**Deliverables:**
- Evidence-backed responder-chain ownership and explicit panel data-source/delegate lifecycle.
- Single- and multi-selection previews.
- Space with no selection is a no-op; Space while Alcove owns a visible panel follows Spike 0.3's verified dismissal behavior.
- Panel ownership is cleared safely when relinquished.

**Tests:**
- Unit: preview data source returns ordered selected items.
- Integration: ownership setup and cleanup through adapters where system UI need not be shown.
- Manual/dedicated-host: present, navigate, dismiss, change key window, and test image/PDF/text/movie previews.

**Exit Gate:**
- [ ] Single- and multi-item Quick Look work.
- [ ] Ownership and dismissal match Spike 0.3 evidence.
- [x] Automated lifecycle coverage leaves no stale panel data source or delegate owned by Alcove.

The production integration and adapter-backed automated coverage are complete. The first two
items remain open until real `QLPreviewPanel` rendering, navigation, dismissal, and focus handoff
are observed on the supported desktop-window configurations.

---

### Slice 8 — Display Placement Persistence

**Goal:** Preserve per-display layout records while the complete runtime layout follows the menu-bar primary display across restart, topology changes, and resolution/scaling changes.

**Entry Gate:** Slice 5 exit gate passed and Spike 0.2 has resolved display identity and placement fields. It may proceed after Slice 7 or in parallel with Slices 6–7.

**Deliverables:**
- Display identity adapter and pure placement state machine.
- For each user-confirmed move/resize: display UUID, absolute frame, save-time `visibleFrame`, preferred size, and normalized anchor within the actual movable range.
- Same display and unchanged geometry prefer the absolute frame.
- Changed geometry: constrain preferred size, calculate movable width/height, restore the clamped anchor, grid-snap, then clamp.
- Primary-display change: preserve left/top point offsets, lock fitting frames, and place overflow in right-hand columns without overwriting remembered placements.
- Display return as primary: restore remembered placement when identity matches.

**Tests:**
- Unit: normalized-anchor save/restore for zero and nonzero movable width/height.
- Unit: unchanged geometry uses absolute frame; changed geometry uses preferred size and movable range.
- Unit: size constraint precedes range calculation; grid snap precedes final clamp.
- Unit: primary switch, disconnect, reconnect, rearrangement, and resolution changes keep all runtime frames on the primary display without overwriting remembered placement.
- Integration: screen-geometry descriptors drive the placement coordinator.
- Manual: real external display disconnect/reconnect, rearrangement, scaling, and sleep/wake.

**Exit Gate:**
- [ ] Placement survives the verified topology scenarios.
- [x] Automated integration preserves home placement across system-driven moves.
- [x] Production AlcoveCore placement-state tests cover critical and exceptional paths.

Production code, v1→v2 migration, screen/wake observation, user-only commit boundaries,
and automated topology orchestration are complete. Physical display and WindowServer
scenarios remain open until manually exercised on supported hardware.

---

### Slice 9 — Directory Observation and Auto-Refresh

**Goal:** Refresh the active tab automatically when its mapped directory changes.

**Entry Gate:** Slice 6 exit gate passed and Spike 0.5 has selected the observation strategy and documented permission/lifecycle behavior.

**Deliverables:**
- `FolderObserver` implemented with the Spike 0.5-selected FSEvents configuration and recovery contract.
- Observe only the active tab; stop observation on tab switch or portal close.
- Debounced refresh through `FolderLoadingActor`, which coordinates generations, cancellation intent, and result ordering.
- Blocking enumeration runs on the explicit background boundary from Slice 2.
- Stale results are always rejected.
- Cooperative cancellation is implemented only at real incremental/batch boundaries; a one-shot `FileManager.contentsOfDirectory` call is not described as mid-call cancellable.
- Explicit missing-folder and permission-denied states; unsupported volume locations are rejected at folder-selection boundaries.

**Tests:**
- Unit: generation ordering and stale-result rejection.
- Unit: observer start/stop lifecycle and mapped error states.
- Cancellation: verify result suppression after cancellation; if incremental enumeration is used, verify its documented boundary checks separately.
- Integration: add, remove, and rename files; replace/delete the observed directory; reject removable, ejectable, and network-volume folder selections.
- Manual: modify files in Finder while switching tabs rapidly.

**Exit Gate:**
- [x] The active grid refreshes for automated real-filesystem changes.
- [x] No stale result or background load updates an inactive tab at the automated boundary.
- [ ] Missing and denied states are visible and recoverable; unsupported folder locations are rejected before tab creation or re-mapping.
- [x] Observation behavior uses the Spike 0.5-selected FSEvents mechanism and recovery flags.

Locate Folder UI and controlled TCC denial remain for Slice 10/manual verification.

---

### Slice 10 — Hardening, Accessibility, and Release Preparation

**Goal:** Complete MVP management, accessibility, compatibility, performance, CI, and release preparation without coupling feature completion to Spike 0.6 timing.

**Entry Gate:** Slices 1–9 exit gates passed. Spike 0.6 is not an entry requirement.

**Deliverables:**
- Menu-bar portal list and portal removal management.
- Final loading, empty, missing-folder, and permission states plus unsupported-folder-location selection feedback.
- Per-portal Small/Medium/Large icon sizing, fixed equal tile spacing, resize snap, and 3×1 minimum.
- Per-Portal tint with one application-global five-step static-background transparency control and an accessibility-driven opaque override.
- Application-global four-step edge/inter-Portal spacing and five-step corner radius, plus a system-shadow toggle; creation, dragging, live resize, and icon-preset resize reject collisions, while spacing changes preflight and animate a reversible runtime reflow of existing Portals.
- Evidence-backed static translucent backgrounds on macOS 26+, per-Portal tint preservation, Space-transition stability, and an opaque Reduce Transparency surface.
- VoiceOver labels/actions, keyboard-only operation, Reduce Transparency, Reduce Motion, and Increase Contrast.
- Performance validation for defined NFR directory sizes.
- Push/PR lightweight automation checks plus change-gated tests and unsigned arm64 build verification without artifact publication.
- Version/CHANGELOG release inputs, Apple Development signing, DMG verification, GitHub publication, and Feishu notifications are implemented; manual installation behavior remains a separate release gate.

**Tests:**
- Unit/integration: portal management, error mapping, icon presets, layout limits, and accessibility metadata.
- Build/test: arm64 architecture and deployment-target checks.
- Manual: complete macOS 26/27 compatibility matrix on available hardware; unavailable cells remain unverified risk.
- Release-gate verification (not a Slice 10 product exit condition): signature, provisioning profile, Gatekeeper/quarantine, DMG structure, install, launch, and expiry checks required by Spike 0.6.

**Product Exit Gate:**
- [ ] All MVP acceptance criteria map to passing automated or recorded manual verification.
- [ ] Accessibility and material compatibility reviews pass on available target systems.
- [ ] CI is green and file mutation remains limited to the documented fail-closed operations.

**Separate Release Gate:** The first public GitHub Release remains blocked until Spike 0.6 is resolved and the selected artifact passes the release verification checklist. This gate does not change Slice 10's product-completion status.

---

### Slice 11 — Finder-Style File Actions

**Goal:** Extend the Portal grid with focused Finder-style transfers and contextual actions without turning Alcove into a global Finder extension.

**Entry Gate:** Slice 3 selection and opening, Slice 7 Quick Look ownership, and Slice 9 directory refresh are implemented.

**Deliverables:**
- External Finder/Desktop and same-panel file drags can target ordinary folder tiles. Automatic operation semantics are same-volume Move and cross-volume Copy; Option forces Copy, Command forces Move, and alias-producing Command-Option is rejected.
- A native `NSMenu` follows Finder right-click selection behavior and provides Open, Quick Look, Finder reveal, Get Info, Rename, Compress, Duplicate, Trash, AirDrop, absolute-path copying, and Apple Terminal.
- Single-item inline rename commits with Return/focus loss, cancels with Escape, preserves the extension selection, coordinates the move, never overwrites, and migrates path-based selection.
- `NSWorkspace.duplicate` owns Finder-compatible duplicate naming and returns the new URL selection.
- Single-item Get Info uses Finder's public scripting dictionary to open its actual information window. Paths travel as Apple Event arguments, Automation consent is declared/localized, and denial fails visibly.
- `/usr/bin/ditto` creates Finder-compatible single- and multi-item ZIP files through argument arrays only. Conflict-safe naming never overwrites, subprocess cancellation cleans temporary state, and success selects the archive.
- No Finder Sync extension, global Finder menu injection, full Share menu, alias creation, tags, Services, Quick Actions, new-folder creation, Keep Both, overwrite, or file-operation undo.

**Tests:**
- Unit: modifier resolution, drop-target eligibility, transfer/rename/compression plans, context selection and menu validation, rename editor commands, duplicate mapping, Finder Info script compilation/event arguments/error mapping, and archive naming.
- Integration: coordinated copy/move and case-only rename, real `NSWorkspace.duplicate`, real `ditto` single/multi ZIP contents, cancellation-driven process termination, and post-operation selection migration.
- Manual: right-click placement and enabled states, inline field-editor focus, AirDrop sheet, Apple Terminal launch, Finder Automation consent/Get Info presentation, Finder/Desktop drag badges, and Archive Utility extraction.

**Exit Gate:**
- [x] All new file-operation unit and integration tests pass with the complete app test suite.
- [x] Public Apple APIs, Finder's public scripting dictionary, or the system `ditto` contract back every system-facing action; Finder automation is limited to user-requested Get Info and no shell command construction is used.
- [x] Automated paths never overwrite, and partial/failure states are surfaced explicitly.
- [ ] System UI presentation and real Finder/Desktop drag gestures pass the manual macOS 26/27 compatibility matrix.

---

## Test Strategy

### Automated Tests

| Layer | Framework | Scope | Runs On |
|-------|-----------|-------|---------|
| Unit | XCTest | `AlcoveCore` models, persistence, selection state, normalization, enumeration | Code-impacting PR or publishing run, macOS 26 runner |
| Integration | XCTest with protocol adapters plus bounded real-filesystem/system-tool fixtures | Portal coordination, tab switching, screen geometry, Quick Look ownership, file transfers, rename, duplicate, metadata enumeration, and ZIP creation/cancellation | Code-impacting PR or publishing run, macOS 26 runner |
| UI | Manual / dedicated-host smoke tests | Window behavior, grid rendering, selection gestures, Quick Look, Spaces, Stage Manager | PR smoke + release |

**Unit test requirements:**
- Persistence DTOs must have round-trip `Codable` tests, and every persisted domain type must have DTO ↔ domain mapping tests.
- `PortalStore` must have atomic-write failure tests.
- Selection state machine must cover all transitions (empty → single, single → command-toggle, single → shift-range, etc.).
- Normalized placement must test: unchanged-geometry absolute restore; constrained size; zero and nonzero movable ranges; clamped anchor; aspect-ratio and origin changes; grid-snap then final clamp.

**Integration test requirements:**
- Portal creation flow: overlay → drag → folder select → portal appears.
- Tab lifecycle: add → switch → remove → last-tab-prompt-to-remove-portal.
- Quick Look: select → Space → panel → Space → dismiss (manual/dedicated-host).
- Display placement: mock display change → verify restore logic.

### Manual Compatibility Matrix

Test each combination and record pass/fail/known-issue. If hardware for a specific combination is unavailable, report it as "unverified risk", not pretend verification.

| Scenario | macOS 26 (1 display) | macOS 26 (2 displays) | macOS 27 (1 display) | macOS 27 (2 displays) |
|----------|----------------------|----------------------|----------------------|----------------------|
| Portal creation (drag rect) | | | | |
| Portal persistence (restart) | | | | |
| Display disconnect/reconnect | — | | — | |
| Display rearrange in Settings | — | | — | |
| Resolution/scaling change | | | | |
| Sleep/wake | | | | |
| Spaces: switch away and back | | | | |
| Show Desktop gesture | | | | |
| Stage Manager on/off | | | | |
| Reduce Transparency on | | | | |
| Reduce Motion on | | | | |
| Increase Contrast on | | | | |
| TCC denial (Desktop/Documents) | | | | |
| Missing folder (moved/deleted) | | | | |
| Large directory (1000+ items) | | | | |
| Quick Look: image, PDF, text, movie | | | | |
| Quick Look: multiple selection | | | | |
| External/network folder selection rejected | | | | |

---

## CI / Release Gates

### CI Pipeline (Every PR)

Every `main` push and pull request runs a lightweight Ubuntu validation job. Changes limited to `README.md`, `docs/`, `LICENSE`, or `AGENTS.md` skip the macOS job while publishing is disabled. Any other change, a manual dispatch, or `release=true` runs the complete suite on `macos-26` with pinned Xcode 26.x because macOS 26 is the minimum deployment target. A final `Build Check` job succeeds only when lightweight validation passes and the macOS job either passes or is intentionally skipped, so required checks never remain pending. macOS 27 compatibility requires an available runner, real hardware, a VM, or a self-hosted runner; never claim both OS versions run automatically without confirmed infrastructure.

```
Main push or PR opened
  ├─ Lightweight automation validation (Ubuntu)
  │   └─ FAIL → block merge
  ├─ Classify changed paths and release flag
  │   ├─ docs-only + release=false → skip macOS job
  │   └─ otherwise → tests + unsigned arm64 Release build on macOS 26
  │       └─ FAIL → block merge
  └─ Build Check accepts only lightweight success plus macOS success/intentional skip
```

GUI Quick Look, window, Spaces, and Stage Manager tests are manual or dedicated-host smoke tests, not ordinary headless XCTest guarantees.

### Main Branch Release Gate

The implemented workflow is the selected Apple Development candidate, not yet a manually validated end-user distribution path. Every main push and PR runs lightweight CI; code-impacting or publishing changes additionally run the full macOS suite. After a successful main push, the release planner reads `Config/Release/manifest.json`; it continues only when `release` is true, the repository is public, the version has not been published, and `CHANGELOG.md` contains one exact non-empty matching section. Planning happens on Ubuntu before any signing runner is allocated. The release job sends a best-effort packaging-started notification, imports the P12 in a temporary keychain, builds arm64, signs and verifies Sparkle's nested components and the App from the inside out, verifies the mounted DMG, creates or resumes a draft release, uploads one DMG, publishes, and explicitly dispatches the independently rerunnable appcast/Homebrew metadata workflow. It fails closed and never switches signing modes.

```
First public release after Spike 0.6 is resolved
  ├─ Full CI suite passes
  ├─ Read and validate `x.y.z[-alpha.n|-beta.n]`; skip unless release is enabled and unpublished
  ├─ Require an exact, unique, non-empty CHANGELOG section
  ├─ Import P12 in temporary keychain
  │   └─ FAIL → fail closed (do not silently switch to ad-hoc)
  ├─ Build arm64 Release
  ├─ Sign the Sparkle nested components, framework, and App with one Apple Development identity
  ├─ Package DMG (app + Applications symlink)
  ├─ Verify:
  │   ├─ `codesign --verify --strict --all-architectures` passes (do not use --deep)
  │   ├─ `spctl --assess --type exec` — rejection expected for this unsupported non-Developer-ID path; record it without treating rejection as successful trust
  │   ├─ DMG structure verified
  │   └─ App launches after `sudo xattr -rd com.apple.quarantine /Applications/Alcove.app` on macOS 26
  ├─ Automatically tag `v<version>`
  ├─ Attach only `Alcove.<version>.dmg` to the GitHub Release
  ├─ Release notes: exact CHANGELOG section plus installation instructions
  └─ Dispatch signed appcast and SHA-256-pinned personal-tap Cask publication
```

### Artifact Verification Checklist

For each release artifact, verify before publishing:

- [ ] `lipo -archs Alcove.app/Contents/MacOS/Alcove` → shows exactly `arm64`.
- [ ] `codesign --verify --strict --all-architectures Alcove.app` passes.
- [ ] `codesign -dv --verbose=4 Alcove.app` → matches the signing mode selected and documented by Spike 0.6.
- [ ] `otool -L Alcove.app/Contents/MacOS/Alcove` → no unexpected dynamic libraries.
- [ ] DMG mounts cleanly on macOS 26.
- [ ] App launches using the installation and quarantine procedure selected and documented by Spike 0.6 on macOS 26.
- [ ] Manual macOS 26/27 compatibility matrix — if hardware unavailable, report as "unverified risk".
- [ ] Menu-bar icon appears; no Dock icon.

### Failure Policy

| Failure | Response |
|---------|----------|
| CI build fails | Block merge; fix before re-review |
| Unit test fails | Block merge; fix test or code |
| Integration test fails | Block merge; investigate and fix |
| Manual test fails (release gate) | Block release; document issue; fix or document as known issue |
| Signing fails | Fail closed; do not publish an ad-hoc or unsigned fallback. |
| DMG verification fails | Block release; re-package and re-verify |

---

## Definition of Done (MVP)

A feature is **done** when all of the following are true:

1. **Behavior implemented:** The user-facing behavior described in the acceptance criterion is present and works correctly.
2. **Tests pass:** All automated tests related to the feature pass on macOS 26 runner.
3. **Manual verification:** The feature has been manually tested per the compatibility matrix above. If hardware for a specific combination is unavailable, it is reported as "unverified risk", not treated as verified.
4. **Error states handled:** Missing folders and permission failures produce user-visible feedback, while removable, ejectable, and network-volume selections are rejected before persistence.
5. **Persistence verified:** State survives app restart, display topology changes, and sleep/wake.
6. **No regressions:** Previously passing features remain passing.
7. **Code review:** PR reviewed and approved.
8. **Documentation:** Any user-facing behavior differences between macOS 26 and 27 are documented. Unexecuted verification items and remaining risk are explicitly listed.

MVP feature implementation is **done** when all acceptance criteria in `PRODUCT_REQUIREMENTS.md` unrelated to publication satisfy the above definition. The product is **release-ready** only when Spike 0.6 is resolved and the selected release artifact also passes the verification checklist. Definition of done follows actually available verification; anything unexecuted is explicitly listed with remaining risk.

---

## Summary

| Phase | Gate |
|-------|------|
| Product-and-architecture gate | Spikes 0.1–0.5 resolved with evidence and explicit decisions → architecture lock or product-scope decision |
| Phase 1: Slices 1–11 | Dependency-specific entry and exit gates pass → MVP feature implementation complete |
| Release gate | Spike 0.6 resolved, CI green, selected artifact verified → tagged DMG may be published |

No calendar estimates. Velocity is determined by spike findings and slice complexity. If a spike reveals a fundamental blocker (e.g., desktop-icon level cannot survive Show Desktop), the architecture adapts before implementation begins.
