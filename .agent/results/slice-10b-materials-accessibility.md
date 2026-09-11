# Slice 10B Result — Adaptive Materials and Accessibility

## Implemented

- Production portal chrome uses `NSGlassEffectView` on macOS 26 and a semantic
  `NSVisualEffectView` configured with `.headerView`, `.behindWindow`, and
  `.followsWindowActiveState` on macOS 15–25.
- The file grid stays outside the material view; Glass is limited to the tab and
  navigation layer.
- Reduce Transparency selects a fully opaque dynamic system background.
- Increase Contrast adds a stronger separator boundary. Reduce Motion is read
  and retained; Alcove has no custom transition or decorative animation to
  suppress.
- The material host observes
  `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, rebuilds on
  the main actor, and rejects callbacks queued before observation stops.
- Grid items report selection and one-based position, expose descriptive help,
  and provide a tested Open accessibility action. Tab controls expose labels and
  help through standard AppKit controls.

## Apple API Basis

- Apple Developer Documentation: `NSGlassEffectView`.
- Apple Developer Documentation: `NSVisualEffectView` and its semantic materials.
- Apple Developer Documentation: AppKit accessibility display options and custom
  controls.
- WWDC25 session 310, “Build an AppKit app with the new design,” for keeping
  Liquid Glass on navigation/control surfaces rather than the content canvas.

## Manual Verification

Visual appearance on a physical macOS 15 system, real VoiceOver speech, light
and dark wallpaper variation, and user-toggled accessibility settings remain
manual checks. No automated structural test is represented as visual evidence.

## Automated Verification

- AlcoveCore: 110 tests passed.
- Hosted app: 107 tests passed.
- Unsigned Release build: universal `arm64` and `x86_64`, minimum macOS 15.0.
- Production Glass, visual-effect, opaque, rebuild, stale-callback, and
  accessibility-action paths have focused tests.
