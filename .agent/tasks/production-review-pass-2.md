# Production Review Pass 2 — State and Failure Audit

## Goal

Independently reread the complete shipping implementation after pass 1, this
time following state machines, concurrency, cancellation, lifecycle, failure,
retry, transaction, and multi-window paths rather than reviewing by feature
folder.

## Scope

- All 38 production Swift files across the app and AlcoveCore.
- CI and all associated XCTest/Core test sources.
- Cross-Portal interaction while modal folder selection is suspended.
- Keyboard focus, scrolling, selection replay, shutdown task draining, and
  persistence FIFO behavior.

## Exit Gate

- Every confirmed Critical, High, or Medium result is fixed and regression
  tested.
- Full Core tests, hosted tests, universal Release, source policy, and diff
  checks pass.
- Independent fix re-review reports no remaining Critical, High, or Medium.
