# Changelog

All notable changes to Alcove releases are recorded here.

## [Unreleased]

### Added

- Added version-gated Apple Development signing, drag-to-install DMG publishing, and matching release-note validation.
- Added Feishu notifications for repository activity, CI results, and published releases.

### Changed

- CI and release artifacts now target Apple Silicon (`arm64`) only.
- GitHub Actions checkouts are commit-pinned, do not persist credentials, and keep privileged triggers on trusted code paths.
