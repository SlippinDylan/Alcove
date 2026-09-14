Status: In Progress — Phase 0.4A material boundary bootstrap only

# Spike 0.4 — Material Compatibility Boundary

## Scope

Phase 0.4A is a disposable AppKit harness for reviewing the candidate material boundary. It constructs equivalent portal chrome through three paths while keeping a plain file-content canvas outside every effect:

- automatic macOS 26 Glass;
- forced `NSVisualEffectView` fallback; and
- an explicit opaque path when Reduce Transparency is enabled.

It does not select a production material, validate pixels, or complete Spike 0.4.

## Structure

```text
spikes/materials/
├── Sources/
│   ├── AppDelegate.swift
│   ├── MaterialChromeView.swift
│   ├── MaterialModel.swift
│   ├── MaterialWindowController.swift
│   └── main.swift
├── Tests/main.swift
├── build.sh
└── test.sh
```

The deterministic scripts compile with Swift 6 complete strict concurrency, warnings as errors, and deployment target `arm64-apple-macosx15.0`. No production module or third-party dependency is created.

## Resolution Model

`MaterialResolver` is UI-free and takes an injected Glass-support fact plus an accessibility snapshot:

| Condition | Resolved path |
|---|---|
| Reduce Transparency enabled | Opaque accessibility background |
| Forced fallback, transparency allowed | `NSVisualEffectView` |
| Automatic, Glass available | Glass |
| Automatic, Glass unavailable | `NSVisualEffectView` |

Increase Contrast remains visible in diagnostics but does not silently select a different material. Whether the platform-adapted material has acceptable contrast is a manual gate.

Runtime Glass construction remains guarded by `if #available(macOS 26.0, *)`. Injected facts are used only for pure resolver tests; they cannot make unavailable APIs callable.

## Chrome and Canvas Boundary

The shared chrome roles are a representative segmented tab control and add/close request controls. They do not implement tab state.

On macOS 26, an `NSGlassEffectContainerView` owns a content view containing two real `NSGlassEffectView` descendants: one wraps the representative tab group and one wraps the controls group. The implementation uses only SDK-confirmed Glass APIs: `contentView`, `cornerRadius`, `style`, and container `contentView`/`spacing`.

The fallback wraps the equivalent `MaterialChromeView` once in an `NSVisualEffectView` configured with candidate values:

```swift
material = .headerView
blendingMode = .behindWindow
state = .followsWindowActiveState
```

These remain spike candidates. The opaque path uses a dedicated view whose dynamic layer colors refresh through `updateLayer()` and which explicitly reports `isOpaque = true`.

The file-content canvas is a sibling below the chrome material, never a descendant of Glass or `NSVisualEffectView`, and no representative file cell receives its own effect.

## Accessibility Lifecycle

The controller reads `NSWorkspace` accessibility display options through an injectable provider. It observes `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on `NSWorkspace.shared.notificationCenter`, as required by the SDK.

Observation start/stop is synchronous and idempotent. Each registration has a unique identity; a task queued before stop is rejected after that identity is invalidated. A small RAII token removes the block observer during explicit stop or deinitialization. Window close stops observation before releasing the window/controller relationship.

## Harness Controls

The application menu supports:

- automatic and forced-fallback material preferences;
- normal and `desktopIconWindow + 1` candidate levels;
- close, recreate, and quit.

The app delegate retains selected material and level intent across recreation. Both levels and every material remain candidates.

## Build, Test, and Run

```bash
cd spikes/materials
bash test.sh
bash build.sh
open build/AlcoveSpike.app
```

## Automated Evidence Executed by Codex

Final verification on 2026-08-02 established:

- prohibited-source scan: pass;
- strict Swift 6 test compile: pass;
- 72 explicit assertions: pass, 0 failures, 0 skips on the macOS 26.5 runtime;
- pure resolution matrix for preference, Glass availability, Reduce Transparency, and Increase Contrast preservation: pass;
- automatic runtime construction contains one real Glass container and two real Glass effect descendants: pass;
- forced fallback type and candidate material/blending/state values: pass;
- injected Reduce Transparency constructs a real opaque, non-effect path: pass;
- equivalent control roles, group count, and chrome height anchor across paths: pass;
- canvas remains outside all material containers: pass;
- preference rebuild detaches old material without stacking or duplicating observation: pass;
- real workspace notification delivers once on MainActor, rebuilds state, stops cleanly, and rejects a queued stale callback: pass;
- normal and desktop-candidate levels have exact values: pass;
- app-delegate recreation replaces/detaches the old controller and preserves material/level intent: pass.

These tests inspect types, hierarchy, constraints, event delivery, and lifecycle. They do not assess rendering quality.

## Manual Verification — Not Run

| Test | Status |
|---|---|
| Glass appearance at normal level | NR |
| Glass appearance at desktop-candidate level | NR |
| Fallback appearance on an actual macOS 15 system | NR |
| Light and dark appearance | NR |
| Reduce Transparency visual result | NR |
| Increase Contrast visual result | NR |
| Readability and control hit testing | NR |
| Resizing and equivalent layout | NR |
| Window active/inactive transitions | NR |
| Desktop wallpaper variation | NR |
| Multiple displays | NR |

## Known Issues and Gate Status

- The disposable spike and current production distribution both target arm64.
- `.headerView`, `.behindWindow`, `.followsWindowActiveState`, Glass radius, and grouping spacing are unselected candidates.
- No macOS 15 runtime was available, so the fallback is structurally constructed on macOS 26 but not runtime-validated on macOS 15.
- Accessibility appearance and readable contrast require human observation under real system settings.
- Behavior at the desktop candidate level remains visually unverified.

Full Spike 0.4 remains incomplete. The exit gate still requires visual evidence on macOS 26 and macOS 15, accessibility-setting observations, and an explicit material-boundary decision.
