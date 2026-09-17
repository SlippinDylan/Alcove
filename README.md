<div align="center">
  <img src="docs/images/readme/app-icon.png" width="160" height="160" alt="Alcove app icon">
  <h1>Alcove</h1>
  <p>A native macOS menu-bar utility that creates movable, resizable desktop-layer folder portals.</p>
  <p>
    <a href="docs/README.zh-CN.md">简体中文</a> ·
    <a href="docs/README.zh-TW.md">繁體中文</a> ·
    <strong>English</strong> ·
    <a href="docs/README.ja.md">日本語</a> ·
    <a href="docs/README.ru.md">Русский</a>
  </p>
</div>

## What It Is

Alcove is designed to place lightweight portal windows on the desktop layer — each portal maps a local directory and displays its contents as a scrollable native icon grid. The target behavior is below normal application windows and above desktop icons, with multiple tabs, Finder-consistent selection, Quick Look, and placement recovery across display changes, Spaces, sleep/wake, and resolution adjustments. Phase 0 spikes must validate the system-dependent window and display behavior before the architecture is locked.

**Alcove is not a Finder replacement.** It is a focused desktop surface for folders you care about.

## Features

<table>
  <tr>
    <td width="32%">
      <strong>Desktop folder portals</strong><br><br>
      Keep important local folders visible in lightweight, movable panels with native icons, multiple tabs, and a translucent desktop-friendly appearance.
    </td>
    <td width="68%"><img src="docs/images/readme/portal-overview.png" alt="An Alcove folder portal showing two tabs and a native icon grid"></td>
  </tr>
  <tr>
    <td>
      <strong>Finder-style file actions</strong><br><br>
      Open, preview, reveal, rename, compress, duplicate, trash, AirDrop, copy paths, and open selected items in Terminal from one native context menu.
    </td>
    <td><img src="docs/images/readme/file-actions.png" alt="Alcove file context menu with native file actions"></td>
  </tr>
  <tr>
    <td>
      <strong>Draw to create</strong><br><br>
      Create a new portal directly on the desktop with a live grid preview, then connect it to a folder on your Mac.
    </td>
    <td><img src="docs/images/readme/portal-creation.png" alt="Alcove portal creation overlay with a live grid preview"></td>
  </tr>
  <tr>
    <td>
      <strong>Multiple folder tabs</strong><br><br>
      Add, reorder, switch, and remove up to four folders in each panel while keeping every tab's navigation and selection state.
    </td>
    <td align="center"><img src="docs/images/readme/folder-tabs.png" width="420" alt="Alcove panel settings showing two folder tabs"></td>
  </tr>
  <tr>
    <td>
      <strong>Panel controls</strong><br><br>
      Pin a panel in place, change its sort order, open its settings, or remove it through a compact native menu.
    </td>
    <td><img src="docs/images/readme/panel-controls.png" alt="Alcove panel menu with pin, sort, settings, and delete controls"></td>
  </tr>
  <tr>
    <td>
      <strong>Custom appearance</strong><br><br>
      Adjust five transparency levels, three content sizes, five corner radii, four panel spacings, and window shadows.
    </td>
    <td align="center"><img src="docs/images/readme/appearance-settings.png" width="420" alt="Alcove appearance settings with transparency and panel style controls"></td>
  </tr>
  <tr>
    <td>
      <strong>Language and startup</strong><br><br>
      Launch Alcove at login and use English, Simplified Chinese, Traditional Chinese, or the current macOS language.
    </td>
    <td align="center"><img src="docs/images/readme/language-settings.png" width="420" alt="Alcove general settings with launch at login and app language controls"></td>
  </tr>
</table>

## Status

> **Production MVP implemented**
>
> Automated implementation and verification are complete; manual system-behavior and release
> checks remain. The production app provides the tested Apple Silicon AppKit shell, multi-tab portals,
> Finder-style interaction and icon tiles, transactional empty-portal creation, Quick Look, v12 portal
> persistence, primary-display-following recovery, automatic FSEvents folder refresh,
> menu-bar portal management, global Small/Medium/Large content sizing, a global five-step static translucent background, global four-step panel spacing, five-step corner radius, a system-shadow toggle, collision-safe placement, accessibility display-option handling, and
> explicit recovery from missing, replaced, permission, read, and persistence
> failures. Portals can be pinned against user movement and resizing, browse mapped subdirectories, expose Finder/Terminal/path actions, and localize all user-facing UI into English, Simplified Chinese, or Traditional Chinese. The menu bar provides portal show/hide commands and an application-settings window for global style, position repair, and layout backup. Three production-wide code review passes are complete, and CI tests
> and performs unsigned arm64 build verification. Version-gated Apple Development signing and
> drag-to-install DMG publishing are implemented; manual Gatekeeper and installation evidence remains open.

## Platform

