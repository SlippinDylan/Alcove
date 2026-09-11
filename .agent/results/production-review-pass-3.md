# Production Review Pass 3 Result — User-Flow and Platform Audit

## Confirmed Defects Fixed

- Automatic FSEvents refresh no longer hides an already visible grid. Per-tab
  selection and scroll snapshots are captured only when the displayed tab is
  actually left, consumed once on the target tab's next successful load, and
  invalidated by an empty result. Rapid switching and duplicate-folder tabs no
  longer inherit or roll back another tab's selection.
- Choosing the same path after a folder identity replacement now explicitly
  restarts observation after persistence succeeds.
- Narrow portals now expose all tabs and Add through horizontal scrolling,
  including the system's legacy always-visible scrollbar style without changing
  the established minimum portal height.
- Save failures from portal management, tabs, and placement now produce an
  accessible user-facing alert while leaving the prior saved state unchanged.
  Task cancellation remains a normal lifecycle event and does not show an error.
- The portal canvas now resolves its dynamic background through the current
  effective appearance, so Light/Dark changes update correctly.

## Verification

- AlcoveCore: 110 tests passed.
- Hosted app: 133 tests passed.
- Unsigned Release: universal `arm64` and `x86_64`, minimum macOS 15.0, SDK 26.5.
- Source-policy and diff checks passed.
- Independent final diff re-review found no remaining confirmed Critical, High,
  or Medium issue.

## Remaining Manual Evidence

Real macOS 15, Intel launch, physical display disconnect/reconnect, Spaces,
Stage Manager, Show Desktop, VoiceOver navigation, controlled TCC denial, and
visual Glass/fallback behavior remain manual acceptance work. Formal signing is
outside this implementation review.
