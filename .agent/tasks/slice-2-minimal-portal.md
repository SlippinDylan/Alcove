# Slice 2 — Minimal Single Portal

## Goal

Add the first production desktop portal: a replaceable provisional window,
background folder loading, native scrollable icon grid, and explicit loading,
empty, and root-error states.

## Scope

- Create the single UI-free `AlcoveCore` package for domain values and grid math.
- Keep URL resource reads and directory I/O in the app target's FolderAccess group.
- Use asynchronous background boundaries and reject stale/cancelled generations.
- Accept only internal fixed local folders before portal creation.
- Allow a development `--folder <path>` startup seam; do not implement the final
  New Portal overlay or persistence.
- Use the replaceable Phase 0.1D window default without claiming its manual gate.

## Verification

- SwiftPM Core tests.
- Hosted app tests for enumeration, errors, eligibility, generation, grid,
  presentation states, startup composition, and window configuration.
- Unsigned universal Release build with macOS 15 minimum target.
