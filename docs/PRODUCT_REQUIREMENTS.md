# Product Requirements — Alcove

## 1. Product Overview

Alcove is a native macOS menu-bar utility that creates movable, resizable desktop-layer folder portals. Each portal displays the contents of a mapped directory on the Mac's internal, fixed local storage as a scrollable native icon grid. Portals support multiple tabs, Finder-consistent selection and interaction, and Quick Look integration.

Alcove is **not** a Finder replacement or a full desktop shell. It is a focused view into folders the user chooses, displayed on the desktop layer below normal application windows, with bounded in-Portal navigation.

---

## 2. Goals

| ID | Goal |
|----|------|
| G-1 | Provide persistent desktop-layer folder portals that survive display topology changes, Spaces, Stage Manager, sleep/wake, and resolution adjustments |
| G-2 | Match Finder's selection and opening semantics for familiar, low-friction interaction |
| G-3 | Offer Quick Look for selected items without leaving the portal |
| G-4 | Keep the complete multi-Portal layout on the menu-bar primary display and migrate it when the primary display changes |
| G-5 | Require macOS 26 or later and provide a stable static translucent Portal background across Spaces |

## 3. Non-Goals (MVP)

| ID | Non-Goal | Rationale |
|----|----------|-----------|
| NG-1 | Unbounded filesystem browsing | Navigation is scoped to each mapped folder's runtime history and never changes the durable mapped root |
| NG-2 | New-folder creation | Keep the focused Portal surface smaller than a general file manager |
| NG-3 | Conflict replacement, Keep Both, and file-operation undo | Initial file transfers fail closed instead of overwriting |
| NG-5 | WidgetKit widgets | Alcove is a windowed utility, not a widget |
| NG-6 | Finder extension or Finder integration beyond NSWorkspace | Out of scope |
| NG-7 | Cloud drive sync status indicators | Deferred; adds complexity with provider-specific APIs |
| NG-8 | Custom file preview/rendering inside the grid | Native icon grid only; Quick Look handles preview |
| NG-9 | Folders on removable, ejectable, or network volumes | Alcove supports folders on the Mac's internal, fixed local storage only |

---

## 4. Personas & Use Cases

### Persona: Developer / Power User
- Keeps project folders, Downloads, and reference material visible on desktop
- Uses multiple displays; the complete Portal layout must follow changes to the menu-bar primary display
- Wants fast access without opening Finder windows

### Persona: Creative Professional
- Organizes assets into folders; wants visual overview on desktop
- Uses Spaces and Stage Manager; portals must coexist without disruption
- Needs Quick Look to preview files quickly

### Core Use Cases

| ID | Use Case |
|----|----------|
| UC-1 | Create a new portal by dragging a dashed rectangle on the desktop, then choosing a folder |
| UC-2 | View folder contents as an icon grid inside a portal |
| UC-3 | Select items with single-click, Command-click, Shift-click |
| UC-4 | Open a file or folder with double-click |
| UC-5 | Invoke Quick Look with Space for selected items |
| UC-6 | Add, switch, close, and move folder tabs within a portal; preserve the resulting order and selected tab across restarts |
| UC-7 | Move and resize a portal; have it remember position across sessions |
| UC-8 | Disconnect, reconnect, or change the menu-bar primary display and see the complete layout follow it without losing remembered per-display positions |
| UC-9 | Switch Spaces and continue seeing portals on every Space; exact system-transition behavior is resolved by the desktop-layer spike |

---

## 5. Interaction Contract

### 5.1 Selection

| Action | Behavior |
|--------|----------|
| Click | Select the clicked item; deselect all others |
| Command-click | Toggle selection of the clicked item without affecting others |
| Shift-click | Extend selection from the anchor to the clicked item (range select) |
| Arrow keys | Move focus; Shift+arrow extends selection |
| Select All (⌘A) | Select all items in the current tab |
| Drag from empty grid space | Select every item tile intersecting the visible marquee; dragging in either direction is supported |
| Command-drag from empty grid space | Toggle the marquee's items against the selection frozen at mouse-down |

Selection state is per-tab. Changing tabs preserves each tab's selection independently.

Return starts inline rename when exactly one item is selected. Tab/Shift-Tab item cycling is not included.

### 5.2 Opening

