# Production Review Pass 3 — User-Flow and Platform Audit

## Goal

Independently reread the complete shipping implementation after passes 1 and 2,
following end-to-end user flows and the AppKit, Quick Look, FSEvents, display,
persistence, accessibility, and release contracts.

## Scope

- All 38 production Swift files across the app and AlcoveCore.
- All hosted and Core tests, CI, Info.plist, requirements, architecture, and the
  relevant window, folder-location, and folder-observation decisions.
- Refresh, tab-runtime, recovery, persistence-failure, appearance, narrow-window,
  cancellation, and rapid-interaction boundaries.

## Exit Gate

- Every confirmed Critical, High, or Medium result is fixed and regression
  tested.
- Full Core tests, hosted tests, universal Release, source policy, artifact, and
  diff checks pass.
- Independent final diff re-review reports no remaining confirmed Critical,
  High, or Medium issue.
