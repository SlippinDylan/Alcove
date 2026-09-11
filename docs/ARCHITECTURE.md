# Candidate Architecture — Alcove

**Status:** This document is a pre-Phase 0 candidate baseline built from research, reference observations, and architectural inference. Any choice that depends on a Prototype Gate is provisional. Until the Phase 0 product-and-architecture gate is resolved, these choices are not immutable production constraints and must not be treated as confirmed platform behavior.

If a spike fails, Alcove may revise either the candidate architecture or the affected product scope. An untested fallback must not be used to hide or relabel a failed feasibility result. Spike 0.6 is a separate release gate: it may run alongside product development, but its signing and distribution conclusions remain provisional until resolved.

## 1. Architectural Principles

| # | Principle | Enforcement |
|---|-----------|-------------|
| P-1 | **Domain logic is UI-free** | AlcoveCore has zero AppKit/SwiftUI imports; tested without host app |
| P-2 | **Dependencies flow inward** | AlcoveCore is the single UI-free Swift package; internal feature groups within the Xcode app target enforce dependency direction in code |
| P-3 | **No force unwraps or broad casts** | All optionals handled with `guard let`/`if let`; no `as!`, no `Any`→typed casts without `as?` |
| P-4 | **Main actor for UI, explicit off-main I/O boundary** | `@MainActor` on all view/window controllers; `FolderLoadingActor` coordinates loading state while blocking file-system work crosses a dedicated, verified background execution boundary |
| P-5 | **Stale results are rejected, not applied** | Every async pipeline carries a monotonic generation counter; UI discards out-of-order completions |
| P-6 | **System-driven moves never overwrite user placement** | Display-placement state machine distinguishes user vs. system origin before writing |
| P-7 | **Prototype gates are explicit** | Window strategy, display identity/placement, Quick Look, Liquid Glass/fallback, folder observation/permissions, and signing/distribution remain provisional until their corresponding spikes are resolved |
| P-8 | **Folder-source eligibility is validated at selection boundaries** | Resolve the selected directory's hosting volume and reject removable, ejectable, or network volumes before a tab can reference it |

---

## 2. Module Boundaries & Dependency Graph

```mermaid
graph TD
    AlcoveApp[AlcoveApp<br/>App entry, menu bar, scene]
    PortalWindowing[PortalWindowing<br/>NSWindow, level, behaviors]
    PortalPresentation[PortalPresentation<br/>Chrome, tabs, glass effects]
    FileGrid[FileGrid<br/>NSCollectionView icon grid]
    QuickLookIntegration[QuickLookIntegration<br/>QLPreviewPanel responder chain]
    FolderAccess[FolderAccess<br/>Enumeration, DispatchSource, FSEvents]
    Persistence[Persistence<br/>Versioned Codable JSON, atomic I/O]
    DisplayPlacement[DisplayPlacement<br/>Normalized geometry, display UUID]
    AlcoveCore[AlcoveCore<br/>Domain models, layout math, value types]

    AlcoveApp --> PortalWindowing
    AlcoveApp --> Persistence
    AlcoveApp --> DisplayPlacement
    PortalWindowing --> PortalPresentation
    PortalWindowing --> DisplayPlacement
    PortalPresentation --> FileGrid
    PortalPresentation --> QuickLookIntegration
    FileGrid --> FolderAccess
    FileGrid --> AlcoveCore
    FolderAccess --> AlcoveCore
    Persistence --> AlcoveCore
    DisplayPlacement --> AlcoveCore
```

### Dependency Rules

1. **AlcoveCore** is the leaf — depends on nothing; no AppKit, no Foundation file I/O.
2. **Persistence** depends only on AlcoveCore. It owns serialization format and version negotiation.
3. **DisplayPlacement** depends only on AlcoveCore. It owns coordinate math and display identity.
4. **FolderAccess** depends only on AlcoveCore. It owns enumeration and file-system observation.
5. **FileGrid** depends on AlcoveCore and FolderAccess. It owns `NSCollectionView` data source and delegate.
6. **PortalPresentation** depends on FileGrid and QuickLookIntegration. It owns chrome, tab bar, and glass effects.
7. **PortalWindowing** depends on PortalPresentation and DisplayPlacement. It owns `NSWindow` lifecycle and behaviors.
8. **QuickLookIntegration** uses AppKit and QuickLookUI; it injects into the responder chain between `PortalWindow` and `NSApplication`.
9. **AlcoveApp** is the composition root — depends on everything. It owns `NSApplicationDelegate`, `NSStatusItem`, and portal lifecycle coordination.

Dependencies are acyclic and point toward AlcoveCore or an explicitly declared feature interface. Cross-feature dependencies are limited to the arrows shown above.

The module boundaries describe the intended separation of responsibilities. Modules and implementation choices marked provisional below may change when Spikes 0.1–0.5 resolve the product-and-architecture gate. Release packaging and signing remain governed separately by Spike 0.6.

---

## 3. Module Responsibilities

### 3.1 AlcoveCore

Domain models and pure layout math. Zero AppKit imports.

- `Portal` — top-level aggregate
- `FolderTab` — tab identity and folder URL reference
- `FileItem` — enumerated file/folder entry
- `SelectionState` — per-tab selection model
- `IconSize` — validated icon dimension value type
- `ColumnCount` — validated column count value type
- `GridLayout` — computes item frames from container size, icon size, column count, and spacing
- `PlacementGeometry` — captures and restores per-display frames with normalized movable-range anchors
- `PlacementStateMachine` — preserves user-confirmed home placement while emitting transient topology directives

### 3.2 AlcoveApp

App entry point and global coordination.