| Action | Behavior |
|--------|----------|
| Double-click file | Open with default application via `NSWorkspace` |
| Double-click ordinary folder | Enter it in the current Portal tab; packages and symbolic links continue through the system default application |
| Back | Return through the current tab's runtime history without crossing its mapped root |
| ⌘↓ (Command-Down) | Open selected item — same as double-click |
| ⌘O (Command-O) | Open selected item — same as double-click |

### 5.3 Quick Look

| Action | Behavior |
|--------|----------|
| Space (with selection) | Present `QLPreviewPanel` for the selected item(s) |
| Space (no selection) | No-op |
| Space (during Quick Look) | Intended to dismiss Quick Look; exact behavior is resolved by the Quick Look spike |

Quick Look follows the responder chain. The portal window owns the Quick Look responder integration.

### 5.4 File Operations

| Action | Behavior |
|--------|----------|
| Command-Delete | Freeze the ordered selection, invalidate Quick Look, and move the selected URLs to Trash through `NSWorkspace.recycle` |
| Drag from Alcove to Finder/Desktop | Publish the native file URLs through the collection view's AppKit drag session; Alcove never deletes the source after the external drop |
| Drag from Finder to empty Portal grid space or an ordinary folder tile | Transfer all dropped items into the current browsed directory or targeted folder using Finder volume semantics |
| Drag from Alcove to an ordinary folder tile in the same panel | Transfer the selected items into that folder; local background drops remain invalid |
| Finder-style transfer modifiers | Same-volume defaults to Move, cross-volume defaults to Copy, Option forces Copy, Command forces Move, and Command-Option is rejected because alias creation is out of scope |
| Right-click an item | Preserve an existing multi-selection or select only the newly clicked item, then show a native contextual menu |
| Right-click empty grid space | Show no file menu and leave selection unchanged |
| Contextual Open / Quick Look / Show in Finder / Trash | Reuse the same ordered selection and existing native behaviors |
| Contextual Get Info with one selected item | Ask Finder through a user-authorized Apple Event to open its actual information window |
| Contextual AirDrop / Copy Path / Open in Terminal | Invoke AirDrop directly, copy newline-separated absolute paths, or open unique selected folders/file-parent folders in Apple Terminal |
| Return or contextual Rename with one selected item | Edit the tile title inline; initially select the stem for files and the complete name for folders |
| Rename Return / focus loss / Escape | Commit on Return or focus loss; cancel and restore the original title on Escape |
| Contextual Duplicate | Ask `NSWorkspace` to duplicate the ordered selection with Finder naming, then select the returned copies and reload |
| Contextual Compress | Create one Finder-compatible ZIP beside the selection, use conflict-safe incremental naming without overwrite, then select the archive and reload |

Before any file mutation, Alcove validates the complete source snapshot off the main actor. An item already in the destination, a duplicate or existing destination name, and a directory transferred into its own descendant are rejected. Alcove never overwrites. Accepted work runs outside the main actor under `NSFileCoordinator`; FSEvents and an explicit reload converge the grid after completion. A multi-item failure reports how many preceding items completed rather than hiding partial progress.

### 5.5 Portal Creation Flow

1. User activates portal creation from the menu bar (clicks Alcove icon → "New Portal")
2. A transparent overlay appears on the menu-bar primary display (`NSScreen.screens[0]`), regardless of pointer location
3. A dashed `3×1` portal appears immediately. It previews the rounded outer frame, two full-width separators, and complete object tiles using the Medium preset; it does not recreate the removed title/path capsules or split an object into separate icon and name boxes.
4. Dragging changes columns and rows at half-cell thresholds: partial progress remains a translucent candidate until the next whole capacity is committed.
5. A candidate that violates the configured screen-edge or inter-Portal spacing is shown as invalid and is not submitted. On a valid mouse-up, Alcove revalidates, persists, and presents an empty Portal; creation does not open a folder chooser.
6. The empty Portal shows a Choose Folder action in its content area. That action opens the standard directory-only `NSOpenPanel`.
7. Alcove validates that the selected folder is on the Mac's internal, fixed local storage; removable, ejectable, and network-volume locations are rejected with an explanation.
8. An eligible folder becomes the first selected tab. Cancelling or rejecting the choice leaves the empty Portal intact.
9. The committed whole `columns × rows` capacity is persisted; its physical frame is derived from the active icon and text metrics.

### 5.6 Tab Management

