# Spike 0.1 — Desktop Window Behavior

Status: In Progress — Phase 0.1A bootstrap only

---

## 1. Goal

This Phase 0.1A spike validates whether a bounded implementation agent can:

- create a correct small macOS project using native Swift and AppKit;
- use public AppKit APIs to configure window level, collection behavior, and visual effects;
- implement two switchable window strategies (Normal Baseline and Desktop Candidate);
- build the result deterministically; and
- honestly distinguish automated verification from manual verification.

This does **not** resolve or complete Spike 0.1. The full spike requires manual testing across Show Desktop, Spaces, Stage Manager, full-screen apps, lock, and sleep/wake on real hardware.

---

## 2. Project Form

**Form:** `swiftc` + deterministic `.app` build script.

**Why chosen:** A single `swiftc` invocation with an explicit build script is the most deterministic, inspectable, and dependency-free form for a disposable harness. It avoids Xcode project complexity and SwiftPM's `.app` bundling limitations. The build command is a single line; the output is a plain `.app` bundle with no hidden build system state.

---

## 3. Project Structure

```text
spikes/desktop-window/
├── Sources/
│   ├── WindowStrategy.swift          — Strategy enum with level, behavior, labels
│   ├── DiagnosticsView.swift         — Live diagnostics display (NSTextField)
│   ├── ExperimentWindowController.swift — Window lifecycle, delegate, notifications
│   ├── AppDelegate.swift             — Menu bar, strategy switching, window management
│   └── main.swift                    — Application entry point
├── build.sh                          — Deterministic build script
└── build/                            — Generated build output (currently untracked)
    └── AlcoveSpike.app/
```

---

## 4. Build and Run

### Build Command

```bash
cd spikes/desktop-window
bash build.sh
```

The script runs:

```bash
xcrun swiftc \
    -target arm64-apple-macosx15.0 \
    -framework AppKit \
    -framework CoreGraphics \
    -framework Foundation \
    -o build/AlcoveSpike.app/Contents/MacOS/AlcoveSpike \
    Sources/*.swift
```

Then creates `Info.plist` (with `LSUIElement = YES`), `PkgInfo`, and ad-hoc code-signs the bundle via `xcrun codesign`.

### Run Command

```bash
open spikes/desktop-window/build/AlcoveSpike.app
```

---

## 5. Window Strategies

### Strategy A: Normal Baseline

- Window level: `.normal` (default `NSWindow.Level`)
- Collection behavior: none (default)
- Purpose: comparison control only

### Strategy B: Desktop Candidate

- Window level: `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)`
- Collection behavior: `[.canJoinAllSpaces, .stationary, .ignoresCycle]`
- Purpose: initial Phase 0.1 candidate — **not final or selected production behavior**

Both strategies use:
- `NSWindow` (not `NSPanel`) — NSWindow vs NSPanel comparison is deferred to the full spike
- Titleless style (`titlebarAppearsTransparent = true`, `titleVisibility = .hidden`)
- Translucent background via `NSVisualEffectView` (material: `.dark`, blending: `.behindWindow`)
- `isMovableByWindowBackground = true`
- Standard resizable style mask

---

## 6. Required Operations

All operations are available via menu commands (⌘ shortcuts):

| Operation | Shortcut | Implementation |
|-----------|----------|----------------|
| Switch to Normal Baseline | ⌘1 | Tears down current window, creates new with `.normal` level |
| Switch to Desktop Candidate | ⌘2 | Tears down current window, creates new with desktop candidate level |
| Activate / Make Key | ⌘A | `NSApp.activate(ignoringOtherApps:)` + `makeKeyAndOrderFront` |
| Close Window | ⌘W | Closes window, nils controller reference |
| Recreate Window | ⌘N | Closes existing (if any), creates fresh controller + window |
| Quit | ⌘Q | Standard `NSApplication.terminate` |

Closing and recreating work without dangling/deallocated controller issues because:
1. `AppDelegate` holds a strong reference to the `ExperimentWindowController`.
2. `closeWindow()` explicitly nils the reference after closing.
3. `recreateWindow()` closes, nils, then creates a fresh instance.

---

## 7. Diagnostics

The window displays these live values, refreshed on every delegate/notification event:

| Value | Source |
|-------|--------|
| Current strategy name | `WindowStrategy.rawValue` |
| Current window type | Runtime `type(of: NSWindow)` |
| Window level (numeric) | `NSWindow.level.rawValue` |
| Collection behavior | `NSWindow.collectionBehavior` flags |
| `isKeyWindow` | `NSWindow.isKeyWindow` |
| `isMainWindow` | `NSWindow.isMainWindow` |
| Window frame | `NSWindow.frame` |
| Screen frame | `NSScreen.frame` |
| Visible frame | `NSScreen.visibleFrame` |
| Display ID | `NSScreen.deviceDescription["NSScreenNumber"]` cast to `CGDirectDisplayID` |
| Activation policy | `NSApplication.activationPolicy` |

### Logged Events

All events are logged to stdout with timestamps:

- `windowDidBecomeKey`
- `windowDidResignKey`
- `windowDidBecomeMain`
- `windowDidResignMain`
- `windowDidMove`
- `windowDidResize`
- `windowDidChangeScreen`
- `applicationDidBecomeActive`
- `applicationDidResignActive`
- `didChangeScreenParameters`
- `windowWillClose`