- `AppDelegate` — `NSApplicationDelegate`, menu-bar `NSStatusItem` lifecycle
- `PortalCoordinator` — creates/destroys portals, routes user actions
- `NewPortalOverlay` — pointer-display overlay with dashed drag rectangle, constrained to `visibleFrame`
- Info.plist: `LSUIElement = YES`, `LSBackgroundOnly = NO`

### 3.3 PortalWindowing

`NSWindow` ownership and behavior configuration.

- `PortalWindow` — provisional `NSWindow`/`NSPanel` abstraction whose concrete type and strategy are selected by Spike 0.1.
- The first candidate uses:
  - `level = CGWindowLevelForKey(.desktopIconWindow) + 1`
  - `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- The spike harness must make strategies switchable and compare `.stationary`, `.moveToActiveSpace`, `.fullScreenAuxiliary`, use or omission of `.canJoinAllSpaces`, `NSWindow` versus `NSPanel`, and whether the portal may become key.
- Final window level, collection behaviors, window class, and key-window policy are provisional until Spike 0.1 is resolved.
- Production development uses the replaceable Phase 0.1D default: key-eligible `NSWindow`, `desktopIconWindow + 1`, and `[.canJoinAllSpaces, .stationary, .ignoresCycle]`. This is an implementation starting point, not a claim that the manual WindowServer matrix passed.
- Regardless of the selected strategy, the portal must provide:
  - `isMovableByWindowBackground = true`
  - Standard resize from edges/corners
  - Frame snap to grid metrics on move/resize end
- `PortalWindowController` — manages window lifecycle, delegates to `DisplayPlacement` on frame changes

### 3.4 PortalPresentation

Visual chrome inside each portal window.

- `PortalViewController` — root view controller per portal
- `TabBarView` — horizontal tab strip with add (+), switch, close, and provisional glass-effect styling; tabs remain in creation order in MVP and drag-to-reorder is Post-MVP
- `GlassMaterialProvider` — candidate compatibility boundary for `NSGlassEffectView` on macOS 26+ and `NSVisualEffectView` on 15–25, subject to Spike 0.4
- Layout: tab bar at top, icon grid fills remaining area

### 3.5 FileGrid

`NSCollectionView`-based icon grid.

- `FileGridViewController` — owns `NSScrollView` + `NSCollectionView`
- `FileItemCell` — displays icon (`NSWorkspace.icon(forFile:)`), file name, selection highlight
- `FileGridDataSource` — bridges `FolderAccess` enumeration results to collection view items
- `FileGridDelegate` — handles selection, double-click, keyboard events, and forwards to `QuickLookIntegration`
- Selection protocol: single-click select, Command-click toggle, Shift-click range, arrow keys navigate

### 3.6 QuickLookIntegration

`QLPreviewPanel` integration via responder chain.

- A dedicated `QuickLookIntegration` responder implements `QLPreviewPanelDataSource` and `QLPreviewPanelDelegate`
- `PortalWindowController` inserts it between `PortalWindow` and the window's previous responder, then restores the exact previous link on detach
- The integration owns an ordered URL snapshot, presents on Space when selection is non-empty, and dismisses on second Space only while Alcove still owns the visible panel
- Tab switches invalidate the old URL snapshot and relinquish panel control; window teardown clears only data-source/delegate references still owned by that integration
- **Prototype gate:** responder chain behavior requires spike validation on each macOS version target

### 3.7 FolderAccess

Directory enumeration and live observation.

- `FolderEnumerator` — returns `[FileItem]` for a given URL; default ordering: directories first, then localized standard name
- `FolderLocationValidator` — resolves the selected directory's hosting volume and accepts only internal, non-removable, non-ejectable local storage; selection and re-mapping reject all other locations before persistence
- `FolderObserver` — FSEvents adapter using `FileEvents`, `WatchRoot`, and `UseCFTypes`; monitors only the active tab's mapped directory and treats records as snapshot invalidation evidence.
- `FolderLoadingActor` coordinates generation tokens, cancellation requests, and result ordering; it does not by itself put synchronous file I/O on a background thread.
- Blocking enumeration crosses an explicit background execution boundary such as a dedicated `DispatchQueue`, `OperationQueue`, or a verified asynchronous wrapper.
- Cooperative cancellation requires incremental or batched enumeration with checks at defined boundaries. A single `FileManager.contentsOfDirectory` call cannot be cancelled midway.
- Stale rejection: each enumeration carries a `Generation` counter; UI discards completions whose generation doesn't match the current one

### 3.8 DisplayPlacement

Display identity, coordinate normalization, and placement state machine.

- `DisplayIdentity` — wraps `CGDisplayCreateUUIDFromDisplayID` output (stability through disconnect/reconnect is inference, requires spike validation)
- `NormalizedAnchor` — portal origin expressed as fractions of the actual movable range within `NSScreen.visibleFrame`, after constraining the portal size
- `PlacementStore` — read/write per-portal, per-display placement records
- State machine (§6) — distinguishes user-initiated moves from system-driven evictions

### 3.9 Persistence

Versioned JSON storage with atomic replacement.

- Location: `~/Library/Application Support/Alcove/portals.json`
- Format: JSON object with `version: Int` at top level, followed by data payload
- Persistence uses versioned Codable DTOs and maps to validated domain models
- Persistence is infrastructure outside AlcoveCore (contains domain/layout only); `PortalStore`, `NSScreen` lookup, `DisplayIdentity` adapters, and file I/O remain app infrastructure
- Write strategy: write to `.tmp` file, then `FileManager.replaceItemAt` for atomic swap
- Read strategy: read file → check `version` → dispatch to appropriate decoder → return typed result or migration error
- No Core Data, no SQLite, no UserDefaults for portal state

---

## 4. Domain Models & Validated Value Types

All types live in `AlcoveCore`. No force unwraps (`!`), no broad casts (`as!`, `as Any`).

### 4.1 Portal

```swift
struct Portal: Identifiable, Sendable {
    let id: PortalID
    var tabs: [FolderTab]
    var selectedTabID: FolderTabID
    var iconSize: IconSize
    var frame: CGRect               // Slice 5; upgraded to PlacementRecord in Slice 8