| Action | Behavior |
|--------|----------|
| Click tab | Switch to that tab's folder |
| Settings → Folders → Add Folder… | Add a new tab until the per-Portal maximum of four; at four the count/limit remains visible and Add Folder is disabled |
| Settings → Folders → Remove current folder | Remove the selected tab; if last tab, prompt to remove the portal (never silently destroy it) |
| Application Settings → Style | Choose a global Small, Medium, or Large content size while preserving every Portal's grid capacity; attached Portals move together to retain the selected edge/inter-Portal gap, while unrelated free placements retain their top-left intent |
| Settings → Folders → Remove Panel | Remove the complete Portal from the destructive action card at the bottom |
| Tab title | Defaults to the mapped folder name |

Tabs appear as at most four equal segments in one horizontally centered, shadow-free outer
capsule. The selected folder uses one neutral inner capsule; unselected segments remain clear.
Small/Medium/Large prefer `56/64/72pt` segment widths and scale without changing the top-row
height. Narrow Portals compress all segments equally and truncate long labels instead of
providing horizontal scrolling. Per-tab close
and add buttons are intentionally omitted;
editing actions open from the fixed trailing settings icon in a separate centered
settings window. A standard close-only titlebar remains above a native preference-style toolbar;
an explicit system separator divides the Folders and Style navigation from the lower content.
The Folders section shows a Glass Add Folder button in its heading and
one abbreviated folder path per native table row, with a trailing drag indicator and borderless
remove action. Dropping a row performs one atomic reorder with native gap feedback. Remove Panel
lives in a separate descriptive destructive card at the bottom of the same page.

The trailing gear menu's Pin command persists per Portal. Pinning disables user-driven dragging and
resizing while leaving tab, file, Quick Look, settings, and display-recovery
interactions available. A dedicated bottom row reserves space below the file grid and shows the
selected folder's path, abbreviating the current home directory as `~`; its copy button writes the
displayed path to the clipboard. Subtle separators divide the top controls and bottom path row from
the file grid. Empty Portals keep the row's layout space but hide the path content.

### 5.7 Portal Window Behavior

| Property | Value |
|----------|-------|
| Window level | Desktop-layer behavior required; the exact public-API strategy is selected by Spike 0.1. `desktopIconWindow + 1` is the first candidate, not a final configuration. |
| Collection behavior | Selected by Spike 0.1 after comparing relevant combinations, including `.stationary`, `.moveToActiveSpace`, `.fullScreenAuxiliary`, and whether to use `.canJoinAllSpaces`. |
| Title bar | None — no traffic-light window controls |
| Movable | Yes — user-initiated drag from empty space in the top control row, unless the Portal is pinned |
| Resizable | Yes — user-initiated resize from edges/corners, unless the Portal is pinned |
| Inactive appearance | Portal material and folder controls retain their active visual contrast when another app becomes active |
| Frame snap | Columns and rows switch at half-cell thresholds and always settle on a whole `columns × rows` capacity; that committed column count directly controls item wrapping and is never re-derived from a slightly smaller content rectangle |
| Min size | 3 columns × 1 row |
| Placement bounds | User dragging and resizing remain inside the menu-bar primary display's fresh `visibleFrame`, including the configured edge spacing; other Portals are fixed obstacles with the same spacing. Portals cannot be left on a secondary display |

The file grid uses 8pt top and bottom content insets. These insets are part of the
capacity-to-frame calculation, so existing persisted placements are migrated when they change.
Horizontal and vertical spacing between complete file-object tiles are both 4pt; the persisted
column capacity remains authoritative while the physical frame width follows those metrics.

---

## 6. Requirement IDs

### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-01 | Create portals via menu-bar → overlay → drag-rect → folder-choose flow | MVP |
| FR-02 | Display folder contents as Finder-style icon tiles with one borderless object space containing padded icon and title regions, separate icon/title selection treatments, and a fixed-height title of at most two lines. Long titles keep the first line intact and middle-truncate only the second line so the filename ending remains visible; the tooltip, accessibility label, and rename editor retain the complete name. Default ordering is directories first, then localized standard name. Layout is continuous row-major order: widening pulls the next lower-row items into the preceding row, and narrowing pushes trailing items into following rows. | MVP |
| FR-03 | Support adding, switching, closing, and moving up to four folder tabs per portal; persist the resulting order and selected tab. The settings UI shows the count and disables addition at four, while domain restoration and backup import reject any fifth folder. The centered segmented capsule never scrolls; constrained widths compress equally and labels truncate at the tail. Closing the last tab prompts to remove the portal. | MVP |
| FR-04 | Finder-consistent selection (single, Command, Shift, keyboard, and bidirectional empty-space marquee with Command-toggle semantics) | MVP |
| FR-05 | Double-click files/packages/symbolic links opens with the default app; double-click an ordinary directory enters it in the current Portal tab; Back restores that tab's prior directory, selection, and scroll position | MVP |
| FR-06 | Quick Look via Space key through responder chain | MVP |
| FR-07 | Portal frames persist across app restarts | MVP |
| FR-08 | The complete Portal layout follows the menu-bar primary display after topology, primary-display, resolution, or scaling changes. Projection preserves each frame's point offsets from the old primary `visibleFrame` left/top edges; fitting non-conflicting frames remain fixed, overflow opens columns to the right from top to bottom, and an over-capacity fallback uses distinct exposed-top slots until finite screen space is exhausted. Further panels may overlap completely but remain recoverable through menu-bar Show, which brings the selected panel to the front | MVP |
| FR-09 | Multiple portals supported simultaneously | MVP |
| FR-10 | Multiple connected displays are supported as topology inputs, but all Portal windows and new-Portal creation remain on the menu-bar primary display | MVP |
| FR-11 | Menu-bar icon with portal management menu | MVP |
| FR-12 | All Portals share one global content-size preset and one global five-step static-background transparency level; each Portal retains its own subtle tint. Changing size is preflighted for every Portal before any frame changes. Lightweight separators distinguish the top controls and bottom path row. Clicking the top controls or draggable background activates the Portal just like clicking its grid or path row. | MVP |
| FR-13 | Require macOS 26 or later. Portal backgrounds use a plain alpha-composited static surface without `NSGlassEffectView`, `NSVisualEffectView`, or WindowServer backdrop sampling. Reduce Transparency overrides it with an opaque accessibility surface | MVP |
| FR-14 | Folder enumeration runs across an explicit background execution boundary, rejects stale results, and honors cancellation at real incremental or batch boundaries when the selected enumeration API permits it | MVP |
| FR-15 | Observe content changes for the active tab's mapped directory. The concrete observation mechanism is selected by Spike 0.5. | MVP |
| FR-16 | Automatic grid refresh when folder contents change | MVP |
| FR-17 | Use native multi-item file-URL drag sessions for Portal-to-Finder/Desktop export; accept external file URLs on the current-directory background or an ordinary folder tile and accept in-panel file URLs on ordinary folder tiles. Same-volume transfers default to Move, cross-volume transfers default to Copy, Option forces Copy, Command forces Move, and Command-Option is rejected because alias creation is out of scope | MVP |
| FR-19 | Accept mapped folders only when their resolved location is on the Mac's internal, fixed local storage; reject removable, ejectable, and network-volume locations before creating or remapping a tab | MVP |
| FR-20 | Persist a per-Portal pinned state that disables user movement and resizing without blocking system placement recovery | MVP |
| FR-21 | Show the selected folder path in a reserved bottom row separated from the file grid, abbreviate the home directory as `~`, and provide a clipboard copy action | MVP |
| FR-22 | The menu bar lists New Portal, each Portal with SF Symbol-labelled Show, Hide, Pin/Unpin, Panel Settings, and confirmed Remove commands, Check for Updates, application Settings, and Quit. Application Settings provides General, Style, Advanced, and About categories; General controls launch at login and the app language (Follow System, English, Simplified Chinese, or Traditional Chinese) and offers to quit and automatically reopen Alcove to apply a changed language, Style owns global content size, transparency, spacing (`2/4/6/8pt`), corner radius (`0/8/14/20/24pt`), and system shadow with a system separator between each row, Advanced repairs off-screen or conflicting panel positions and imports or exports the complete layout, and About shows the bundled app icon, version/build, copyright, and another Check for Updates action. All user-facing UI uses the selected supported language, with the current macOS language and English fallback used when Follow System is selected | MVP |
| FR-23 | New placement, user dragging, live resizing, and global content-size changes must not overlap another Portal and must honor the selected edge/inter-Portal spacing. Portals attached within the four-step spacing range to a screen edge or another Portal retain that relationship when either spacing or content size changes, so expansion pushes and contraction pulls the attached layout in both directions. Unattached free placements retain their top-left intent when legal. The complete primary-display plan is accepted atomically, and style-driven or topology-driven reflow does not overwrite durable placement. Manual repair persists only repaired frames and leaves already visible non-conflicting frames unchanged. | MVP |
| FR-24 | Each Portal persists its own name/modified/created sort order and one built-in neutral or rainbow tint. The gear opens an SF Symbol-labelled native menu for pinning, sorting, Portal settings, and confirmed Portal removal. Removal confirmation is an independent app-modal alert centered in the current Portal screen's fresh `visibleFrame`, not an attached sheet. Portal settings show all sort choices as radio buttons and all tint choices as circular single-selection swatches; global content size and transparency are not duplicated there. | MVP |
| FR-25 | Advanced settings exports a stable versioned JSON layout backup containing global Portal appearance and portable per-Portal layout state, but never launch-at-login. Import ignores the retired `background_type` key in older version 1 files, strictly validates the rest of the document and, after confirmation, replaces rather than merges the current layout. The replacement is preflighted against the fresh primary display and persisted once before runtime windows change; any validation or save failure leaves the current runtime layout untouched. | MVP |
| FR-26 | Command-Delete moves a frozen ordered selection to Trash through `NSWorkspace.recycle`; drop transfers validate the entire snapshot before asynchronous coordinated IO, reject same-destination, overwrite, duplicate-name, and self-descendant cases, and report partial failure explicitly | MVP |
| FR-27 | Right-clicking an item presents a native validated contextual menu while following Finder selection semantics. It provides Open, native Quick Look, Show in Finder, single-item Finder Get Info through user-authorized Apple Events, single-item inline Rename, cancellable Finder-compatible ZIP compression, Finder-style Duplicate through `NSWorkspace`, Move to Trash, direct AirDrop, newline-separated absolute-path copying, and Apple Terminal opening; right-clicking blank grid space neither displays a file menu nor changes selection. Get Info uses Finder's public scripting dictionary and passes paths as event arguments; Return also begins single-item rename; invalid/conflicting names never overwrite; compression never invokes a shell or overwrites; Escape cancels rename; and successful rename/duplicate/compress actions retain the returned URL selection | MVP |

### Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-01 | Grid scroll performance (60 fps) | < 16 ms frame budget |
| NFR-02 | Portal creation to first content display | < 1 s for folders with < 500 items |
| NFR-03 | Folder enumeration for < 1000 items | < 500 ms |
| NFR-04 | Portal frame restore after display change | < 2 s |
| NFR-05 | App launch to menu-bar icon visible | < 1 s |

---

## 7. States

### 7.1 Empty States

| State | Display |
|-------|---------|
| Empty folder | Placeholder text: "This folder is empty" with folder icon |
| Empty Portal | Shows an in-Portal Choose Folder action; it has no tabs and no selected tab until the first eligible folder is chosen |

### 7.2 Error States

| Error | Display | Action |
|-------|---------|--------|
| Folder not found (moved/deleted) | Error banner: "Folder not found" with path | Offer "Locate Folder…" to re-map |
| Permission denied (TCC-protected) | Error banner: "Permission denied" with folder name | Report the system result accurately; Alcove does not fabricate or force a permission flow, while macOS may present its own prompt |
| Read error (I/O) | Error banner: "Unable to read folder contents" | Show retry button |
| Unsupported folder location | Selection error: "Choose a folder on this Mac's internal disk" | Keep the chooser flow available; do not create or remap the tab |

### 7.3 Loading States

| State | Display |
|-------|---------|
| Initial folder load | Skeleton/placeholder grid with progress indicator |
| Refreshing after content change | No full-screen overlay; items update incrementally |

---

## 8. Accessibility

| ID | Requirement |
|----|-------------|
| A-01 | Full VoiceOver support for grid items (role, label, value, position, actions) |
| A-02 | Keyboard-only operation for all selection, opening, and Quick Look actions |
| A-03 | Respects System Settings → Accessibility → Reduce Transparency |
| A-04 | Respects System Settings → Accessibility → Increase Contrast |
| A-05 | Standard macOS AppKit control sizes for interactive elements; sufficient focus indicators and contrast |
| A-06 | Per-portal Small/Medium/Large sizing through a keyboard-accessible three-step slider |
| A-07 | Respects System Settings → Accessibility → Reduce Motion |
| A-08 | VoiceOver labels and actions for all interactive elements |
| A-09 | Pin, path, copy, menu, and settings controls expose localized accessibility labels and help |

