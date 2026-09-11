# Slice 10E — Final Review Fixes

## Goal

Close the concrete Medium findings from the independent MVP implementation
review before producing the final verification build.

## Scope

- Snap user-finished resize content dimensions to the active icon grid's column
  and row increments before committing placement.
- Include tab chrome in the real 2×2 minimum window size.
- Expand and persist too-small creation frames and icon-preset transitions before
  applying them to live windows.
- Hide the previous tab's grid synchronously when selected-tab identity or mapped
  folder changes, before asynchronous validation and loading begin.

## Exit Gate

- Focused regression tests reproduce and close all three review findings.
- Full Core and hosted tests pass.
- Unsigned universal Release build and source-policy checks pass.
- Independent re-review finds no remaining Critical, High, or Medium issue in
  the changed paths.