    init(id: PortalID = PortalID(), tabs: [FolderTab], selectedTabID: FolderTabID,
         iconSize: IconSize = .medium, frame: CGRect) throws { ... }
}
```

### 4.2 FolderTab

```swift
struct FolderTab: Identifiable, Sendable {
    let id: FolderTabID
    var folderURL: URL           // standardized file URL (non-sandboxed, no bookmark)

    var displayName: String { folderURL.lastPathComponent }

    init(id: FolderTabID = FolderTabID(), folderURL: URL) { ... }
}
```

Sorting is not exposed in MVP. Default ordering: directories first, then localized standard name.

### 4.3 FileItem

`FileItem` is runtime state, not `Codable`. Identity is derived from the standardized URL (or a scoped file identity), not a fresh `UUID` each enumeration.

```swift
struct FileItem: Identifiable, Sendable, Hashable {
    let id: FileIdentity       // derived from standardized URL, stable across enumerations
    let url: URL
    let name: String
    let isDirectory: Bool
    let isHidden: Bool

    /// FolderAccess supplies already-validated metadata; AlcoveCore performs no file I/O.
    init(url: URL, name: String, isDirectory: Bool, isHidden: Bool) {
        self.id = FileIdentity(standardizedURL: url.standardizedFileURL)
        self.url = url.standardizedFileURL
        self.name = name
        self.isDirectory = isDirectory
        self.isHidden = isHidden
    }
}

/// Stable identity derived from standardized file URL.
struct FileIdentity: Hashable, Sendable {
    let path: String  // url.standardizedFileURL.path
}
```

Metadata beyond name and directory status (file size, modification date) is deferred; default ordering is directories first, then localized standard name.

### 4.4 SelectionState

```swift
struct SelectionState: Sendable {
    private(set) var selectedIDs: Set<FileIdentity>
    private(set) var anchorID: FileIdentity?   // for Shift-click range
    private(set) var focusID: FileIdentity?

    mutating func select(_ id: FileIdentity) { ... }
    mutating func toggle(_ id: FileIdentity, in orderedIDs: [FileIdentity]) { ... }
    mutating func extendRange(to id: FileIdentity, in orderedIDs: [FileIdentity]) { ... }
    mutating func selectAll(_ ids: [FileIdentity]) { ... }
    mutating func clear() { ... }
    mutating func reconcile(with orderedIDs: [FileIdentity]) { ... }
}
```

### 4.5 Validated Value Types

No force unwraps. Presets use a private validated path; public construction is failable.

```swift
struct IconSize: Sendable, Comparable {
    let rawValue: CGFloat

    private init(validated value: CGFloat) { self.rawValue = value }

    /// Returns nil if value is outside [32, 128].
    init?(rawValue: CGFloat) {
        guard rawValue >= 32 && rawValue <= 128 else { return nil }
        self.rawValue = rawValue
    }

    static let small  = IconSize(validated: 48)
    static let medium = IconSize(validated: 64)
    static let large  = IconSize(validated: 80)

    static func < (lhs: IconSize, rhs: IconSize) -> Bool { lhs.rawValue < rhs.rawValue }
}

Grid column count is derived from the current available width and validated
metrics during each layout pass. It is not user preference or persistence state.
```

### 4.6 PlacementRecord

Stores both preferred absolute frame (in points) and an origin normalized within the actual movable range of `visibleFrame`. Restoration policy: if the same display has unchanged geometry, prefer the saved absolute frame; if geometry changed, constrain preferred size, compute the movable range, restore the normalized anchor, then grid-snap and clamp to `visibleFrame`.

```swift
struct PlacementRecord: Sendable {
    /// Keyed by display UUID string.
    var framesByDisplay: [String: DisplayPlacementEntry]
    /// The display UUID the user last explicitly placed this portal on.
    var homeDisplayUUID: String?
}

struct DisplayPlacementEntry: Sendable {
    /// Absolute frame in points, as saved by the user.
    var absoluteFrame: CGRect
    /// NSScreen.visibleFrame used when this entry was saved.
    var referenceVisibleFrame: CGRect
    /// Origin normalized within the movable range at save time.
    var normalizedAnchor: NormalizedAnchor
    /// Preferred portal size in points (width, height).
    var preferredSize: CGSize
}

