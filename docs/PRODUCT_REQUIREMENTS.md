# Product Requirements — Alcove

## 1. Product Overview

Alcove is a native macOS menu-bar utility that creates movable, resizable desktop-layer folder portals. Each portal displays the contents of a mapped directory on the Mac's internal, fixed local storage as a scrollable native icon grid. Portals support multiple tabs, Finder-consistent selection and interaction, and Quick Look integration.

Alcove is **not** a Finder replacement. It does not provide directory navigation, file management mutations, or a full desktop shell. It is a focused read-only view into folders the user chooses, displayed on the desktop layer below normal application windows.

---

## 2. Goals

| ID | Goal |
|----|------|
| G-1 | Provide persistent desktop-layer folder portals that survive display topology changes, Spaces, Stage Manager, sleep/wake, and resolution adjustments |
| G-2 | Match Finder's selection and opening semantics for familiar, low-friction interaction |
| G-3 | Offer Quick Look for selected items without leaving the portal |
| G-4 | Support multiple independent portals across multiple displays |
| G-5 | Adopt Liquid Glass on macOS 26 while remaining fully functional on macOS 15 |

## 3. Non-Goals (MVP)

| ID | Non-Goal | Rationale |
|----|----------|-----------|
| NG-1 | In-portal directory navigation | Folders open in Finder; Alcove is a viewport, not a file browser |
| NG-2 | File mutations (rename, trash, new folder, move, copy) | Read-only MVP; reduces scope and permission surface |
| NG-3 | Drag-in file imports | Mutation; deferred to post-MVP |
| NG-4 | Drag-out from portals | Under investigation; deferred |
| NG-5 | WidgetKit widgets | Alcove is a windowed utility, not a widget |
| NG-6 | Finder extension or Finder integration beyond NSWorkspace | Out of scope |
| NG-7 | Cloud drive sync status indicators | Deferred; adds complexity with provider-specific APIs |
| NG-8 | Custom file preview/rendering inside the grid | Native icon grid only; Quick Look handles preview |
| NG-9 | Folders on removable, ejectable, or network volumes | Alcove supports folders on the Mac's internal, fixed local storage only |

---

## 4. Personas & Use Cases

### Persona: Developer / Power User
- Keeps project folders, Downloads, and reference material visible on desktop
- Uses multiple displays; portals must survive display disconnect/reconnect
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
| UC-8 | Unplug a display, replug it, and see portals restored to their remembered positions |
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

Selection state is per-tab. Changing tabs preserves each tab's selection independently.

Return is reserved by Finder for rename; since Alcove MVP is read-only, Return is a no-op. Tab/Shift-Tab item cycling is not included.

### 5.2 Opening

| Action | Behavior |
|--------|----------|
| Double-click file | Open with default application via `NSWorkspace` |
| Double-click folder | Open in Finder via `NSWorkspace.open(folderURL)` |
| ⌘↓ (Command-Down) | Open selected item — same as double-click |
| ⌘O (Command-O) | Open selected item — same as double-click |

### 5.3 Quick Look

| Action | Behavior |
|--------|----------|
| Space (with selection) | Present `QLPreviewPanel` for the selected item(s) |
| Space (no selection) | No-op |
| Space (during Quick Look) | Intended to dismiss Quick Look; exact behavior is resolved by the Quick Look spike |

Quick Look follows the responder chain. The portal window owns the Quick Look responder integration.

### 5.4 Portal Creation Flow

1. User activates portal creation from the menu bar (clicks Alcove icon → "New Portal")
2. A transparent overlay appears on the pointer's current display
3. A dashed `3×1` portal appears immediately. Its card, title control, item slots, and bottom path row are previewed as dashed outlines using the Medium preset.
4. Dragging changes columns and rows at half-cell thresholds: partial progress remains a translucent candidate until the next whole capacity is committed.
5. On mouse-up, Alcove immediately persists and presents an empty Portal; creation does not open a folder chooser.
6. The empty Portal shows a Choose Folder action in its content area. That action opens the standard directory-only `NSOpenPanel`.
7. Alcove validates that the selected folder is on the Mac's internal, fixed local storage; removable, ejectable, and network-volume locations are rejected with an explanation.
8. An eligible folder becomes the first selected tab. Cancelling or rejecting the choice leaves the empty Portal intact.
9. The committed whole `columns × rows` capacity is persisted; its physical frame is derived from the active icon and text metrics.

### 5.5 Tab Management

| Action | Behavior |
|--------|----------|
| Click tab | Switch to that tab's folder |
| Settings → Folders → Add Folder… | Add a new tab (opens folder chooser) |
| Settings → Folders → Remove current folder | Remove the selected tab; if last tab, prompt to remove the portal (never silently destroy it) |
| Settings → Style | Choose Small, Medium, or Large with a three-step slider, and choose one of five background levels with a five-step slider |
| Settings → Folders → Remove Panel | Remove the complete Portal from the destructive action card at the bottom |
| Tab title | Defaults to the mapped folder name |

