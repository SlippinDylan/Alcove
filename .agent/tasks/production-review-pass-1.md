# Production Review Pass 1 — Module Audit

## Goal

Read every shipping source module and its directly associated tests, compare it
with the MVP requirements and Apple SDK contracts, and fix every confirmed
Critical, High, or Medium defect before starting the next independent review
pass.

## Scope

- AlcoveCore domain, selection, creation, grid, and placement geometry.
- Folder access, volume validation, FSEvents, cancellation, and persistence.
- File grid, portal creation/presentation, accessibility, and Quick Look.
- App lifecycle, portal coordination, window lifecycle, display placement, menu,
  CI, and shutdown behavior.
- Tests were examined for self-proving assertions as well as missing failure
  sequences.

Disposable Phase 0 spike sources are not shipping application code; their
recorded conclusions and the production code migrated from them were checked,
while the pass's line-by-line scope is the production targets and tests.