struct NormalizedAnchor: Sendable {
    /// Fractions of the window's movable range inside NSScreen.visibleFrame.
    /// x: 0.0 = leftmost origin, 1.0 = rightmost origin
    /// y: 0.0 = bottommost origin, 1.0 = topmost origin
    let x: Double
    let y: Double
}
```

---

## 5. Versioned Persistence & Migration

### 5.1 Storage Format

```json
{
  "version": 1,
  "portals": [ ... ]
}
```

All JSON keys are `snake_case`. Dates are ISO 8601.

### 5.2 Version Negotiation

| `version` value | Behavior |
|-----------------|----------|
| Matches current decoder | Decode directly |
| Lower than current | When a second schema version exists, run the explicit migration path from the stored version to current |
| Higher than current | Fail with `.unsupportedVersion(Int)`; do not attempt partial read |
| Missing or malformed | Fail with `.corruptedFile` |

### 5.3 Migration Strategy

MVP starts with a versioned v1 envelope and preserves room for future migration, but it does not build a speculative migration chain before a second schema exists. When v2 is introduced, that change must add and test the concrete v1→v2 migration using the real old and new schemas. Later migrations are explicit and sequential; the implementation shape is chosen from the needs of those schemas rather than a mock migration framework.

### 5.4 Failure Policy

| Failure | Response |
|---------|----------|
| File not found (first launch) | Return empty state; create file on first save |
| File corrupted / unreadable | Log error; present user with option to reset or restore from backup |
| Migration fails (once a migration exists) | Preserve original file as `.bak`; present a recoverable error and do not overwrite the source |
| Disk full on write | Catch `NSCocoaErrorDomain` code 640 (disk full); surface to user; do not lose in-memory state |
| Atomic replace fails | Preserve in-memory state; retry once on next save cycle |

### 5.5 Backup

When the first real migration is introduced, preserve the pre-migration file as `portals.v<N>.json.bak` before transforming it. A retention policy should be added with that migration based on actual storage and recovery requirements.

---

## 6. Portal Window & Display State Machine

### 6.1 Window States

```
┌─────────┐   user creates   ┌──────────┐   user closes   ┌───────────┐
│ (absent) │ ───────────────→ │  active   │ ──────────────→ │ destroyed │
└─────────┘                   └──────────┘                  └───────────┘
                               ▲       │
                    display    │       │ display
                    reconnected│       │ disconnected
                               │       ▼
                          ┌─────────────┐
                          │  displaced   │
                          └─────────────┘
```

### 6.2 Display Event Handling

| Event | Origin | Action |
|-------|--------|--------|
| User ends drag or live-resize session | User | Write absolute frame and normalized anchor to `framesByDisplay[currentDisplayUUID]`; update `homeDisplayUUID` |
| Display disconnected | System | If portal was on that display, move to primary screen clamped to `visibleFrame`; do **not** overwrite `framesByDisplay[disconnectedUUID]` |
| Display reconnected | System | If `framesByDisplay[reconnectedUUID]` exists, apply the same-geometry or changed-geometry restoration policy; mark portal as active on that display |
| Resolution/scaling change | System | Constrain preferred size, compute movable range, restore the normalized anchor, grid-snap, and clamp to new `visibleFrame` |
| Sleep/wake | System | Re-read `NSScreen` geometry and apply the same-geometry or changed-geometry restoration policy |
| Spaces transition | System | Desired behavior: portal remains on every Space without persisted-state mutation; the desktop-layer spike determines whether the selected window behaviors achieve this reliably |

### 6.3 User vs. System Move Distinction

The display placement state machine writes only at the end of explicitly tracked user drag and live-resize sessions. Both the drag handle and window resize edges are tracked. Window frame notifications alone are not proof of user origin — this remains spike-validated.

The `PortalWindowController` tracks a `isUserInteracting: Bool` flag:

- Set to `true` on `mouseDown` in the title bar, drag area, or resize edge.
- Set to `false` on `mouseUp`.
- All frame-change notifications while `isUserInteracting == false` are treated as system-driven and do **not** write to `framesByDisplay` (except when restoring from normalized coordinates after a resolution change).

This prevents Show Desktop, Spaces transitions, or Stage Manager reflow from overwriting the user's chosen position.

---

## 7. Placement Restoration Algorithm

### 7.1 Save (user ended drag or live-resize)

```
1. Get currentDisplay = NSScreen containing portal window
2. Get visibleFrame = currentDisplay.visibleFrame  (accounts for menu bar and Dock; safe-area behavior is verified separately)
3. Constrain portalWindow.frame.size to visibleFrame; this constrained frame is absoluteFrame
4. Compute the actual movable range:
     movableWidth = max(0, visibleFrame.width - absoluteFrame.width)
     movableHeight = max(0, visibleFrame.height - absoluteFrame.height)
5. Compute normalized anchor within that movable range:
     nx = movableWidth > 0
          ? (absoluteFrame.minX - visibleFrame.minX) / movableWidth
          : 0
     ny = movableHeight > 0
          ? (absoluteFrame.minY - visibleFrame.minY) / movableHeight
          : 0
6. Clamp nx and ny to 0...1 before storing
7. Store DisplayPlacementEntry(absoluteFrame, visibleFrame, NormalizedAnchor(nx, ny), absoluteFrame.size) in framesByDisplay[displayUUID]
8. Update homeDisplayUUID = currentDisplayUUID
```

### 7.2 Restore (display available, same geometry)

```
1. Look up DisplayPlacementEntry for displayUUID in framesByDisplay
2. Get current visibleFrame for that display
3. If visibleFrame is unchanged from save time (same origin and size):
     - Use saved absoluteFrame directly
     - Constrain size to visibleFrame, then grid-snap and clamp to visibleFrame
4. Set portalWindow.frame
```

### 7.3 Restore (display available, geometry changed)

```
1. Look up DisplayPlacementEntry for displayUUID in framesByDisplay
2. Get current visibleFrame for that display
3. Constrain preferredSize to current visibleFrame
4. Compute the actual movable range using the constrained size:
     movableWidth = max(0, visibleFrame.width - constrainedSize.width)
     movableHeight = max(0, visibleFrame.height - constrainedSize.height)
5. Restore the origin from the normalized anchor:
     ax = visibleFrame.minX + clamp(nx, 0...1) * movableWidth
     ay = visibleFrame.minY + clamp(ny, 0...1) * movableHeight
