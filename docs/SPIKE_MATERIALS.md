# Spike 0.4 — macOS 26+ Liquid Glass Boundary

## Scope

This disposable AppKit harness validates the material boundary used by Alcove's
macOS 26+ product baseline:

- native `NSGlassEffectView` and `NSGlassEffectContainerView` construction;
- one Glass chrome layer above an ordinary file-content canvas;
- desktop-candidate and normal window levels;
- an explicitly opaque surface when Reduce Transparency is enabled;
- accessibility notification delivery, teardown, and window recreation.

The harness builds for `arm64-apple-macosx26.0` with Swift 6 complete strict
concurrency and warnings as errors. It contains no older-system material path.

## Architecture

```text
MaterialWindowController
├── NSGlassEffectContainerView
│   └── MaterialChromeView
│       ├── NSGlassEffectView (tabs)
│       └── NSGlassEffectView (actions)
└── ordinary file-content canvas

Reduce Transparency
└── OpaqueChromeBackgroundView
    └── MaterialChromeView
```

`MaterialResolver` has exactly two states: Glass and opaque accessibility.
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

`test.sh` validates the two-state resolver, real Glass construction, the opaque
accessibility surface, control callbacks, window levels, observer lifecycle, and
controller ownership. `build.sh` produces an ad-hoc signed arm64 app whose
`LSMinimumSystemVersion` is 26.0.

## Evidence and remaining validation

Automated structural coverage establishes that Glass content is installed through
the public `contentView` APIs, file content stays outside the Glass container, and
Reduce Transparency removes Glass rather than dimming it. Production tests cover
the complete Portal surface's style/tint mapping and accessibility rebuild.

Manual validation remains required on macOS 26 and macOS 27 for wallpaper-driven
appearance, active/inactive contrast at the desktop window level, Increase
Contrast, Reduce Transparency, and performance with multiple Portals.
