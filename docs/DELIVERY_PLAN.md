# Delivery Plan — Alcove

## Phase 0: Technical Spikes

Spikes are time-boxed investigations that produce **evidence, not production code**. The six work packages below cover the eight prototype evidence cases (`SP-01` through `SP-08`) tracked in `RESEARCH.md`. Spikes may create disposable prototype harnesses; they produce evidence and are not production implementation. A spike may fail; resolution requires a recorded result and an explicit architecture or product-scope decision, not a forced pass or an unverified fallback.

There are two independent gates:

- **Product-and-architecture gate:** Spikes 0.1–0.5 must be resolved before the production architecture is locked or dependent production slices begin.
- **Release gate:** Spike 0.6 may run in parallel with Phase 1. It does not block App Shell, Portal, or other MVP feature development, but it must be resolved before the first public GitHub Release. Until then, free Apple Development signing is a provisional distribution hypothesis, not a confirmed end-user distribution solution.

Each spike records its findings in `docs/SPIKE_<name>.md`. The candidate architecture is updated from Spikes 0.1–0.5 before architecture lock; release documentation is updated from Spike 0.6 before publication.

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

**Question:** Can we establish a stable display identity via `CGDisplayCreateUUIDFromDisplayID` (or equivalent) that survives display disconnect/reconnect, resolution changes, and rearrangement in System Settings?

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

### Spike 0.4 — Liquid Glass and Fallback

**Question:** Can `NSGlassEffectView` and `NSGlassEffectContainerView` be used for portal chrome (tab bar, title area, controls) on macOS 26, and does `NSVisualEffectView` provide an acceptable visual fallback on macOS 15?

**Approach:**
- On macOS 26: create a window with a tab bar and controls using `NSGlassEffectView` for the chrome area and `NSGlassEffectContainerView` to group them. Verify the glass effect renders correctly at desktop-icon window level.
- On macOS 15 (or a macOS 15 VM): create the same layout using `NSVisualEffectView` with material selected by spike validation.
- Verify both approaches respect `Reduce Transparency` in Accessibility settings.
- Measure the material behavior at the leading window strategies from Spike 0.1 rather than assuming one fixed level.
- Confirm the availability check: `if #available(macOS 26, *)`.

**Exit Gate:**
- [ ] `NSGlassEffectView` renders correctly on macOS 26 at desktop-icon level for chrome elements.
- [ ] `NSVisualEffectView` renders acceptably on macOS 15 for the same layout.
- [ ] Both respect `Reduce Transparency`.
- [ ] Document the `@available` guard pattern and any layout differences.

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

### Spike 0.6 — Apple Development / Ad-hoc DMG Launch Behavior

**Question:** What is the actual user experience when installing and launching an app signed with a free Apple Development identity vs. ad-hoc signed, across macOS 15 and 26?

**Scheduling:** This release-gate spike may run in parallel with Phase 1 and does not block product implementation. It must be resolved before the first public GitHub Release.

**Approach:**
- Build a minimal test app, sign with free Apple Development identity, package as DMG.
- On macOS 15 and 26: mount DMG, drag to Applications, attempt to launch.
- Document every Gatekeeper dialog, quarantine warning, and `xattr` removal step required.
- Repeat with ad-hoc signing (`codesign -s -`).
- Test: does the 7-day profile expiry actually kill the app silently, or does it show a dialog?
- Test: does `sudo xattr -rd com.apple.quarantine /Applications/Alcove.app` reliably remove quarantine?
- Test: does right-click → Open bypass the warning on both macOS versions?

**Exit Gate:**
- [ ] Document the exact installation and first-launch UX for both signing methods.
- [ ] Document the quarantine removal steps to include in README/DMG.
- [ ] Spike 0.6 must inspect the built artifact and launch after expiry to confirm the 7-day expiry behavior (dialog vs. silent kill). Do not assert Alcove's non-sandboxed manually signed build necessarily embeds a Personal Team provisioning profile until inspected.
- [ ] Recommend the signing strategy for CI releases.

---

## Phase 1: Vertical Slices to MVP

Each slice produces a runnable, observable increment and adds only the domain or infrastructure required by that increment. Spikes 0.1–0.5 must be resolved before Slice 1 because they define the production architecture boundary. Spike 0.6 may continue in parallel and blocks only the first public GitHub Release.

### Slice 1 — App Shell and Menu Bar

**Goal:** Launchable LSUIElement app with a menu-bar icon, disabled "New Portal" item, and "Quit"; no portal window yet.

