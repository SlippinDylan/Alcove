# Slice 10A — Portal Management and Icon Sizing

## Goal

Complete the MVP menu-bar management surface and connect the persisted Small,
Medium, and Large icon presets to every live portal without weakening the
existing persistence transaction boundary.

## Scope

- List portals in persistence order in the menu-bar menu.
- Show and remove a portal from its submenu.
- Select Small, Medium, or Large icon sizing per portal.
- Persist removals and icon changes before mutating live UI state.
- Update grid layout, cell icon constraints, and the 2×2 minimum content size.
- Add focused hosted tests for menu dispatch, transaction failure, layout, and
  accessibility metadata.

## Out of Scope

- Material compatibility and accessibility display-option handling (Slice 10B).
- Missing-folder remapping (Slice 10C).
- Signing, notarization, and public release packaging (Spike 0.6).

## Exit Gate

- AlcoveCore and all hosted tests pass.
- The unsigned Release app is universal (`arm64`, `x86_64`) with macOS 15.0 as
  the minimum deployment target.
- Source and diff policy checks pass.