6. Form the candidate frame from the restored origin and constrained size
7. Grid-snap the candidate frame, then clamp it to visibleFrame
8. Set portalWindow.frame
```

The normalized anchor expresses the portal origin's relative position within the space in which that specific window size can actually move. It does not divide by the full display width or height. Operation order is fixed: constrain size, calculate movable range, restore origin, grid-snap, then clamp.

### 7.4 Eviction to Primary Screen

```
1. Resolve a primary screen with `NSScreen.main ?? NSScreen.screens.first`
2. If no screen is available during a transient display reconfiguration, defer eviction until the next screen-parameters notification
3. primaryFrame = resolvedScreen.visibleFrame
4. Compute clamped position: center of portal stays within primaryFrame
5. If portal width > primaryFrame.width, shrink to fit
6. Set portalWindow.frame to clamped rect
7. Do NOT write to framesByDisplay[anyUUID] — preserve home placement
```

---

## 8. Folder Enumeration & Observation Pipeline

### 8.1 Enumeration

```
User selects tab
    │
    ▼
TabController requests FolderEnumerator.enumerate(url, showHidden)
    │
    ▼
FolderLoadingActor records request generation and coordinates cancellation/result order
    │
    ▼
Dedicated background execution boundary performs blocking or incremental file-system work
    ├─ FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)
    ├─ Map each URL → FileItem (throwing; collect per-item diagnostics)
    ├─ Filter hidden files if !showHidden
    ├─ Sort: directories first, then localized standard name
    ├─ If enumeration is incremental/batched, check cancellation at item or batch boundaries
    └─ If using one synchronous contentsOfDirectory call, cancellation takes effect only before or after that call
    │
    ▼
Return [FileItem] + Generation counter + per-item diagnostics
    │
    ▼
FileGridDataSource receives result on @MainActor
    ├─ If generation != currentGeneration → discard (stale)
    └─ Else → apply diff to NSCollectionView
```

**File enumeration error policy:** Root enumeration failure (directory not found, permission denied) is fatal for that tab — surface error state. Per-item metadata errors (unreadable entries) are collected as diagnostics and surfaced if needed; accessible items are still listed.

`FolderLoadingActor` owns coordination state: request generations, cancellation intent, and result ordering. Actor isolation alone does not guarantee that synchronous file I/O runs on a dedicated background thread. The concrete enumerator must cross an explicit and tested background boundary, such as a dedicated `DispatchQueue`, `OperationQueue`, or verified asynchronous wrapper. The `@MainActor` load coordinator starts a lifecycle-bound task, requests cancellation on tab changes or teardown, and applies only the current generation.

For fine-grained cooperative cancellation, the implementation must enumerate incrementally or in batches and check cancellation at documented boundaries. `FileManager.contentsOfDirectory` is a one-shot synchronous call and cannot be interrupted midway; documentation and tests must reflect that limitation rather than promise an impossible in-call cancellation.

### 8.2 Observation

Active tab only. Idle tabs are re-enumerated on switch. Phase 0.5C7 selects FSEvents as the sole production mechanism.

```
FolderObserver.start(url)
    │
    ▼
FSEvents adapter (FileEvents + WatchRoot + UseCFTypes)
    │
    ▼
On event:
    ├─ Ordinary item flags → debounce 200ms → increment generation → full re-enumeration
    ├─ Drop/wrap/RootChanged → invalidate generation → bounded stream teardown
    │   └─ Revalidate path, supported volume, and root device/inode
    │       ├─ Missing/different identity → folderNotFound + explicit Locate Folder…
    │       └─ Same identity → start fresh stream before full re-enumeration
    └─ Apply only the current generation; events during enumeration schedule another refresh
```

Phase 0.5C7 selected FSEvents after both candidates passed local mutation, teardown, resource, multiple-observer, load, and lifecycle evidence. DispatchSource was substantially faster locally but provides directory-level invalidation only, remains attached to a moved inode after pathname replacement, and has no explicit dropped-event signal. Alcove does not need FSEvents item-level patching; its root-change and dropped/wrapped flags provide the stronger trigger for a fail-closed full rebuild. No dual-observer fallback is selected.

### 8.3 Cancellation

- Switching tabs cancels the in-flight enumeration `Task` for the previous tab.
- Closing a portal cancels all its tab `Task`s.
- `FolderObserver` completes bounded stream teardown when the tab becomes inactive.

---

## 9. NSCollectionView Ownership

```
PortalViewController
    │
    ├─ TabBarView
    │
    └─ FileGridViewController (one per portal; model replaced on tab switch)
         │
         ├─ NSScrollView
         │    └─ NSCollectionView
         │         ├─ Data source: FileGridDataSource (bridges FolderAccess → items)
         │         ├─ Delegate: FileGridDelegate (selection, double-click, keyboard)
         │         └─ Supplementary views: (none in MVP)
         │
         └─ FileItemCell (NSCollectionViewItem)
              ├─ NSImageView (icon from NSWorkspace)
              └─ NSTextField (file name, truncated with ellipsis)
```

- Each portal creates one `FileGridViewController` and reuses its collection view for every tab.
- On tab switch, the controller saves the outgoing tab's runtime selection/scroll state, replaces the grid model, and restores the incoming tab's runtime state after loading.
- Item size is computed by `GridLayout` from `IconSize`, `ColumnCount`, and the scroll view's width.
- `NSScrollView` always shows vertical scrollbar; horizontal is disabled (grid wraps to columns).

---

## 10. Quick Look Responder Chain Ownership

```
FileCollectionView
    │ Space forwards the ordered selection
    ▼
PortalWindow
    │ nextResponder
    ▼
QuickLookIntegration  (QLPreviewPanelDataSource, QLPreviewPanelDelegate)
    │ preserves the former successor
    ▼