**Entry Gate:** Spikes 0.1–0.5 are resolved with recorded evidence and explicit architecture or product-scope decisions; the candidate architecture has been updated and locked for production implementation. Spike 0.6 is not an entry requirement.

**Deliverables:**
- Xcode project with universal binary target (arm64 + x86_64).
- `Info.plist` with `LSUIElement = true`.
- `NSStatusItem` with Alcove icon.
- Menu with disabled "New Portal", separator, and "Quit".
- App lifecycle: launch, show menu-bar icon, quit.

**Tests:**
- Unit: app delegate registers the status item and expected menu commands.
- Build: deployment target macOS 15 with macOS 26 SDK for arm64 and x86_64.
- Manual: app launches, menu-bar icon appears, no Dock icon, Quit works.

**Exit Gate:**
- [ ] Universal target builds for arm64 and x86_64.
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
- [ ] Enumeration does not block the main actor.
- [ ] No persistence, tabs, or speculative migration framework is required yet.

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
- [ ] No rename, delete, copy, move, drag-in, or drag-out action is available.

---

### Slice 4 — Portal Creation Flow

**Goal:** Enable "New Portal" and create one or more portals by drawing a desktop rectangle and choosing a folder.

**Entry Gate:** Slice 3 exit gate passed.

**Deliverables:**
- Enable the menu-bar "New Portal" command.
- Transparent overlay on the pointer's current display, constrained to `visibleFrame`.
- Dashed rectangle drag, Escape cancellation, and grid-snapped frame.
- Directory-only `NSOpenPanel` after mouse-up.
- Validate the resolved folder's hosting volume and reject removable, ejectable, and network-volume locations without creating a partial portal.
- Create a runtime portal for the selected folder; repeating the flow can create multiple portals.
- No durable storage yet.

**Tests:**
- Unit: rectangle constraint, cancellation, and grid-snap math.
- Integration: overlay → drag → folder selection → portal appears.
- Manual: create multiple portals on available displays.

**Exit Gate:**
- [ ] Creation works end to end.
- [ ] Cancel leaves no partial portal.
- [ ] Unsupported folder locations leave no partial portal and keep folder selection available.
- [ ] Multiple runtime portals can coexist.

---

### Slice 5 — Minimal Persistence

**Goal:** Restore the portal state that exists at this point: portal identity, one mapped tab, current frame, icon-size preset, and creation order.

**Entry Gate:** Slice 4 exit gate passed.

**Deliverables:**
- Small validated domain model for current portal state.
- Versioned v1 JSON envelope at `~/Library/Application Support/Alcove/portals.json`.
- Separate Codable persistence DTOs mapped to domain values.
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
- [ ] JSON is versioned and human-readable.
- [ ] Domain types are not Codable persistence DTOs.
- [ ] No speculative migration framework or display-topology state machine has been added.

---

### Slice 6 — Tabs

**Goal:** Add, switch, and close multiple folder tabs while preserving runtime selection per tab and durable creation order.

**Entry Gate:** Slice 5 exit gate passed.

**Deliverables:**
- Tab bar with folder titles, add button, switching, and close controls.
- Closing the last tab prompts to remove the portal; it never silently destroys it.
- One reusable grid controller per portal; tab switches replace its model.
- Per-tab runtime selection and scroll state.
- Persist tabs in creation order and the selected tab.
- No drag-to-reorder; tab reorder is Post-MVP.

**Tests:**
- Unit: add, switch, close, selected-tab validation, creation-order preservation, and last-tab prompt decision.
- Integration: tab switching replaces grid contents and restores per-tab runtime state.
- Integration: add opens `NSOpenPanel`; close follows the last-tab prompt.
- Persistence: creation order and selected tab survive restart.
- Manual: add three tabs, switch among them, close one, relaunch, and verify state.

**Exit Gate:**
- [ ] Add, switch, and close work for multiple tabs.
- [ ] Per-tab runtime selection is restored on switch.
- [ ] Creation order and selected tab persist.
- [ ] No tab drag-to-reorder behavior is present.

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
- [ ] No stale panel data source or delegate remains.

---

### Slice 8 — Display Placement Persistence

**Goal:** Preserve explicit home placement across restart, display topology changes, resolution/scaling changes, and temporary system eviction.

**Entry Gate:** Slice 5 exit gate passed and Spike 0.2 has resolved display identity and placement fields. It may proceed after Slice 7 or in parallel with Slices 6–7.

**Deliverables:**
- Display identity adapter and pure placement state machine.
- For each user-confirmed move/resize: display UUID, absolute frame, save-time `visibleFrame`, preferred size, and normalized anchor within the actual movable range.
- Same display and unchanged geometry prefer the absolute frame.
- Changed geometry: constrain preferred size, calculate movable width/height, restore the clamped anchor, grid-snap, then clamp.
- Missing display: temporary primary-screen placement without overwriting remembered home placement.
- Display return: restore remembered placement when identity matches.

