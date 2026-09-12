# Research — Alcove

**Date:** 2026-08-02
**Purpose:** Evidence record separating confirmed facts, observed implementations, inferences, and required prototypes. Primary citations are provided where available; observations and inferences are labeled as such.

---

## 1. Evidence Classification Table

### 1.1 Window Layering & Desktop Presence

| Claim | Classification | Evidence |
|-------|---------------|----------|
| `CGWindowLevelKey.desktopIconWindow` is a public Core Graphics constant placing windows at the Finder desktop icon level | **Confirmed by Apple** | [Apple Developer — CGWindowLevelKey](https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey/desktopiconwindow) |
| `desktopIconWindow + 1` places a window above desktop icons in one reference implementation | **Observed in reference implementation** | TileTop commit `63ae118d` (Apache-2.0) uses `CGWindowLevelForKey(.desktopIconWindow) + 1`; Apple documents the level constant, but not Alcove's intended relationship to Finder and every system transition |
| `.canJoinAllSpaces` makes a window appear on every Space | **Confirmed by Apple** | [Apple Developer — NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces) |
| `.stationary` prevents a window from moving during Space transitions | **Confirmed by Apple** | [Apple Developer — NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary) |
| `.moveToActiveSpace` moves a window to the active Space when ordered front; `.fullScreenAuxiliary` permits participation alongside a full-screen window | **Confirmed by Apple** (individual flag semantics); combined Alcove behavior is **prototype-required** | [Apple Developer — NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) |
| `.ignoresCycle` excludes a window from window cycling (not Command-Tab application switching) | **Confirmed by Apple** | [Apple Developer — NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/ignorescycle) |
| The correct combination of window level, collection behaviors, `NSWindow` versus `NSPanel`, and key-window eligibility for Alcove | **Prototype required** | No Apple documentation guarantees the combined behavior of a desktop-layer accessory window across Show Desktop, Mission Control, Spaces, Stage Manager, lock, and sleep/wake |

### 1.2 Multi-Display Identity & Placement