PortalWindowController / NSApplication
```

- `QLPreviewPanel` is shared and responder-chain controlled. `QuickLookIntegration` accepts control only when its ordered selection snapshot is non-empty.
- On Space, the grid passes selected URLs in grid order. The integration obtains the shared panel, sets its data source/delegate, and calls `makeKeyAndOrderFront(nil)`; a second Space calls `orderOut(nil)` only if this integration still owns the visible panel.
- The integration assigns and clears `dataSource` and `delegate` only while it owns those references. It never clears or dismisses a panel already taken over by another responder.
- The panel shows previews for all selected items (multi-item preview with arrow navigation).
- A tab switch invalidates the outgoing selection and relinquishes control. Window close detaches the responder and clears owned panel references.
- Dismissal behavior when the portal loses key-window status remains manual/spike-validated; do not assume it always dismisses merely because the portal loses key status.

**Prototype Gate:** Automated tests verify selection ordering, explicit ownership, takeover safety, second-Space dismissal policy, and responder restoration. Actual preview rendering, carousel navigation, focus handoff, and desktop-level behavior across macOS 15–26 still require manual validation.

---

## 11. Liquid Glass Compatibility Boundary

| macOS Version | Material API | Scope |
|---------------|-------------|-------|
| 26+ | `NSGlassEffectView` / `NSGlassEffectContainerView` | Portal chrome: tab bar, navigation, control grouping |
| 15–25 | `NSVisualEffectView` (material selected by spike) | Same scope as above, visual approximation |

`NSGlassEffectView` exposes `contentView`, `cornerRadius`, `tintColor`, and `style`. `NSGlassEffectContainerView` exposes `contentView` and `spacing`. Standard controls supply interaction; `NSGlassEffectView` does not have `isInteractive` or `state` properties.

**Not applied to:**

- The file content canvas (the `NSCollectionView` area itself) — icons and file names sit on the portal's background material, not on separate glass layers.
- `FileItemCell` contents or selection highlights — icons are standard `NSImage` from `NSWorkspace`, not glass-rendered.

**Availability check pattern:**

```swift
func makePortalChrome() -> NSView {
    if #available(macOS 26.0, *) {
        return NSGlassEffectView()
    } else {
        let blur = NSVisualEffectView()
        // Material selected during spike validation
        return blur
    }
}
```

Glass effects are a visual enhancement, not a functional dependency. Spike 0.4 must verify both the macOS 26 glass path and the macOS 15 `NSVisualEffectView` path at the selected window level. If either fails, the architecture or visual scope is revised explicitly; an untested fallback is not treated as a successful gate result.

---

## 12. Concurrency, Cancellation & Stale Result Handling

### 12.1 Actor Isolation

| Actor | Scope |
|-------|-------|
| `@MainActor` | All view controllers, window controllers, `NSCollectionView` data source/delegate, `NSStatusItem` |
| `FolderLoadingActor` | Coordinates folder-load generation, cancellation intent, and result ordering; actor isolation alone is not a background-thread guarantee |
| Dedicated background executor | Runs blocking folder enumeration and persistence file I/O away from `MainActor`; pure display-placement math remains nonisolated |

### 12.2 Task Lifecycle

Uses lifecycle-bound unstructured tasks owned and cancelled by the relevant controller, with a `@MainActor` load coordinator that tracks a monotonically increasing request token. Enumeration crosses into `FolderLoadingActor` for coordination and then into an explicit background executor for blocking I/O; no claim is made that actor isolation alone changes the executor used by synchronous file-system calls.

```
PortalCoordinator.createPortal(for:)
    │
    ├─ Task { @MainActor in
    │      let controller = PortalViewController(portal: portal)
    │      window.contentView = controller.view
    │  }
    │
    └─ Task { @MainActor in
           let token = loadCoordinator.nextToken()
           let items = try await folderLoadingActor.loadUsingBackgroundExecutor(...)
           guard loadCoordinator.isActive(token) else { return }  // stale
           dataSource.apply(items, generation: token)
       }
```

### 12.3 Load Coordinator

```swift
@MainActor
final class LoadCoordinator {
    private var currentToken: Int = 0

    func nextToken() -> Int {
        currentToken += 1
        return currentToken
    }

    func isActive(_ token: Int) -> Bool {
        token == currentToken
    }
}
```

Every `FolderEnumerator` call is paired with a request token from the coordinator. Results are applied only if the token is still active at the moment of `@MainActor` application. This prevents:

- Rapid tab switches causing stale folder contents to flash.
- Display reconnect triggering a re-enumeration that arrives after a newer one.

### 12.4 Cancellation Points

| Operation | Cancellation Trigger |
|-----------|---------------------|
| Folder enumeration | Tab switch, portal close, folder path change |
| Folder observation | Tab becomes inactive, portal closes |
| Overlay drag (portal creation) | Escape key, click outside display |

The coordinator rejects every result whose token is no longer active, regardless of whether underlying synchronous I/O has already returned. If the selected enumerator is incremental or batched, it also checks cancellation at item or batch boundaries and throws `CancellationError`. A one-shot `FileManager.contentsOfDirectory` call can only observe cancellation before or after the call, not during it; cancellation tests must distinguish prompt result suppression from impossible mid-call interruption.

---

## 13. Error Taxonomy

```swift
enum AlcoveError: Error, Sendable {
    // Persistence
    case fileNotFound(path: String)
    case corruptedFile(path: String, underlyingDomain: String?, underlyingCode: Int?)
    case unsupportedVersion(Int)
    case migrationFailed(fromVersion: Int, underlyingDomain: String?, underlyingCode: Int?)
    case diskFull(path: String)

    // Folder access
    case folderNotFound(url: URL)
    case permissionDenied(url: URL, underlyingDomain: String?, underlyingCode: Int?)
    case unsupportedFolderLocation(url: URL)
    case enumerationFailed(url: URL, underlyingDomain: String?, underlyingCode: Int?)
    case itemMetadataFailed(url: URL, underlyingDomain: String?, underlyingCode: Int?)

    // Display
    case displayNotFound(uuid: String)
    case screenGone(displayUUID: String)