**Tests:**
- Unit: normalized-anchor save/restore for zero and nonzero movable width/height.
- Unit: unchanged geometry uses absolute frame; changed geometry uses preferred size and movable range.
- Unit: size constraint precedes range calculation; grid snap precedes final clamp.
- Unit: disconnect, temporary eviction, reconnect, rearrangement, and resolution changes do not overwrite home placement.
- Integration: screen-geometry descriptors drive the placement coordinator.
- Manual: real external display disconnect/reconnect, rearrangement, scaling, and sleep/wake.

**Exit Gate:**
- [ ] Placement survives the verified topology scenarios.
- [ ] Home placement is preserved across system-driven moves.
- [ ] Pure placement-state tests cover critical and exceptional paths.

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
- [ ] The active grid refreshes for verified changes.
- [ ] No stale result or background load updates an inactive tab.
- [ ] Missing and denied states are visible and recoverable; unsupported folder locations are rejected before tab creation or re-mapping.
- [ ] Observation behavior matches Spike 0.5 rather than an assumed mechanism.

---

### Slice 10 — Hardening, Accessibility, and Release Preparation

**Goal:** Complete MVP management, accessibility, compatibility, performance, CI, and release preparation without coupling feature completion to Spike 0.6 timing.

**Entry Gate:** Slices 1–9 exit gates passed. Spike 0.6 is not an entry requirement.

**Deliverables:**
- Menu-bar portal list and portal removal management.
- Final loading, empty, missing-folder, and permission states plus unsupported-folder-location selection feedback.
- Alcove-owned Small/Medium/Large icon presets; resize snap and 2×2 minimum.
- Evidence-backed Liquid Glass chrome on macOS 26 and `NSVisualEffectView` fallback on macOS 15–25.
- VoiceOver labels/actions, keyboard-only operation, Reduce Transparency, Reduce Motion, and Increase Contrast.
- Performance validation for defined NFR directory sizes.
- PR CI for build, tests, and unsigned artifacts.
- Release inputs and verification requirements are documented; workflow and DMG implementation belong to the separate release gate after Spike 0.6 selects signing and installation behavior.

**Tests:**
- Unit/integration: portal management, error mapping, icon presets, layout limits, and accessibility metadata.
- Build/test: universal architecture and deployment-target checks.
- Manual: complete macOS 15/26 compatibility matrix on available hardware; unavailable cells remain unverified risk.
- Release-gate verification (not a Slice 10 product exit condition): signature, provisioning profile, Gatekeeper/quarantine, DMG structure, install, launch, and expiry checks required by Spike 0.6.

**Product Exit Gate:**
- [ ] All MVP acceptance criteria map to passing automated or recorded manual verification.
- [ ] Accessibility and material compatibility reviews pass on available target systems.
- [ ] CI is green and no excluded file-mutation feature is present.

**Separate Release Gate:** The first public GitHub Release remains blocked until Spike 0.6 is resolved and the selected artifact passes the release verification checklist. This gate does not change Slice 10's product-completion status.

---
## Test Strategy

### Automated Tests

| Layer | Framework | Scope | Runs On |
|-------|-----------|-------|---------|
| Unit | XCTest | `AlcoveCore` models, persistence, selection state, normalization, enumeration | Every PR, macOS 26 runner |
| Integration | XCTest with `WorkspaceOpening` / `ScreenGeometryProvider` protocol adapters | Portal coordination, tab switching, screen-geometry adapters, Quick Look data-source ownership without presenting system UI | Every PR, macOS 26 runner |
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

| Scenario | macOS 15 (1 display) | macOS 15 (2 displays) | macOS 26 (1 display) | macOS 26 (2 displays) |
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
| Universal binary on Intel | | | | |

---

## CI / Release Gates

### CI Pipeline (Every PR)

Primary GitHub CI uses `macos-26` with pinned Xcode 26.x because the app compiles against the 26 SDK. macOS 15 runtime compatibility requires real hardware, a VM/self-hosted runner, or a separately supported runner capable of running an artifact built with the 26 SDK; never claim both OS versions run automatically on every PR without confirmed infrastructure.

```
PR opened
  ├─ Build (arm64 + x86_64, macOS 26 SDK, deployment target macOS 15)
  │   └─ FAIL → block merge
  ├─ Unit tests (macOS 26 runner)
  │   └─ FAIL → block merge
  ├─ Integration tests (macOS 26 runner)
  │   └─ FAIL → block merge
  ├─ Lint (SwiftLint, if configured)
  │   └─ WARN → allow merge, log issue
  └─ Produce unsigned .app artifact
      └─ Archive for manual testing
```

