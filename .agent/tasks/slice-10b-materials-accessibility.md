# Slice 10B — Adaptive Materials and Accessibility

## Goal

Apply the Spike 0.4 compatibility boundary to production portal chrome and
complete the directly testable MVP accessibility contracts.

## Scope

- Use public `NSGlassEffectView` on macOS 26 for the portal tab/navigation layer.
- Use semantic `NSVisualEffectView` header material on macOS 15–25.
- Replace transparency with an opaque chrome surface when Reduce Transparency
  is enabled.
- React to workspace accessibility display-option changes without stale observer
  delivery.
- Preserve Increase Contrast and Reduce Motion state; add an explicit stronger
  boundary for Increase Contrast and keep production free of custom animation.
- Add file-grid position, selection value, help, and Open accessibility action.
- Complete accessibility help for tab selection, close, and add controls.

## Exit Gate

- Resolver, Glass, fallback, opaque, contrast, and observer lifecycle tests pass.
- File accessibility metadata and Open action tests pass.
- Full hosted tests and unsigned universal Release build pass.
- Visual and real VoiceOver behavior remain honestly recorded as manual checks.