Tabs appear as small folder-name capsules inside one larger, horizontally
centered capsule without dividers. The selected folder receives the inner
capsule emphasis. Per-tab close and add buttons are intentionally omitted;
editing actions open from the fixed trailing settings icon in a separate centered
settings window. A standard close-only titlebar remains above a native preference-style toolbar;
an explicit system separator divides the Folders and Style navigation from the lower content.
The Folders section shows a Glass Add Folder button in its heading and
one abbreviated folder path per native table row, with a trailing drag indicator and borderless
remove action. Dropping a row performs one atomic reorder with native gap feedback. Remove Panel
lives in a separate descriptive destructive card at the bottom of the same page.

The fixed leading pin button persists per Portal. Pinning disables user-driven dragging and
resizing while leaving tab, file, Quick Look, settings, and display-recovery
interactions available. A dedicated bottom row reserves space below the file grid and shows the
selected folder's path in a capsule spanning the row's available width, abbreviating the current home directory as `~`; its copy
button writes the displayed path to the clipboard. Empty Portals keep the row's layout space but
do not display a path capsule.

### 5.6 Portal Window Behavior

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
| FR-02 | Display folder contents as Finder-style icon tiles with one outlined object space containing padded icon and title regions, separate icon/title selection treatments, and a title that wraps to at most two lines; default ordering is directories first, then localized standard name. Layout is continuous row-major order: widening pulls the next lower-row items into the preceding row, and narrowing pushes trailing items into following rows. | MVP |
| FR-03 | Support adding, switching, closing, and moving folder tabs up or down per portal; persist the resulting order and the currently selected tab. Closing the last tab prompts to remove the portal. | MVP |
| FR-04 | Finder-consistent selection (single, Command, Shift, keyboard) | MVP |
| FR-05 | Double-click file opens with default app; double-click folder opens in Finder via NSWorkspace.open(folderURL) | MVP |
| FR-06 | Quick Look via Space key through responder chain | MVP |
| FR-07 | Portal frames persist across app restarts | MVP |
| FR-08 | Portal frames restore correctly after display topology changes | MVP |
| FR-09 | Multiple portals supported simultaneously | MVP |
| FR-10 | Multiple displays supported | MVP |
| FR-11 | Menu-bar icon with portal management menu | MVP |
| FR-12 | Liquid Glass on macOS 26 for the centered folder-tab control group; each portal independently selects and persists one of five background levels on the same always-active frosted content material | MVP |
| FR-13 | NSVisualEffectView fallback on macOS 15–25 | MVP |
| FR-14 | Folder enumeration runs across an explicit background execution boundary, rejects stale results, and honors cancellation at real incremental or batch boundaries when the selected enumeration API permits it | MVP |
| FR-15 | Observe content changes for the active tab's mapped directory. The concrete observation mechanism is selected by Spike 0.5. | MVP |
| FR-16 | Automatic grid refresh when folder contents change | MVP |
| FR-17 | Drag-out from portals | Investigate |
| FR-19 | Accept mapped folders only when their resolved location is on the Mac's internal, fixed local storage; reject removable, ejectable, and network-volume locations before creating or remapping a tab | MVP |
| FR-20 | Persist a per-Portal pinned state that disables user movement and resizing without blocking system placement recovery | MVP |
| FR-21 | Show the selected folder path in a reserved bottom capsule, abbreviate the home directory as `~`, and provide a clipboard copy action | MVP |
| FR-22 | The menu bar lists New Portal, each Portal with Show/Hide commands, application Settings, and Quit. Application Settings provides General and About categories; General controls launch at login, and About shows the bundled app icon, version/build, and copyright. All user-facing UI uses English, Simplified Chinese, or Traditional Chinese according to the current system language, with English fallback | MVP |

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

The table below is the current release candidate, not a confirmed final-user distribution path. Spike 0.6 may run in parallel with MVP implementation, but must resolve the Apple Development and ad-hoc artifact behavior before the first public GitHub Release. Until then, no document may claim free Apple Development signing is a validated end-user distribution solution.

| Aspect | Detail |
|--------|--------|
| PR builds | Unsigned; CI test gate only |
| Main branch releases | Provisional Apple Development candidate: imported P12 in CI, not notarized; final signing mode is selected by Spike 0.6 |
| First launch / quarantine | Spike 0.6 determines and documents the verified steps; right-click → Open and `sudo xattr -rd com.apple.quarantine /Applications/Alcove.app` are candidates to test, not assumed universal requirements |
| DMG packaging | Standard DMG with app bundle and Applications symlink |
| GitHub Releases | Tagged releases with DMG attached |
| Explicit fallback workflow | Separately invoked ad-hoc signing (`codesign -s -`); the main release never switches signing modes automatically |