---

## 8. Automated Verification Actually Executed

| Check | Result |
|-------|--------|
| `xcrun swiftc` compilation (arm64, macOS 15 target) | **Pass** — exit code 0, no errors, no warnings |
| Build exit code 0 | **Pass** |
| Binary exists in `.app` bundle | **Pass** — `AlcoveSpike` Mach-O arm64, 185KB |
| Info.plist contains `LSUIElement = YES` | **Pass** |
| Ad-hoc code signing | **Pass** — `xcrun codesign --force --sign -`, confirmed `flags=0x2(adhoc)` |
| Source files contain no force unwraps | **Verified by inspection** — `!flag` is logical negation, not a force unwrap |
| Source files contain no `as!` casts | **Verified by inspection** |
| Modification boundary respected | **Verified by inspection** — only files within allowed paths |

---

## 9. Manual Verification Not Yet Executed

The following require real macOS GUI interaction and **cannot** be verified by headless automation:

| Test | Status |
|------|--------|
| Level relative to Finder desktop icons | **Unverified** |
| Normal application windows cover the portal | **Unverified** |
| Clicking on window (focus, events) | **Unverified** |
| Moving the window | **Unverified** |
| Resizing the window | **Unverified** |
| Space switching (portal persists on all Spaces) | **Unverified** |
| Show Desktop (F11 / trackpad gesture) | **Unverified** |
| Mission Control | **Unverified** |
| Stage Manager | **Unverified** |
| Full-screen applications | **Unverified** |
| Lock screen | **Unverified** |
| Sleep / wake | **Unverified** |
| Diagnostics values update correctly | **Unverified** |
| Menu shortcuts all functional | **Unverified** |
| Window recreation lifecycle | **Unverified** |

---

## 10. Known Issues

1. **No automated GUI assertions.** Compilation and artifact checks passed, but Claude did not execute GUI interaction tests.
2. **Single architecture.** Build targets `arm64` only. Universal binary (arm64 + x86_64) is deferred to production.
3. **No NSPanel comparison.** Both strategies use `NSWindow`. The `NSWindow` vs `NSPanel` comparison is a required future spike item.
4. **No key-window eligibility control.** Both strategies allow the window to become key. The "allow vs prohibit key-window" comparison is a required future spike item.
5. **No `.moveToActiveSpace` or `.fullScreenAuxiliary` strategies.** These are required future comparison items for the full spike.
6. **Diagnostics update on move/resize may lag** during rapid interaction due to notification coalescing.
7. **Limited reactivation path.** With `LSUIElement = YES` and no status item, the app has no Dock or normal Command-Tab entry. Recreate works from the application menu while it remains active, but reactivation after closing and deactivating remains unverified.
8. **Dark material only.** No light-mode or accessibility (Reduce Transparency) adaptation.

---

## 11. Strategies Still Required for Full Spike 0.1

The full spike must compare these additional combinations:

| # | Comparison | Status |
|---|-----------|--------|
| 1 | `.stationary` behavior | Candidate implemented; manual testing pending |
| 2 | `.moveToActiveSpace` behavior | **Not implemented** |
| 3 | `.fullScreenAuxiliary` behavior | **Not implemented** |
| 4 | With vs without `.canJoinAllSpaces` | **Not implemented** (only "with" is tested) |
| 5 | `NSWindow` vs `NSPanel` | **Not implemented** |
| 6 | Key-window eligibility (allow vs prohibit) | **Not implemented** |

---

## 12. Phase 0.1 Is Not Complete

**Phase 0.1 is not complete.** This document records only the Phase 0.1A bootstrap:

- The harness is built and source-verified but not runtime-verified.
- Only 2 of the required 6+ strategy comparisons are implemented.
- Zero manual GUI tests have been executed.
- No evidence has been recorded for Show Desktop, Spaces, Stage Manager, full-screen, lock, or sleep/wake behavior.
- No architecture or product-scope decision can be made from this phase alone.

The full Spike 0.1 requires:
1. Implementing additional strategy switches (at minimum: `.moveToActiveSpace`, `.fullScreenAuxiliary`, with/without `.canJoinAllSpaces`, `NSPanel`, key-window eligibility).
2. Manually testing every strategy across all required system transitions.
3. Recording observations in this document.
4. Selecting the evidence-backed window configuration (or declaring feasibility failure).

---

## 13. Future Comparison List (Minimum Required)

For the full Spike 0.1, the harness must support runtime switching between at least:

- `.stationary` (implemented as part of Desktop Candidate)
- `.moveToActiveSpace`
- `.fullScreenAuxiliary`
- With `.canJoinAllSpaces` (implemented)
- Without `.canJoinAllSpaces`
- `NSWindow` (implemented)
- `NSPanel`
- Key-window allowed (implemented)
- Key-window prohibited (via `NSWindow.Level` or `NSPanel` style)

Each combination must be tested against:
- Finder desktop icon layer ordering
- Normal application window coverage
- Click, move, resize behavior
- Space switching
- Show Desktop
- Mission Control
- Stage Manager
- Full-screen applications
- Lock/unlock
- Sleep/wake
