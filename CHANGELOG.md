# Changelog

All notable changes to Alcove releases are recorded here.

## [Unreleased]

## [0.1.0-beta.2] - 2026-09-17

### Changed

- Shifted the five panel-transparency presets toward greater transparency and made the previous fourth preset the default.
- Reduced panel spacing to four presets and made the second preset the default.
- Normalized retired transparency and spacing values when loading preferences or layout backups.
- Changed the language confirmation action to quit and automatically reopen Alcove with the selected language.

## [0.1.0-beta.1] - 2026-09-16

### Added

- Added movable and resizable desktop-layer folder portals with persistent placement.
- Added support for multiple portals and up to four folder tabs per portal.
- Added a Finder-style icon grid with single, range, marquee, and keyboard selection.
- Added folder navigation, Quick Look, and opening files in their default applications.
- Added inline rename, duplicate, compress, Move to Trash, AirDrop, Show in Finder, Get Info, Copy Path, and Open in Terminal actions.
- Added native file dragging between Alcove, Finder, the desktop, and folders inside a portal, with conflict-safe move and copy behavior.
- Added automatic folder refresh when files are added, removed, renamed, or changed.
- Added portal pinning, sorting, per-portal colors, and global controls for content size, transparency, spacing, corner radius, and window shadow.
- Added automatic portal recovery when the primary display or screen layout changes.
- Added menu-bar controls, launch-at-login support, panel position repair, and layout backup and restore.
- Added English, Simplified Chinese, and Traditional Chinese localization with a Follow System language option in Settings.
- Added local-only persistence with no telemetry, analytics, or network access.
- Added version-gated Apple Development signing, drag-to-install DMG publishing, and release-note validation.
- Added Feishu notifications for repository activity, CI results, and published releases.
- Published Alcove under the Apache License 2.0.

### Changed

- Release artifacts target Apple Silicon (`arm64`) and require macOS 26 or later.
- Folder portals accept paths on internal fixed local storage only; removable, ejectable, external, and network volumes are not supported.
- GitHub Actions checkouts are commit-pinned, do not persist credentials, and keep privileged triggers on trusted code paths.
- Long file and folder names now retain their ending with middle truncation on the second display line without increasing tile height.
- The menu-bar item now uses the `tray.full` system symbol to better represent Alcove as a container of shortcuts.

### Known Limitations

- This beta is signed with an Apple Development certificate and is not notarized.
- Manual validation of the final DMG installation and launch flow remains required before the public release.