GUI Quick Look, window, Spaces, and Stage Manager tests are manual or dedicated-host smoke tests, not ordinary headless XCTest guarantees.

### Main Branch Release Gate

No public main-branch release workflow is final until Spike 0.6 resolves Apple Development versus ad-hoc artifact behavior. The workflow below is the current Apple Development candidate, not a confirmed end-user distribution path. If Spike 0.6 selects it, the workflow tests first, reads `MARKETING_VERSION`, skips publication if that tag already exists, imports the P12 in a temporary keychain, builds universal Release, verifies, tests DMG structure, then publishes. It must fail closed if the selected signing inputs or verification fail; it must never silently switch signing modes. An ad-hoc artifact, if retained by the spike decision, uses a separately invoked workflow.

```
First public release after Spike 0.6 is resolved
  ├─ Full CI suite passes
  ├─ Read MARKETING_VERSION; skip if tag already exists
  ├─ Import P12 in temporary keychain
  │   └─ FAIL → fail closed (do not silently switch to ad-hoc)
  ├─ Build universal Release (arm64 + x86_64)
  ├─ Sign with Apple Development identity
  ├─ Package DMG (app + Applications symlink)
  ├─ Verify:
  │   ├─ `codesign --verify --strict --all-architectures` passes (do not use --deep)
  │   ├─ `spctl --assess --type exec` — rejection expected for this unsupported non-Developer-ID path; record it without treating rejection as successful trust
  │   ├─ DMG structure verified
  │   └─ App launches after `sudo xattr -rd com.apple.quarantine /Applications/Alcove.app` on macOS 26
  ├─ Tag release (semver: `v0.x.0` during MVP, `v1.0.0` at MVP completion)
  ├─ Attach DMG to GitHub Release
  └─ Release notes: changes, known issues, installation instructions
```

Ad-hoc signing (`codesign -s -`) remains a Spike 0.6 candidate. If the final decision retains it, it is a separately invoked explicit workflow, not an automatic fallback.

### Artifact Verification Checklist

For each release artifact, verify before publishing:

- [ ] `lipo -info Alcove.app/Contents/MacOS/Alcove` → shows `arm64` and `x86_64`.
- [ ] `codesign --verify --strict --all-architectures Alcove.app` passes.
- [ ] `codesign -dv --verbose=4 Alcove.app` → matches the signing mode selected and documented by Spike 0.6.
- [ ] `otool -L Alcove.app/Contents/MacOS/Alcove` → no unexpected dynamic libraries.
- [ ] DMG mounts cleanly on macOS 26.
- [ ] App launches using the installation and quarantine procedure selected and documented by Spike 0.6 on macOS 26.
- [ ] Manual macOS 15 compatibility matrix — if hardware unavailable, report as "unverified risk".
- [ ] Menu-bar icon appears; no Dock icon.

### Failure Policy

| Failure | Response |
|---------|----------|
| CI build fails | Block merge; fix before re-review |
| Unit test fails | Block merge; fix test or code |
| Integration test fails | Block merge; investigate and fix |
| Manual test fails (release gate) | Block release; document issue; fix or document as known issue |
| Signing fails | Fail closed; do not silently switch to ad-hoc. Ad-hoc is a separately invoked fallback workflow. |
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
8. **Documentation:** Any user-facing behavior differences between macOS 15 and 26 are documented. Unexecuted verification items and remaining risk are explicitly listed.

MVP feature implementation is **done** when all acceptance criteria in `PRODUCT_REQUIREMENTS.md` unrelated to publication satisfy the above definition. The product is **release-ready** only when Spike 0.6 is resolved and the selected release artifact also passes the verification checklist. Definition of done follows actually available verification; anything unexecuted is explicitly listed with remaining risk.

---

## Summary

| Phase | Gate |
|-------|------|
| Product-and-architecture gate | Spikes 0.1–0.5 resolved with evidence and explicit decisions → architecture lock or product-scope decision |
| Phase 1: Slices 1–10 | Dependency-specific entry and exit gates pass → MVP feature implementation complete |
| Release gate | Spike 0.6 resolved, CI green, selected artifact verified → tagged DMG may be published |

No calendar estimates. Velocity is determined by spike findings and slice complexity. If a spike reveals a fundamental blocker (e.g., desktop-icon level cannot survive Show Desktop), the architecture adapts before implementation begins.