| Property | Value |
|---|---|
| Deployment target | macOS 26 (Tahoe) |
| Compatibility target | macOS 26 and macOS 27 (Golden Gate) |
| Build SDK | Xcode / macOS 26 SDK |
| Architecture | Apple Silicon (arm64) |
| App type | Menu-bar LSUIElement (accessory), non-sandboxed |
| Distribution | Version-gated GitHub Releases with one Apple Development-signed, non-notarized DMG |

## Installation and Releases

Each GitHub Release contains one `Alcove.<version>.dmg`. Open the DMG and drag
`Alcove.app` into `Applications`. Releases are signed with a free Apple Development
certificate and are not notarized. Before the first launch, remove the download
quarantine attribute as described in the release notes:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Alcove.app
```

Pushes to `main` and pull requests always run lightweight release-automation checks.
Changes limited to `README.md`, `docs/`, `LICENSE`, or `AGENTS.md` skip the macOS build
unless publishing is enabled; all other changes run the complete test suite and an
unsigned arm64 Release build. Release configuration lives in
[`Config/Release/manifest.json`](Config/Release/manifest.json). The release workflow
signs, packages, and publishes a DMG only after main CI succeeds, `release` is `true`,
the version is unpublished, and [`CHANGELOG.md`](CHANGELOG.md) contains one unique,
non-empty section with the exact same version.

Supported versions are `x.y.z`, `x.y.z-alpha.n`, and `x.y.z-beta.n`. Alpha and beta
suffixes are used by the release, tag, DMG, and Changelog; the app's
`CFBundleShortVersionString` uses the matching numeric `x.y.z` value.

The release workflow uses these GitHub Actions repository secrets:

- `CERTIFICATES_P12`: Base64-encoded Apple Development P12
- `CERTIFICATES_PASSWORD`: P12 export password
- `FEISHU_WEBHOOK`: Feishu custom bot webhook
- `FEISHU_SECRET`: Feishu custom bot signing secret

## Key Design Decisions

- **Native AppKit**, not WidgetKit
- **Stable static translucency** for Portal backgrounds: a plain alpha-composited surface avoids WindowServer backdrop rebinding artifacts across Spaces, supports five global transparency levels and per-Portal colors, and becomes opaque when Reduce Transparency is enabled
- **Finder-consistent interaction**: click/Command/Shift and empty-space marquee selection, arrow navigation, Command-A, Quick Look, open, Trash, native file-URL drag in/out, and an AppKit contextual menu for Open, Quick Look, Finder reveal, Finder Get Info through user-authorized Apple Events, AirDrop, path copying, and Apple Terminal
- **Finder-style icon tiles**: separate icon/title selection regions, two-line labels, a durable integer-capacity grid shared by rendering, keyboard navigation, creation, and live resizing, and persisted Small/Medium/Large icon presets
- **Internal local folders only**: folder selection rejects removable, ejectable, and network-volume locations
- **Primary-display layout**: all Portals live on the menu-bar display (`NSScreen.screens[0]`). Primary-display changes preserve left/top point offsets, keep fitting non-conflicting panels fixed, flow overflow into new right-hand columns, and retain complete per-display layouts for return restoration. Advanced settings repairs off-screen or conflicting panels; UUID stability and real topology behavior remain Phase 0 spike gates
- **Focused file operations**: Return and the context menu provide inline conflict-safe rename; Duplicate delegates Finder-compatible naming to `NSWorkspace`; Compress creates conflict-safe Finder-compatible ZIP archives through `/usr/bin/ditto`; Command-Delete uses the system Trash; external and in-panel file drops target either the current directory or an ordinary folder tile, using Finder-style same-volume Move/cross-volume Copy semantics after fail-closed conflict validation; new-folder creation and overwrite remain out of scope
- **Pinned placement**: each portal can persistently disable user dragging and resizing without blocking system display recovery
- **Localized native UI**: English is the development and fallback language; Settings can follow the current macOS language or explicitly use English, Simplified Chinese, or Traditional Chinese after relaunch
- **Single UI-free Swift package**: `AlcoveCore` for domain/layout; internal feature groups within the Xcode app target

## Documentation

| Document | Description |
|---|---|
| [Current Handoff](docs/HANDOFF.md) | Current requirements, implementation status, known risks, and handoff notes |
| [Product Requirements](docs/PRODUCT_REQUIREMENTS.md) | Goals, personas, interaction contract, acceptance criteria |
| [Architecture](docs/ARCHITECTURE.md) | Component boundaries, domain models, persistence, concurrency |
| [Research](docs/RESEARCH.md) | Evidence table, API analysis, reference project inspections |
| [Delivery Plan](docs/DELIVERY_PLAN.md) | Historical delivery stages, current test matrix, and release gates |

## License

Copyright © 2025–2026 SlippinDylan Studio. Alcove is licensed under the [Apache License 2.0](LICENSE).