    // Portal lifecycle
    case portalNotFound(id: UUID)
    case tabNotFound(id: UUID)
    case lastTabClosed(portalID: UUID)
}
```

Non-Sendable `Error` values are mapped at infrastructure boundaries: preserve `NSError.domain`/`code`/`path` as Sendable failure context. Domain errors never embed a non-Sendable `Error`.

All errors are `Sendable` and carry enough context for:

1. Logging (diagnostic message).
2. User-facing presentation (localized description).
3. Recovery guidance (suggested action).

No error is silently swallowed. Every error path results in either a user-visible state (error banner per PRD §7.2) or a logged diagnostic.

---

## 14. Security & Permissions

### 14.1 Entitlements

Alcove is **non-sandboxed**. No entitlement file is required to declare `app-sandbox=false`; do not add a false sandbox entitlement.

### 14.2 Permissions Model

| Permission | Required? | Handling |
|------------|-----------|----------|
| Accessibility | No | Core interaction is within Alcove-owned windows |
| Full Disk Access | No | User selects folders via `NSOpenPanel`; non-sandboxed app has normal POSIX access |
| TCC (Desktop, Documents, Downloads) | Conditional | System may show permission dialog on first access; Alcove surfaces TCC errors explicitly, does not silently fail |
| Network | No | Zero network calls in MVP |
| Folder source | Internal fixed local storage only | Selection and re-mapping reject removable, ejectable, and network-volume locations |

### 14.3 Folder Access in Non-Sandboxed Context

Since Alcove is non-sandboxed:

- `NSOpenPanel` is selection UX; it does not grant a non-sandbox access token. Standard POSIX permissions apply — user must have read access to the target directory.
- After resolving the selected directory, validate its hosting-volume metadata. The directory is eligible only when the volume is local, internal, non-removable, and non-ejectable; reject it before creating or updating a tab otherwise.
- A standardized file URL/path is persisted directly. If the folder moves, show a missing state and offer "Locate Folder…" via `NSOpenPanel` to re-map.
- TCC-protected folders may still affect non-sandboxed apps; do not claim TCC only applies to sandboxed apps.

### 14.4 TCC Failure Reporting

When `FileManager.contentsOfDirectory` throws `NSCocoaErrorDomain` code 257 (permission denied) or `EPERM`:

1. Check if the path is under a TCC-protected location (`~/Desktop`, `~/Documents`, `~/Downloads`).
2. Display error banner: "Permission denied — <folder name>. macOS may require permission in System Settings → Privacy & Security → Files and Folders."
3. Do not prompt for Full Disk Access; explain the restriction and let the user decide.

---

## 15. Test Seams

| Module | Test Strategy | Key Seams |
|--------|--------------|-----------|
| AlcoveCore | Unit tests only; no host app | `GridLayout` output for known inputs; `IconSize`/`ColumnCount` validation; `SelectionState` transitions |
| Persistence | Unit tests with temp directory | `PortalStore.save`/`load` round-trip; version rejection; corrupted file handling; atomic write verification; real migrations added only when a second schema exists |
| DisplayPlacement | Unit tests with screen geometry value descriptors | `DisplayPlacementEntry` save/restore round-trip; zero and nonzero movable ranges; size-before-anchor ordering; grid-snap/clamp ordering; eviction logic; geometry-change recomputation |
| FolderAccess | Unit tests with temp directories | `FolderEnumerator` returns correct items; hidden file filter; directories-first ordering; stale results are suppressed; incremental cancellation is tested only if implemented; selected `FolderObserver` strategy fires on file creation and handles teardown errors |
| FileGrid | UI tests with test host | Selection behavior; double-click callback; keyboard navigation; collection view diff application |
| PortalPresentation | Snapshot tests | Tab bar rendering; glass material selection; error banner display |
| PortalWindowing | Integration tests | Spike-selected window class, level, collection behaviors, key-window policy, frame snap, and move/resize callbacks |
| QuickLookIntegration | Manual spike tests | `QLPreviewPanel` appears on Space; responder chain correct on each macOS version |
| AlcoveApp | Smoke tests | App launches; menu bar icon appears; portal creation flow end-to-end |

### 15.1 Dependency Injection Points

All external dependencies are injected via protocols:

```swift
protocol FileEnumerator {
    func contentsOfDirectory(at url: URL, keys: [URLResourceKey]?) throws -> [URL]
}

protocol WorkspaceOpening {
    func open(_ url: URL) -> Bool
}

