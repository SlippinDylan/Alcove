# Phase 0.4A — Material Compatibility Boundary Bootstrap

You are the bounded implementation agent for a disposable Alcove technical spike. This is not production code, does not select a final material, and does not complete Spike 0.4.

## Read First

Read and list every successfully read path; report absent instruction files and read errors honestly:

1. `~/.codex/AGENTS.md`
2. Repository `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DELIVERY_PLAN.md`
8. `docs/SPIKE_DESKTOP_WINDOW.md`
9. Relevant public SDK headers for `NSGlassEffectView`, `NSGlassEffectContainerView`, `NSVisualEffectView`, and accessibility display options

Follow the global rules: English code/comments/docs, explicit errors, MainActor AppKit ownership, no unsafe casts/unwraps, actual verification, and no unsupported GUI claims.

## Objective

Create a minimal disposable AppKit harness under `spikes/materials/` that makes the provisional portal material boundary reviewable and testable:

- one movable, resizable, key-eligible `NSWindow`;
- a root layout with a chrome region at the top and a plain file-content canvas below;
- representative chrome controls: a small tab group plus add/close controls;
- on macOS 26 automatic mode, use public `NSGlassEffectView` descendants inside `NSGlassEffectContainerView` for chrome only;
- provide a force-fallback mode that uses `NSVisualEffectView` for the same chrome layout even on macOS 26, so structural compatibility can be tested locally;
- when Reduce Transparency is modeled as enabled, use an explicit opaque chrome path instead of claiming translucent material is acceptable;
- expose current material path, window level, Reduce Transparency, and Increase Contrast in visible diagnostics;
- observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` with an explicit, idempotent observer lifecycle and rebuild the material when options change;
- provide menu controls to select automatic vs forced visual-effect fallback, normal vs `desktopIconWindow + 1` candidate level, recreate the window, close it, and quit.

The file-content canvas and representative file cells must never be wrapped in separate glass/effect views. The desktop level and material choices remain candidates.

## Material Model

Use typed intent and result values, for example:

```swift
enum MaterialPreference {
    case automatic
    case forceVisualEffectFallback
}

enum ResolvedMaterialPath {
    case glass
    case visualEffect
    case opaqueAccessibility
}

struct AccessibilityDisplayOptions {
    let reduceTransparency: Bool
    let increaseContrast: Bool
}
```

The resolver should be independently testable. Automatic resolution may take an injected `supportsGlass` fact so tests cover both OS branches without pretending the current macOS 26 runtime is macOS 15. Runtime construction must still use `if #available(macOS 26.0, *)` before referencing Glass APIs.

For the fallback candidate, start with the semantic `NSVisualEffectView.Material.headerView`, `.behindWindow`, and `.followsWindowActiveState`. These are spike candidates, not a final material decision.

Use only SDK-confirmed Glass APIs: `contentView`, `cornerRadius`, `tintColor`, `style`, and container `contentView`/`spacing`. Do not invent `isInteractive`, `state`, or other Glass properties.

## Engineering Constraints

- Native Swift and AppKit; minimum macOS 15; compile with Swift 6 complete strict concurrency and warnings as errors.
- Public Apple APIs only; no third-party dependencies, network, package installation, copied reference-project code, production Alcove modules, file enumeration, tabs state, persistence, Quick Look, or folder observation.
- No `as!`, `try!`, normal-path force unwrap, recoverable `fatalError`, `nonisolated(unsafe)`, `@preconcurrency`, KVC, broad `Any`, swallowed errors, or test-only state that merely proves itself.
- MainActor owns all AppKit objects and notification lifecycle.
- Use deterministic `swiftc` app/test scripts under the spike directory.
- Keep the implementation to roughly three to eight source/test files where practical.

## Automated Verification

Actually clean, test, and build. Tests must meaningfully cover without presenting pixels as proven:

- pure resolution matrix for automatic/forced fallback, supports-glass true/false, Reduce Transparency true/false, and Increase Contrast preservation;
- macOS 26 runtime automatic construction produces a real `NSGlassEffectContainerView` with Glass descendants in chrome;
- forced fallback produces a real `NSVisualEffectView` configured with the selected semantic material, blending mode, and state;
- Reduce Transparency produces an opaque non-effect view;
- each path retains equivalent chrome control roles and layout anchors;
- file-content canvas is outside material-effect descendants;
- switching preferences rebuilds rather than stacking old views or observers;
- accessibility observer start/stop is synchronous, idempotent, removes its token, and delivers updates on MainActor;
- both window-level values are exact;
- close/recreate ownership is stable;
- source-policy checks reject the prohibited syntax and invented Glass properties.

Automated construction and hierarchy tests are not visual rendering, contrast, accessibility, desktop-level, or macOS 15 runtime evidence.

## Manual Checklist

Document all as not run (`NR`): Glass appearance at normal and desktop-candidate levels; fallback appearance on an actual macOS 15 system; light/dark appearance; Reduce Transparency; Increase Contrast; readability; control hit testing; resizing/layout; window active/inactive transitions; desktop wallpaper variation; multiple displays.

## Allowed Modifications

Only create or modify:

- `spikes/materials/`
- `docs/SPIKE_MATERIALS.md`
- `.agent/results/phase-0.4a-material-boundary.md`

Do not modify HANDOFF, progress, README, `.gitignore`, baseline documents, existing spikes/docs, Memory, Git config, or Git history. Do not commit, push, reset, rebase, clean Git files, or alter remotes.

## Documentation

Create `docs/SPIKE_MATERIALS.md` beginning with:

```text
Status: In Progress — Phase 0.4A material boundary bootstrap only
```

Include structure, exact build/test/run commands, material resolution, layout boundary, accessibility lifecycle, actual automated evidence, all manual items as `NR`, limitations, known issues, and an explicit statement that full Spike 0.4 is incomplete.

## Result Report

Create `.agent/results/phase-0.4a-material-boundary.md`, at most 120 lines:

1. Read/absent/failure paths.
2. Created/modified files.
3. Engineering form and reason.
4. Exact commands and exit codes.
5. Automated facts and limitations.
6. Unperformed manual tests.
7. Known issues and three least-certain points.
8. Strict scope statement.
9. Explicit statement that full Spike 0.4 is incomplete.

Implement now. A prose-only response is a failure.