---

## 9. Privacy & Permissions

| ID | Requirement |
|----|-------------|
| PR-01 | No sandbox; non-sandboxed LSUIElement app |
| PR-02 | No Accessibility permission required for core functionality |
| PR-03 | No Full Disk Access required for core functionality |
| PR-04 | TCC-protected folders (Desktop, Documents, Downloads) may trigger system permission prompts — surface explicit errors, do not silently fail |
| PR-05 | No App Groups, Keychain, security-scoped bookmarks, or application-level provisioning-profile dependency in MVP; the non-sandboxed app persists a standardized file URL/path. Spike 0.6 separately inspects whether a signing workflow embeds a profile in the release candidate. |
| PR-06 | No telemetry, analytics, or network calls in MVP |
| PR-07 | All state stored locally under `~/Library/Application Support/Alcove/` |

---

## 10. Distribution

The table below is the implemented release candidate, not a confirmed final-user distribution path. Apple Development is the selected signing mode; Spike 0.6 must still resolve its actual Gatekeeper, expiry, and installation behavior before the first public GitHub Release. Until then, no document may claim free Apple Development signing is a validated end-user distribution solution.

| Aspect | Detail |
|--------|--------|
| PR builds | Unsigned; CI test gate only |
| Main branch releases | Selected Apple Development implementation: imported P12 in CI, arm64 only, not notarized; manual installation evidence remains gated by Spike 0.6 |
| First launch / quarantine | Spike 0.6 determines and documents the verified steps; right-click → Open and `sudo xattr -rd com.apple.quarantine /Applications/Alcove.app` are candidates to test, not assumed universal requirements |
| DMG packaging | Standard DMG with app bundle and Applications symlink |
| GitHub Releases | A manifest version plus explicit release switch gates an automatically tagged release with one `Alcove.<version>.dmg` |
| Release notes | `CHANGELOG.md` must contain one non-empty section whose full stable/alpha/beta version exactly matches the manifest |
| Installed updates | Sparkle 2 uses one signed public appcast, EdDSA-signed DMGs, explicit stable/alpha/beta channels, automatic checks/downloads, and user-invoked update actions |
| Homebrew | A public personal tap receives a fixed-version, SHA-256-pinned Cask only after the matching GitHub Release is public |

**Note:** Apple reserves customer distribution and notarization for paid Developer ID certificates. The free Apple Development identity is for development and testing; Personal Team provisioning profiles, if generated or embedded, expire after 7 days. This is an unsupported self-hosted distribution compromise, not official free distribution. Right-click → Open is Apple's official guidance for unidentified developers; the `xattr` quarantine removal is a project operational workaround, not an Apple-endorsed method. See [Apple Membership Comparison](https://developer.apple.com/support/compare-memberships/), [Developer ID](https://developer.apple.com/support/developer-id/), and [Apple Support — Open apps from unidentified developer](https://support.apple.com/en-us/102445).

---

## 11. Acceptance Criteria (MVP and Release)

AC-01 through AC-17 define MVP product acceptance. AC-18 is the separate first-public-release acceptance criterion and does not block MVP feature implementation.