**Note:** Apple reserves customer distribution and notarization for paid Developer ID certificates. The free Apple Development identity is for development and testing; Personal Team provisioning profiles, if generated or embedded, expire after 7 days. This is an unsupported self-hosted distribution compromise, not official free distribution. Right-click → Open is Apple's official guidance for unidentified developers; the `xattr` quarantine removal is a project operational workaround, not an Apple-endorsed method. See [Apple Membership Comparison](https://developer.apple.com/support/compare-memberships/), [Developer ID](https://developer.apple.com/support/developer-id/), and [Apple Support — Open apps from unidentified developer](https://support.apple.com/en-us/102445).

---

## 11. Acceptance Criteria (MVP and Release)

AC-01 through AC-17 define MVP product acceptance. AC-18 is the separate first-public-release acceptance criterion and does not block MVP feature implementation.

| ID | Criterion | Source |
|----|-----------|--------|
| AC-01 | User can create a portal by dragging a rectangle on the desktop and choosing a folder | FR-01 |
| AC-02 | Portal displays folder contents as an icon grid with file names and icons | FR-02 |
| AC-03 | Single-click selects; Command-click toggles; Shift-click extends range | FR-04 |
| AC-04 | Double-click file opens with default app; double-click folder opens in Finder via NSWorkspace.open(folderURL) | FR-05 |
| AC-05 | Space invokes Quick Look for selected items | FR-06 |
| AC-06 | Portal supports adding, switching, closing, and moving multiple tabs; each tab maps one folder, the resulting order and selected tab survive restart, and closing the last tab prompts before removing the portal | FR-03 |
| AC-07 | Portal frame persists across app restart and restores to the correct display | FR-07, FR-10 |
| AC-08 | Portal frames restore correctly after display disconnect/reconnect | FR-08, FR-10 |
| AC-09 | Portal frames restore correctly after resolution/scaling change | FR-08 |
| AC-10 | Portal coexists with Spaces and Stage Manager without permanent eviction | G-1; Spike 0.1 product gate |
| AC-11 | App runs on macOS 15 with NSVisualEffectView materials | FR-13 |
| AC-12 | App uses Liquid Glass on macOS 26 for the centered folder-tab capsule group, preserves active visual contrast when the portal loses focus, and restores each portal's independently selected frosted-background transparency after restart | FR-12 |
| AC-13 | Folder contents update automatically when files are added/removed | FR-15, FR-16 |
| AC-14 | No file mutations (rename, trash, new folder) are possible through the portal | NG-2 |
| AC-15 | App is a menu-bar utility with no Dock icon | FR-11 |
| AC-16 | Universal binary (arm64 + x86_64) builds and runs on both architectures | Distribution target |
| AC-17 | Folder creation and re-mapping accept only resolved directories on internal fixed local storage and reject removable, ejectable, external, and network-volume locations without persisting partial state | FR-19 |
| AC-18 | Spike 0.6 validates the selected signed DMG installation and launch procedure on the supported test matrix, and the verified steps are documented | Spike 0.6 release gate |
| AC-19 | A pinned Portal cannot be dragged or resized by the user, restores that state after relaunch, and can still be relocated by display recovery | FR-20 |
| AC-20 | The selected folder's abbreviated path updates with tab changes and can be copied without reducing the persisted visible grid capacity | FR-21 |
| AC-21 | The menu hierarchy and all user-facing strings render in English, Simplified Chinese, or Traditional Chinese from the current macOS language, with unsupported languages falling back to English | FR-22 |

---

## 12. MVP vs. Later

### MVP (Phase 1)
- Portal creation, display, selection, opening, Quick Look
- Multiple tabs (add, switch, close, creation-order persistence, selected-tab persistence), multiple portals, multiple displays
- Stable display identity and frame persistence
- Liquid Glass (macOS 26) and NSVisualEffectView (macOS 15–25) compatibility
- Menu-bar management UI
- Read-only: no mutations
- GitHub distribution readiness; signing mode and installation procedure remain gated by Spike 0.6

### Deferred (Post-MVP)
- Tab drag-to-reorder
- Drag-out investigation (FR-17)
- Custom icon size slider (beyond Small/Medium/Large presets)
- Sorting UI (beyond default directories-first, localized-name ordering)
- File mutations (rename, trash, new folder)
- Drag-in file imports
- Cloud drive sync status
- Custom grid layouts beyond icon grid
- Portal templates / presets