| Claim | Classification | Evidence |
|-------|---------------|----------|
| `CGDisplayCreateUUIDFromDisplayID` returns a display UUID | **Confirmed by Apple** | [Apple Developer — CGDisplayCreateUUIDFromDisplayID](https://developer.apple.com/documentation/colorsync/cgdisplaycreateuuidfromdisplayid(_:)) — Apple docs do not explicitly promise stability through every disconnect/reconnect scenario; classify stability as inference/prototype-required |
| `NSScreen.visibleFrame` accounts for the menu bar and Dock; notch/safe-area behavior requires separate validation | **Confirmed by Apple** (menu bar/Dock); safe-area behavior is **prototype-required** | [Apple Developer — NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe) |
| `NSApplication.didChangeScreenParametersNotification` says display configuration changed; exact event coverage (connect/disconnect, resolution, arrangement) is an inference to test | **Confirmed by Apple** (notification exists); exact coverage is **inference** | [Apple Developer — NSApplication.didChangeScreenParametersNotification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification) |
| TileTop stores per-display absolute frames only; system-driven moves (e.g., display disconnect) do not overwrite the saved "home" display frame | **Observed in reference implementation** | TileTop commit `63ae118d` implements per-display absolute frame storage with eviction-safe restoration. Our normalized-plus-absolute design is an Alcove inference, not a TileTop observation |

### 1.3 File System Interaction

| Claim | Classification | Evidence |
|-------|---------------|----------|
| `NSWorkspace.shared.open(_:)` opens a file with its default application | **Confirmed by Apple** | [Apple Developer — NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) |
| `NSWorkspace.shared.open(_:configuration:completionHandler:)` with a folder URL opens it in Finder | **Confirmed by Apple** | [Apple Developer — NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) |
| `NSWorkspace.shared.icon(forFile:)` returns the system icon for any file or folder | **Confirmed by Apple** | [Apple Developer — NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) |
| `NSCollectionViewFlowLayout` exposes item size and minimum spacing, but may distribute remaining line space; fixed Finder-style frames require an app-owned layout | **Confirmed by Apple / architecture consequence** | [Apple Developer — NSCollectionViewFlowLayout](https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout) |
| `NSTextField.maximumNumberOfLines` limits a wrapping field before clipping or truncating | **Confirmed by Apple** | [Apple Developer — maximumNumberOfLines](https://developer.apple.com/documentation/appkit/nstextfield/maximumnumberoflines) |
| Finder desktop icon size, grid spacing, and text size are user-configurable rather than universal constants | **Confirmed by Apple Support** | [Apple Support — Align and resize items in icon view](https://support.apple.com/guide/mac-help/align-and-resize-items-in-icon-view-on-mac-mchlp2209/mac) |
| `DispatchSource.makeFileSystemObjectSource` monitors a directory for changes using kqueue | **Confirmed by Apple** | [Apple Developer — DispatchSourceFileSystemObject](https://developer.apple.com/documentation/dispatch/dispatchsourcefilesystemobject) |
| FSEvents (`FSEventStreamCreate`) provides per-volume change notifications | **Confirmed by Apple** | [Apple Developer — File System Events](https://developer.apple.com/documentation/coreservices/file_system_events) |
| FSEvents as Alcove's active-tab observer | **Selected from local spike evidence** | Phase 0.5A–0.5C7 compared event coverage, path lifecycle, resources, latency, load, teardown, and recovery signals; FSEvents was selected without a DispatchSource fallback |
| Declaring an actor does not by itself prove that a synchronous `FileManager` call executes on a dedicated background thread; a one-shot `contentsOfDirectory` call cannot provide cooperative cancellation during the call | **Architecture constraint / inference to verify in implementation** | Actor isolation coordinates access and ordering; the candidate architecture requires an explicit background execution boundary and does not claim mid-call cancellation for a synchronous API |
| Finder's scripting dictionary exposes desktop icon size and text size, but not grid spacing or Finder's selection renderer | **Confirmed by installed Finder scripting dictionary / API-boundary conclusion** | Reading the exposed values sends an Apple event and requires user-approved Finder Automation access; Alcove must own grid spacing and cell rendering and does not read private Finder preference keys |

### 1.4 Quick Look

| Claim | Classification | Evidence |
|-------|---------------|----------|
| `QLPreviewPanel` is the system Quick Look panel, usable via responder chain integration | **Confirmed by Apple** | [Apple Developer — QLPreviewPanel](https://developer.apple.com/documentation/quicklookui/qlpreviewpanel) |
| Quick Look supports responder-chain integration with a controller that provides panel data source/delegate ownership; Alcove's borderless desktop-level key-window combination is not guaranteed | **Confirmed by Apple** (mechanism); Alcove window behavior is **prototype-required** | [Apple Developer — QLPreviewPanel](https://developer.apple.com/documentation/quicklookui/qlpreviewpanel) |

### 1.5 Visual Effects — Liquid Glass

| Claim | Classification | Evidence |
|-------|---------------|----------|
| `NSGlassEffectView` is the macOS 26 Liquid Glass material view | **Confirmed by Apple** | [Apple Developer — NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) |
| `NSGlassEffectContainerView` groups multiple glass elements for coordinated rendering | **Confirmed by Apple** | [Apple Developer — NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview) |
| Custom content placed on glass must be assigned through `NSGlassEffectView.contentView`, not installed as a sibling behind the content | **Confirmed by Apple** | [WWDC25 session 310 — Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/) |
| `NSGlassEffectView` has no public active-state override; `NSVisualEffectView.state = .active` explicitly requests the active appearance regardless of window activation | **Confirmed by Apple SDK** | `NSGlassEffectView.h` and `NSVisualEffectView.h` in the macOS 26.5 SDK |
| At Alcove's selected desktop window level, folder controls inside a small `NSGlassEffectView.contentView` remained hit-testable but rendered fully transparent; controls must stay in the proven direct TabBar hierarchy above separate Glass and visible-backdrop siblings | **Observed in production UI** | User-provided macOS 26 screenshots on 2026-09-12 after commits `36ac213`, `98cd17d`, and `3345920` |
| Apple recommends glass for chrome, navigation, and controls — not indiscriminately on content canvases | **Confirmed by Apple** | [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), WWDC25 session 219 "Meet Liquid Glass" |
| `NSVisualEffectView` is the macOS vibrancy/material view selected as Alcove's macOS 15–25 fallback | **Architecture selection** (not migration guidance from Apple docs) | [Apple Developer — NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview) |
| WWDC25 session 310 covers AppKit adoption of Liquid Glass | **Confirmed by Apple** | WWDC25 session 310 — "Build an AppKit app with the new design" |
| WWDC25 session 219 covers Liquid Glass design philosophy | **Confirmed by Apple** | WWDC25 session 219 — "Meet Liquid Glass" |
| Local Xcode 26.6 exposes macOS 26.5 SDK headers confirming `NSGlassEffectView` and `NSGlassEffectContainerView` API surface | **Observed locally** | Verified in Xcode 26.6 on this machine; SDK headers at `MacOSX26.5.sdk/System/Library/Frameworks/AppKit.framework/Headers/` |

### 1.6 Distribution & Signing

| Claim | Classification | Evidence |
|-------|---------------|----------|
| Free Apple Development identity (Personal Team) allows local device deployment | **Confirmed by Apple** | [Apple Developer — Program Enrollment](https://developer.apple.com/help/account/membership/program-enrollment/) |
| Free Apple Development identity may impose 7-day provisioning profile expiry | **Confirmed by Apple** | [Apple Developer — Compare Memberships](https://developer.apple.com/support/compare-memberships/) |
| Developer ID distribution and notarization require Apple Developer Program membership | **Confirmed by Apple** | [Apple Developer — Developer ID](https://developer.apple.com/support/developer-id/) |
| Right-click → Open is Apple's official guidance for unidentified developers; `sudo xattr -rd com.apple.quarantine /Applications/Alcove.app` is a project operational workaround | **Confirmed by Apple** (right-click/Open); xattr is project operational guidance | [Apple Support — Open apps from unidentified developer](https://support.apple.com/en-us/102445) |
| Ad-hoc signing (`codesign -s -`) may be useful for a separately invoked local/testing artifact | **Inference; prototype-required for distribution UX** | Standard macOS code signing hierarchy; Spike 0.6 must measure actual Gatekeeper, quarantine, and launch behavior before it is called a usable distribution path |

### 1.7 Permissions (TCC)

| Claim | Classification | Evidence |
|-------|---------------|----------|
| Alcove's non-sandboxed MVP should not require Full Disk Access for ordinary readable folders selected through `NSOpenPanel` | **Architecture inference; prototype-required for protected locations** | Normal POSIX access remains subject to filesystem permissions and TCC; Spike 0.5 records actual behavior |
| Desktop, Documents, and Downloads are protected locations; macOS may prompt the user or require a Privacy & Security setting change | **Confirmed by Apple** | [Apple Platform Security — Controlling app access to files in macOS](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web) |
| Accessibility permission is not required for managing an app's own windows | **Inference** | Accessibility API is for controlling other applications' UI; own-window management uses standard AppKit APIs |

---

## 2. Reference Implementation Analysis

### 2.1 TileTop — Commit `63ae118d711e8f7fc0eaa510678e996794f2456e`

**Repository:** [github.com/NeutrinoLiu/TileTop](https://github.com/NeutrinoLiu/TileTop)
**License:** Apache-2.0
**Commit analyzed:** `63ae118d711e8f7fc0eaa510678e996794f2456e`
**No code was copied; analysis only.**

| Aspect | Observation |
|--------|-------------|
| Window level | Uses `CGWindowLevelForKey(.desktopIconWindow) + 1` — places portal above Finder desktop icons |
| Space behavior | Configures `.canJoinAllSpaces` and `.stationary` for persistent desktop presence |
| Display identity | Stores per-display frame using display UUID; disconnect moves window to primary display without overwriting saved position; reconnect restores original position |
| File grid | `NSCollectionView` with `NSScrollView`; uses `NSWorkspace.shared.icon(forFile:)` for system icons |
| File observation | `DispatchSourceFileSystemObject` for kqueue-based directory monitoring |
| Opening behavior | Double-click folder opens Finder via `NSWorkspace`; double-click file opens with default app |
| Menu bar | `NSStatusItem` for portal management |
| Visual effects | Uses `NSVisualEffectView`; did not explicitly set `.behindWindow` blending mode in the inspected source |
| Selection | Single-click select, Command-click toggle, basic multi-select |
| Scope | Includes rename, trash, new folder, drag-in/out — more than Alcove MVP |
| Multi-display test gaps | Display disconnect/reconnect logic exists but no automated tests; Spaces and Stage Manager behavior unverified |
| Size | ~8 commits, ~1 star at time of analysis; very early stage project |

**Relevance to Alcove:** TileTop demonstrates the core technical approach in one reference implementation (desktop-level window, per-display persistence, `NSCollectionView` file grid, `DispatchSource` monitoring); it does not prove Alcove's full OS compatibility matrix. Alcove implements clean-room. Apache-2.0 attribution is required only if Alcove copies/derives/distributes covered source, not for abstract architectural ideas; we currently copy no code.

### 2.2 Pocket Finder — Commit `234c6920cb8ef6e1ee54e44b2efe7cee22adb6a3`

**Repository:** [github.com/leaton79/pocket-finder](https://github.com/leaton79/pocket-finder)
**License:** GPL-3.0
**Commit analyzed:** `234c6920cb8ef6e1ee54e44b2efe7cee22adb6a3`
**No code was copied; analysis only. GPL-3.0 is copyleft — incorporating Pocket Finder source or a derivative expressive implementation would require GPL analysis. Alcove does not reuse either.**

| Aspect | Observation |
|--------|-------------|
| Window approach | Desktop-layer window; fixed position (screen corner), not user-repositionable |
| File grid | List-based layout rather than icon grid; closer to Finder list view |
| Features | Full file manager: browse subdirectories, search, sort, rename, move, create folders, drag |
| Multi-display | Creates one panel per `NSScreen` and rebuilds all panels on screen-parameter changes; no durable per-display placement |
| Scope | Heavier than Alcove's MVP — full file manager, not a portal viewer |
| Signing | Ad-hoc signed; 0 stars at time of analysis |

**Relevance to Alcove:** Pocket Finder confirms that a desktop-layer file browsing window is technically viable but its architecture is heavier than needed. GPL protects source expression; no Pocket Finder code or expressive implementation is copied. Intentional reuse of Pocket Finder code would require GPL analysis; none is planned.

### 2.3 Desktop Organizer — File Zones (App Store)

**Source:** [App Store — Desktop Organizer](https://apps.apple.com/us/app/desktop-organizer-file-zones/id6504022609?mt=12)
**Analysis:** App Store listing and release notes only; no source code available.

| Aspect | Observation |
|--------|-------------|
| Multi-tab | Added in v3.3 — multiple folder tabs within a single zone |
| Quick Look | Added in v3.1 — Space key file preview |
| Multi-display | v3.0 and v2.10 addressed multi-display positioning bugs |
| User feedback | Reviews cite issues with rename, drag-and-drop, and iCloud files |
| Closest commercial analog | Described by users as the closest Mac equivalent to Windows Fences Folder Portals |

**Relevance to Alcove:** Validates market demand for exactly this product category. Confirms multi-display positioning is a known hard problem that existing commercial apps have struggled with. Alcove's display-UUID-based persistence strategy aims to be more robust.

### 2.4 Stardock Fences (Windows)

**Source:** [Stardock Fences](https://www.stardock.com/products/fences/), [Steam — Fences 6](https://store.steampowered.com/app/3165690/Fences_6/)
**Analysis:** Product marketing and reviews only; Windows-only, closed source.

| Aspect | Observation |
|--------|-------------|
| Folder Portals | Core feature: maps local folders to desktop zones showing file contents inline |
| Tabs | Fences 6 added tabbed zones for switching between multiple folders in one area |
| File interaction | Double-click opens files; drag-and-drop within and between zones |
| Multi-monitor | Supported; positioning tied to specific monitors |
| Market validation | Established product (years of development); sold on Steam and direct; validates the desktop-folder-portal concept on Windows |

**Relevance to Alcove:** Fences Folder Portals is the conceptual origin of this product category. Alcove brings the same paradigm to macOS with native AppKit, Liquid Glass, and display-UUID-based persistence. No code or architecture reference — different platform, different framework.

---

## 3. Inference Log

These are conclusions drawn from confirmed facts and observations, not directly verified:

| ID | Inference | Basis |
|----|-----------|-------|
| INF-01 | `desktopIconWindow + 1` may place Alcove portals above Finder desktop icons but below normal windows on macOS 15–26 | Apple documents the level hierarchy; TileTop observes this configuration on its tested environment, while Spike 0.1 must compare it with other public-API strategies |
| INF-02 | Per-display UUID plus an anchor normalized within the window's actual movable range may survive display topology changes without overwriting home placement | `CGDisplayCreateUUIDFromDisplayID` provides display identity (stability through disconnect/reconnect is inference); TileTop uses per-display absolute frames; the proposed normalized anchor divides by `max(0, visibleFrame dimension - window dimension)`, not the full screen dimension |
| INF-03 | FSEvents is suitable for observing the active tab's eligible internal-local directory | Both candidates passed local lifecycle/load evidence; Phase 0.5C7 selected FSEvents for explicit root-change and dropped/wrapped-event recovery signals |
| INF-04 | Alcove applies Liquid Glass to the centered folder-navigation capsule and keeps the file grid on an always-active translucent material rather than a glass content canvas | Apple says Liquid Glass belongs to the top-level controls/navigation layer, nearby controls should share a logical glass group, and `NSGlassEffectView` has no active-state override |
| INF-05 | Non-sandboxed app with `NSOpenPanel`-selected folders needs no sandbox entitlement or security-scoped bookmark for the MVP path | Access remains subject to normal POSIX permissions and TCC; the spike verifies protected locations |
| INF-06 | Personal Team is suitable for local/development signing, while PR CI disables signing; the proposed end-user release path is an unsupported, non-notarized compromise | Apple's membership comparison defines development/testing scope, not customer distribution; Spike 0.6 must inspect the actual artifact and launch behavior |
| INF-07 | A user-invoked Apple event can read Finder desktop icon/text sizes; exact grid spacing and selection rendering remain app-owned | Finder's scripting dictionary exposes `icon size` and `text size` on desktop icon-view options but no grid-spacing property or reusable desktop cell |

---

## 4. Prototype Required (Spikes)

These items need empirical testing before implementation commitment:

| ID | Spike | Risk | Acceptance Criteria |
|----|-------|------|---------------------|
| SP-01 | Compare public-API desktop-window strategies, beginning with `desktopIconWindow + 1`, `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle` | A single reference configuration may fail under Show Desktop, Spaces, Stage Manager, lock, or sleep/wake | A switchable harness compares `.stationary`, `.moveToActiveSpace`, `.fullScreenAuxiliary`, use or omission of `.canJoinAllSpaces`, `NSWindow` versus `NSPanel`, and key-window eligibility; results identify a strategy or force a product-feasibility decision |
| SP-02 | Spaces, Show Desktop, and Stage Manager behavior for the candidate strategies from SP-01 | Portal may animate, flash, hide, change position, or be permanently evicted | Each tested strategy has recorded behavior across system transitions on the available macOS 15 and 26 matrix; no untested fallback is called successful |
| SP-03 | Quick Look responder-chain behavior from the candidate desktop-level window, including key-window transitions | Quick Look may not activate or relinquish ownership correctly | Space presents and dismisses previews for single and multiple selection, with exact responder ownership documented |
| SP-04 | Display identity, disconnect/reconnect, rearrangement, scaling, and sleep/wake | Display UUID may change or window placement may be overwritten | UUID observations are recorded; temporary eviction preserves remembered home placement; return restores it when identity is recognized |
| SP-05 | Placement restoration using absolute frame plus an anchor normalized within the actual movable range | Full-screen normalization or wrong operation ordering may shift or clip portals | Same geometry prefers the absolute frame; changed geometry first constrains preferred size, computes movable range, restores the clamped normalized anchor, then grid-snaps and clamps |
| SP-06 | `NSGlassEffectView` on portal chrome plus the corresponding `NSVisualEffectView` compatibility path | Either path may have rendering, contrast, accessibility, layout, or selected-window-level issues | Verify acceptable Liquid Glass behavior on macOS 26 and an acceptable functional/layout fallback on macOS 15; failure requires an explicit visual-scope or architecture decision |
| SP-07 | Compare `DispatchSourceFileSystemObject` and FSEvents for eligible internal-local directory observation | Either mechanism may miss lifecycle events or impose unsuitable resource/coalescing behavior | Phase 0.5C7 selects FSEvents without a fallback and defines full-rebuild handling for root-change and dropped/wrapped-event flags; controlled TCC and integration evidence remain |
| SP-08 | Apple Development and ad-hoc signed DMG launch behavior under Gatekeeper | Development signing may not be a durable end-user distribution path, including possible profile expiry | Spike 0.6 inspects the actual artifacts and records quarantine, right-click Open, `xattr`, Gatekeeper, provisioning-profile, expiry, and launch behavior on the available macOS 15 and 26 matrix before the first public release |

---

## 5. Licensing Boundary

| Project | License | Alcove Relationship |
|---------|---------|---------------------|
| TileTop | Apache-2.0 | Permissive. No code copied. Attribution required only if Alcove copies/derives/distributes covered source; abstract ideas do not trigger attribution. |
| Pocket Finder | GPL-3.0 | GPL protects source expression. No Pocket Finder code or expressive implementation is copied. Intentional reuse would require GPL analysis. |
| Desktop Organizer | Proprietary (App Store) | No source access. Market and UX reference only. |
| Stardock Fences | Proprietary (Windows) | Conceptual origin of folder portals paradigm. Platform-specific; no code or architecture reference. |

---

## 6. Source Index

### Apple Documentation

- [CGWindowLevelKey.desktopIconWindow](https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey/desktopiconwindow)
- [NSWindow.CollectionBehavior — canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces)
- [NSWindow.CollectionBehavior — stationary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary)
- [NSWindow.CollectionBehavior — ignoresCycle](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/ignorescycle)
- [NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- [NSApplication.didChangeScreenParametersNotification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)
- [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
- [CGDisplayCreateUUIDFromDisplayID](https://developer.apple.com/documentation/colorsync/cgdisplaycreateuuidfromdisplayid(_:))
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [NSCollectionViewFlowLayout](https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout)
- [NSTextField.maximumNumberOfLines](https://developer.apple.com/documentation/appkit/nstextfield/maximumnumberoflines)
- [Apple Support — Align and resize items in icon view](https://support.apple.com/guide/mac-help/align-and-resize-items-in-icon-view-on-mac-mchlp2209/mac)
- [QLPreviewPanel](https://developer.apple.com/documentation/quicklookui/qlpreviewpanel)
- [File System Events](https://developer.apple.com/documentation/coreservices/file_system_events)
- [DispatchSourceFileSystemObject](https://developer.apple.com/documentation/dispatch/dispatchsourcefilesystemobject)
- [Apple Platform Security — Controlling app access to files in macOS](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web)
- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [WWDC25 Session 219 — Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25 Session 310 — Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/)
- [Apple Developer — Program Enrollment](https://developer.apple.com/help/account/membership/program-enrollment/)
- [Apple Developer — Compare Memberships](https://developer.apple.com/support/compare-memberships/)
- [Apple Developer — Developer ID](https://developer.apple.com/support/developer-id/)
- [Apple Support — Open apps from unidentified developer](https://support.apple.com/en-us/102445)
- [Apple Developer — Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

### Reference Implementations

- [TileTop — github.com/NeutrinoLiu/TileTop](https://github.com/NeutrinoLiu/TileTop) — commit `63ae118d711e8f7fc0eaa510678e996794f2456e` — Apache-2.0
- [Pocket Finder — github.com/leaton79/pocket-finder](https://github.com/leaton79/pocket-finder) — commit `234c6920cb8ef6e1ee54e44b2efe7cee22adb6a3` — GPL-3.0
- [Desktop Organizer — File Zones](https://apps.apple.com/us/app/desktop-organizer-file-zones/id6504022609?mt=12) — App Store (proprietary)
- [Stardock Fences](https://www.stardock.com/products/fences/) — Windows (proprietary)
- [Fences 6 on Steam](https://store.steampowered.com/app/3165690/Fences_6/) — Windows (proprietary)

---

## 7. Local Environment Note

Xcode 26.6 on this machine exposes macOS 26.5 SDK headers confirming `NSGlassEffectView` and `NSGlassEffectContainerView` as public AppKit API. This was verified by inspecting the SDK headers at the standard path. `NSGlassEffectView` exposes `contentView`, `cornerRadius`, `tintColor`, and `style`; `NSGlassEffectContainerView` exposes `contentView` and `spacing`. There is no `isInteractive` or `state` property on either view; standard controls supply interaction.

On 2026-08-02, the critical Apple URLs in this document were checked directly. AnySearch extraction was used to verify the current Apple pages for Developer ID, Quick Look, screen geometry, visual effects, and protected file access; an HTTP status pass then found and corrected two stale documentation paths.