| ID | Criterion | Source |
|----|-----------|--------|
| AC-01 | User can create a portal by dragging a rectangle on the desktop and choosing a folder | FR-01 |
| AC-02 | Portal displays folder contents as an icon grid with file names and icons | FR-02 |
| AC-03 | Single-click selects; Command-click toggles; Shift-click extends range | FR-04 |
| AC-04 | Double-click file opens with its default app; an ordinary directory navigates within the tab; Back never crosses the mapped root | FR-05 |
| AC-05 | Space invokes Quick Look for selected items | FR-06 |
| AC-06 | Portal supports adding, switching, closing, and moving multiple tabs; each tab maps one folder, the resulting order and selected tab survive restart, and closing the last tab prompts before removing the portal | FR-03 |
| AC-07 | Portal frames persist across app restart and restore on the menu-bar primary display | FR-07, FR-10 |
| AC-08 | All Portal frames follow the menu-bar primary display after disconnect/reconnect or a primary-display switch; fitting frames retain left/top point offsets and overflow uses new right-hand columns | FR-08, FR-10 |
| AC-09 | Portal frames restore correctly after resolution/scaling change | FR-08 |
| AC-10 | Portal coexists with Spaces and Stage Manager without permanent eviction | G-1; Spike 0.1 product gate |
| AC-11 | The app binary declares macOS 26.0 as its minimum system; every Portal uses the stable static translucent background without changing per-Portal tint, and Reduce Transparency uses the opaque accessibility surface | FR-12, FR-13 |
| AC-12 | The static Portal surface remains visually stable while switching Spaces, preserves active control contrast when the Portal loses focus, and restores global transparency plus each Portal's independent tint after restart | FR-12 |
| AC-13 | Folder contents update automatically when files are added/removed | FR-15, FR-16 |
| AC-14 | Command-Delete moves the selected items to Trash, invalidates Quick Look immediately, and reports a recycle failure | FR-26 |
| AC-15 | App is a menu-bar utility with no Dock icon | FR-11 |
| AC-16 | The CI and release artifact build for Apple Silicon (`arm64`) and reject an unexpected architecture | Distribution target |
| AC-17 | Folder creation and re-mapping accept only resolved directories on internal fixed local storage and reject removable, ejectable, external, and network-volume locations without persisting partial state | FR-19 |
| AC-18 | Spike 0.6 validates the selected signed DMG installation and launch procedure on the supported test matrix, and the verified steps are documented | Spike 0.6 release gate |
| AC-19 | A pinned Portal cannot be dragged or resized by the user, restores that state after relaunch, and can still be relocated by display recovery | FR-20 |
| AC-20 | The selected folder's abbreviated path updates with tab changes and can be copied without reducing the persisted visible grid capacity | FR-21 |
| AC-21 | The menu hierarchy and all user-facing strings render in English, Simplified Chinese, or Traditional Chinese from the saved app-language choice after Alcove automatically restarts; Follow System uses the current macOS language and falls back to English for unsupported languages | FR-22 |
| AC-22 | Empty-space marquee selection works in both directions and Command-drag toggles against the mouse-down selection | FR-04 |
| AC-23 | Native file URL drags work from Alcove to Finder/Desktop; external drops target the current browsed directory or an ordinary folder tile, in-panel drops target ordinary folder tiles, automatic operations use Finder same-volume Move/cross-volume Copy semantics, modifiers override safely, and no transfer overwrites an existing item | FR-17, FR-26 |
| AC-24 | Advanced → Repair Panel Positions leaves every already visible non-conflicting frame unchanged, persists only repaired panels, uses distinct exposed-top fallback slots before repeating them, and leaves every panel recoverable through menu-bar Show | FR-08, FR-22, FR-23 |
| AC-25 | File and folder context menus preserve or replace selection like Finder, expose only valid native actions, keep blank-space selection unchanged, and route multi-item Finder, AirDrop, path-copy, Terminal, native Quick Look, open, compress, duplicate, and Trash actions in stable grid order. Single-item Get Info opens Finder's real information window after user-approved Automation access and reports denial; single-item Return/contextual rename edits inline, preserves the file extension selection, rejects invalid/conflicting names, cancels with Escape, and retains selection after the path changes; Duplicate uses Finder naming and selects the returned copies; Compress produces a Finder-compatible ZIP with conflict-safe naming, cancellation cleanup, no shell, and no overwrite | FR-27 |

---

## 12. MVP vs. Later

### MVP (Phase 1)
- Portal creation, display, selection, opening, Quick Look
- Multiple tabs (add, switch, close, creation-order persistence, selected-tab persistence), multiple portals, and primary-display-following multi-display recovery
- Stable display identity and frame persistence
- Static translucent Portal backgrounds on macOS 26 and macOS 27, with an opaque Reduce Transparency path
- Menu-bar management UI
- Trash selected items and copy/move file-URL drops with fail-closed conflict handling
- GitHub distribution readiness; signing mode and installation procedure remain gated by Spike 0.6

### Deferred (Post-MVP)
- Tab drag-to-reorder
- Custom icon size slider (beyond Small/Medium/Large presets)
- Additional sorting modes beyond name, modification date, and creation date
- New folder, conflict replacement/Keep Both, and file-operation undo
- Cloud drive sync status
- Custom grid layouts beyond icon grid
- Portal templates / presets