/// Value descriptors for pure geometry; not mocked NSScreen.
protocol ScreenGeometryProvider {
    func visibleFrame(for displayUUID: String) -> CGRect?
    func displayUUID(for screenIndex: Int) -> String?
}
```

Production implementations use `FileManager.default`, `NSWorkspace.shared` (via protocol adapter — `NSWorkspace.shared` itself is not mockable), and `NSScreen` geometry. Test implementations return controlled values.

---

## 16. Prototype Gates

Spikes 0.1–0.5 form the product-and-architecture gate. Their dependent choices remain provisional until evidence is recorded and an explicit architecture or product-scope decision is made. Spike 0.6 is a separate release gate: it may run during Phase 1, but must be resolved before the first public GitHub Release. A failed gate is never converted into success by naming an untested fallback.

### 16.1 Desktop Layer Stability — Spike 0.1

**Provisional claim:** A public AppKit window strategy can keep portals above Finder desktop icons and below normal application windows without permanent eviction.

**Gate criteria:**

- A switchable harness begins with `desktopIconWindow + 1`, `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle`, but does not privilege it as final.
- Compare `.stationary`, `.moveToActiveSpace`, `.fullScreenAuxiliary`, use or omission of `.canJoinAllSpaces`, `NSWindow` versus `NSPanel`, and whether the portal may become key.
- Record Show Desktop, Spaces, Stage Manager, full-screen interaction, lock, and sleep/wake behavior on the available macOS 15 and 26 matrix.
- Select the final window strategy from measured results.

**If gate fails:** Record the failure and make an explicit product-feasibility or scope decision. Test additional public-API strategies if justified; do not silently substitute an unverified fallback.

### 16.2 Display Identity and Placement — Spike 0.2

**Provisional claim:** Display UUID, absolute frame, save-time `visibleFrame`, preferred size, and a normalized anchor within the actual movable range can restore a portal without overwriting remembered home placement.

**Gate criteria:**

- Measure display UUID behavior across disconnect/reconnect, rearrangement, resolution/scaling changes, and sleep/wake.
- Verify system-driven eviction does not overwrite the user's last explicit placement.
- Verify same geometry prefers the absolute frame; changed geometry constrains size, computes movable range, restores normalized origin, grid-snaps, then clamps.
- Record behavior for zero movable width or height and displays unavailable during transient reconfiguration.

**If gate fails:** Revise display identity matching, placement fields, or the restoration product promise based on evidence.

### 16.3 Quick Look Responder Chain — Spike 0.3

**Provisional claim:** `QLPreviewPanel` can be owned and presented from the selected desktop-window strategy.

**Gate criteria:**

- Space presents and dismisses Quick Look for single and multiple selected items.
- Verify responder ownership, explicit data-source/delegate assignment, portal key-window transitions, and cleanup.
- Test common file types on the available macOS 15 and 26 matrix.

**If gate fails:** Revise the responder-chain integration or product scope. Explicit assignment is a candidate to test, not a presumed successful fallback.

### 16.4 Liquid Glass and Compatibility Material — Spike 0.4

**Provisional claim:** `NSGlassEffectView`/`NSGlassEffectContainerView` can render appropriate portal chrome on macOS 26, while `NSVisualEffectView` can preserve layout and usable contrast on macOS 15–25.

**Gate criteria:**

- Verify both material paths at the selected desktop window level.
- Verify Reduce Transparency, Increase Contrast, readability, and equivalent control layout.
- Keep glass off the file-content canvas and individual file cells.

**If gate fails:** Revise the material boundary or visual scope explicitly; do not describe an untested fallback as validated compatibility.

### 16.5 Folder Observation and Access — Spike 0.5

**Selected mechanism:** FSEvents with `FileEvents`, `WatchRoot`, and `UseCFTypes`, using the Phase 0.5C7 snapshot-refresh and fail-closed rebuild contract.

**Gate criteria:**

- Compare `DispatchSourceFileSystemObject` and FSEvents for immediate-child changes, rename/delete, local directory replacement, teardown, event coalescing, latency, and resource cost.
- Record TCC-protected-folder, missing-directory, and symlink behavior.
- Verify folder selection rejects removable, ejectable, and network-volume locations at the boundary.
- [Resolved] Select the primary mechanism and evidence-backed recovery policy.
- Verify blocking enumeration uses an explicit background boundary; verify stale-result suppression and document actual cancellation granularity.

**If gate fails:** Revise observation scope, refresh behavior, or the affected product requirement using recorded evidence.

### 16.6 Signing, DMG, and Gatekeeper — Spike 0.6 Release Gate

**Provisional claim:** An Apple Development-signed or explicitly ad-hoc-signed DMG can support a documented self-hosted installation path.

**Gate criteria:**

- Inspect both artifacts for signatures and embedded provisioning profiles.
- Record quarantine, right-click Open, `xattr`, `spctl`, expiry, and post-expiry launch behavior on the available macOS 15 and 26 matrix.
- Choose and document the release signing strategy; the main workflow must fail closed and never silently switch to ad-hoc.

**If gate fails:** Block the first public GitHub Release and revise the distribution plan. Product implementation may continue independently.

---

## 17. Rejected Alternatives

| Alternative | Reason for Rejection |
|-------------|---------------------|
| **WidgetKit** | Cannot host scrollable, interactive file grids; limited to Button/Toggle intents; system-managed lifecycle conflicts with persistent desktop presence |
| **SwiftUI App lifecycle** | AppKit lifecycle and `NSStatusItem` selected for control over `NSWindow` level, collection behaviors, and responder chain needed for Quick Look |
| **NSCollectionView → SwiftUI List/UICollectionView** | SwiftUI `List` lacks the icon grid layout and Finder-consistent selection semantics; `UICollectionView` is iOS-only |
| **DispatchSource as the production observer** | It passed local lifecycle/load evidence and was faster, but FSEvents provides explicit root-change and dropped/wrapped-event recovery signals without requiring a second observer |
| **Security-scoped bookmarks** | MVP does not adopt them: Alcove is non-sandboxed, persists standardized paths, and relies on normal POSIX access subject to TCC and filesystem permissions |
| **App Groups / XPC / Helper** | Single-process architecture is simpler and sufficient; no cross-process communication needed |
| **Core Data / SQLite** | Portal state is a small, infrequently-written JSON document; no query language or relational model needed; atomic file replacement is simpler and safer |
| **UserDefaults** | Not suitable for structured, versioned, multi-entity state; file-based persistence allows backup, migration, and inspection |
| **Storing absolute frames only** | Candidate restoration also stores save-time `visibleFrame`, preferred size, and an origin normalized within the actual movable range; Spike 0.2 validates whether this is sufficient for multi-display stability |
| **Reading Finder desktop icon size via private API** | No public API exists (research conclusion, not Apple-confirmed); app-owned `IconSize` presets are explicit and stable; no private Finder preference investigation proposed |
| **Sandboxed distribution** | Non-sandboxed allows normal POSIX file access without security-scoped bookmarks; simplifies implementation; distribution via GitHub with documented quarantine removal |
