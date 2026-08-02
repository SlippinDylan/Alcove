# Phase 0.1A — Claude Implementation Report

## 1. Files Created

| File | Purpose |
|------|---------|
| `spikes/desktop-window/Sources/WindowStrategy.swift` | Strategy enum with level, behavior, labels |
| `spikes/desktop-window/Sources/DiagnosticsView.swift` | Live diagnostics display (NSTextField) |
| `spikes/desktop-window/Sources/ExperimentWindowController.swift` | Window lifecycle, delegate, notifications |
| `spikes/desktop-window/Sources/AppDelegate.swift` | Menu bar, strategy switching, window management |
| `spikes/desktop-window/Sources/main.swift` | Application entry point |
| `spikes/desktop-window/build.sh` | Deterministic build script |
| `docs/SPIKE_DESKTOP_WINDOW.md` | Spike evidence document |
| `.agent/results/phase-0.1a-claude-result.md` | This report |

No existing files were modified or deleted.

## 2. Project Form and Rationale

**Form:** `swiftc` + deterministic `.app` build script.

**Why:** A single `swiftc` invocation is the most deterministic and dependency-free form for a disposable harness. It avoids Xcode project complexity and SwiftPM's limitations with `.app` bundles. The build command is a single inspectable line; the output is a plain `.app` bundle.

## 3. Build Command

```bash
cd spikes/desktop-window && bash build.sh
```

Underlying compile command:

```bash
xcrun swiftc -target arm64-apple-macosx15.0 \
    -framework AppKit -framework CoreGraphics -framework Foundation \
    -o build/AlcoveSpike.app/Contents/MacOS/AlcoveSpike \
    Sources/WindowStrategy.swift Sources/DiagnosticsView.swift \
    Sources/ExperimentWindowController.swift Sources/AppDelegate.swift \
    Sources/main.swift
```

## 4. Build Exit Result

**Pass.** Exit code 0. No errors, no warnings. Binary produced: `AlcoveSpike` Mach-O arm64, 185KB. Ad-hoc signed with `xcrun codesign --force --sign -`.

## 5. Automated Tests/Checks Actually Run

| Check | Result |
|-------|--------|
| `xcrun swiftc` compilation | **Pass** — exit code 0, no errors, no warnings |
| Binary existence | **Pass** — `AlcoveSpike` Mach-O arm64, 185KB |
| Info.plist `LSUIElement` | **Pass** — `<key>LSUIElement</key><true/>` |
| Code signing | **Pass** — ad-hoc, confirmed via `xcrun codesign -dv` |
| Source inspection: no force unwraps | **Pass** — `!flag` is logical negation, not a force unwrap |
| Source inspection: no `as!` casts | **Pass** |
| Source inspection: no swallowed errors | **Pass** — all delegate/notification handlers are void, no throwing paths |
| Modification boundary | **Pass** — all 8 created files are within the allowed boundary |

## 6. Manual Tests Not Run

All GUI-interactive tests remain unverified:

- Level relative to Finder desktop icons
- Normal window coverage
- Click, move, resize behavior
- Space switching
- Show Desktop
- Mission Control
- Stage Manager
- Full-screen applications
- Lock/unlock
- Sleep/wake
- Diagnostics value accuracy
- Menu shortcut functionality
- Window recreation lifecycle

**Reason:** These tests require real macOS GUI interaction on hardware. They cannot be automated by a headless agent. They must be performed manually or by an agent with GUI access.

## 7. Known Issues

1. **No automated GUI assertions.** Compilation and artifact checks passed, but Claude did not execute GUI interaction tests.
2. **arm64 only.** Universal binary deferred to production.
3. **No NSPanel comparison.** Both strategies use NSWindow.
4. **No key-window eligibility control.** Both strategies allow key-window.
5. **No `.moveToActiveSpace` or `.fullScreenAuxiliary` strategies.**
6. **Dark material only.** No light-mode or Reduce Transparency adaptation.
7. **Limited reactivation path.** With `LSUIElement = YES` and no status item, there is no Dock or normal Command-Tab entry after the app deactivates.

## 8. Three Areas of Least Confidence

1. **Window level behavior at desktop-icon layer.** `desktopIconWindow + 1` is a reference-project observation, not an Apple-guaranteed Alcove strategy. Its behavior relative to Finder icons, Show Desktop, and Mission Control is completely unverified.
2. **NSVisualEffectView rendering at the candidate window level.** The `.behindWindow` blending mode with `.dark` material at `desktopIconWindow + 1` has not been visually verified. It may have unexpected transparency or rendering artifacts.
3. **Diagnostics refresh completeness.** The diagnostics view reads from `NSWindow` and `NSScreen` properties, but some values (like `NSScreen.frame` during Space transitions) may not update in time or may reflect stale state during rapid system transitions.

## 9. Modification Boundary Compliance

**Strictly followed.** All created files are within the allowed paths:

- `spikes/desktop-window/` (5 source files, 1 build script)
- `docs/SPIKE_DESKTOP_WINDOW.md`
- `.agent/results/phase-0.1a-claude-result.md`

No existing files were modified, deleted, or renamed. No `.engramory-memory/`, `HANDOFF.md`, baseline documents, `README.md`, or other project files were touched.

## 10. Spike 0.1 Completion Statement

**The full Spike 0.1 remains incomplete.** Phase 0.1A created a buildable harness with two strategies and documented the required future comparisons, but:

- Zero manual GUI tests have been executed.
- Only 2 of 6+ required strategy comparisons are implemented.
- No evidence has been recorded for any system transition behavior.
- No architecture or product-scope decision has been made.

Phase 0.1A is a bootstrap, not a resolution.
