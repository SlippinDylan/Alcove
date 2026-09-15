# Spike 0.4 — macOS 26+ Portal Background Boundary

## Scope

This disposable AppKit harness validates the material boundary used by Alcove's
macOS 26+ product baseline:

- native `NSGlassEffectView`, `NSGlassEffectContainerView`, and content-layer `NSVisualEffectView` construction;
- one Glass chrome layer above an ordinary file-content canvas;
- desktop-candidate and normal window levels;
- a user-selected Frosted Glass path using active `.underWindowBackground` and `.behindWindow`;
- an explicitly opaque surface when Reduce Transparency is enabled;
- accessibility notification delivery, teardown, and window recreation.

The harness builds for `arm64-apple-macosx26.0` with Swift 6 complete strict
concurrency and warnings as errors. Frosted Glass is a current macOS 26+ visual
choice, not an older-system compatibility branch.

The harness now records rejected alternatives rather than the production surface.
Real Space-transition testing showed that both Liquid Glass and Frosted Glass
temporarily fall back to gray when a Portal uses `.canJoinAllSpaces`. Removing that
flag prevents the artifact but violates all-Space visibility, and moving windows
after the transition produces a visible pop-in. Production therefore uses a plain
static translucent background with no backdrop sampling.

## Architecture

```text
MaterialWindowController
├── Liquid Glass: NSGlassEffectContainerView
│   └── two NSGlassEffectView control groups
├── Frosted Glass: active NSVisualEffectView / behindWindow
└── ordinary file-content canvas

Reduce Transparency
└── OpaqueChromeBackgroundView
    └── MaterialChromeView
```

`MaterialResolver` has three states: Liquid Glass, Frosted Glass, and opaque accessibility.
Increase Contrast remains part of the observed accessibility snapshot without
inventing a separate material. Rebuilding replaces the material container while
retaining the same chrome roles and content boundary.

## Commands

```bash
cd spikes/materials
bash test.sh
bash build.sh
open build/AlcoveSpike.app
```

`test.sh` validates the three-state resolver, real Glass/Frosted construction, the opaque
accessibility surface, control callbacks, window levels, observer lifecycle, and
controller ownership. `build.sh` produces an ad-hoc signed arm64 app whose
`LSMinimumSystemVersion` is 26.0.

## Evidence and remaining validation

Automated harness coverage preserves the construction evidence for the rejected
Glass/Frosted alternatives. Production tests cover static alpha/tint mapping,
light/dark appearance, accessibility rebuild, and the opaque Reduce Transparency path.

Manual validation remains required on macOS 26 and macOS 27 for static-background
appearance, active/inactive contrast at the desktop window level, Increase Contrast,
Reduce Transparency, and performance with multiple Portals.
