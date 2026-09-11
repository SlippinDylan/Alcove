# Slice 3 — Selection and Opening

## Goal

Add Finder-consistent selection, keyboard navigation, and read-only opening to
the production file grid.

## Scope

- Pure per-tab selection state in AlcoveCore.
- Click selects, Command-click toggles, Shift-click forms an inclusive range.
- Arrow keys move focus; Shift-arrow extends from the anchor; Command-A selects all.
- Double-click, Command-O, and Command-Down open through an injected NSWorkspace boundary.
- Return is a no-op. No mutation command is introduced.
- Quick Look remains Slice 7.

## Verification

- Core state tests cover anchors, focus, ranges, toggles, empty and stale items.
- Hosted tests cover event-command mapping, grid selection, navigation, opening,
  failures, and Return behavior.
- Swift 6 warnings-as-errors and universal Release build remain clean.
