# Alcove

A native macOS menu-bar utility that creates movable, resizable desktop-layer folder portals.

## What It Is

Alcove is designed to place lightweight portal windows on the desktop layer — each portal maps a local directory and displays its contents as a scrollable native icon grid. The target behavior is below normal application windows and above desktop icons, with multiple tabs, Finder-consistent selection, Quick Look, and placement recovery across display changes, Spaces, sleep/wake, and resolution adjustments. Phase 0 spikes must validate the system-dependent window and display behavior before the architecture is locked.

**Alcove is not a Finder replacement.** It is a focused desktop surface for folders you care about.

## Status

> **Phase 0 — Technical Spikes**
>
> The documentation baseline and automated portions of Spikes 0.1A–0.5C7 are complete. Manual
> system-behavior matrices and remaining integration evidence are still in progress. Production
> Slices 1–11 now provide the tested Apple Silicon AppKit shell, multi-tab portals,
> Finder-style interaction and icon tiles, transactional empty-portal creation, Quick Look, v12 portal
> persistence, primary-display-following recovery, automatic FSEvents folder refresh,
> menu-bar portal management, global Small/Medium/Large content sizing, a global five-step static translucent background, global five-step panel spacing and corner radius, a system-shadow toggle, collision-safe placement, accessibility display-option handling, and
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

## 安装与发布

GitHub Release 只上传一个 `Alcove.<版本号>.dmg`。打开 DMG 后，将 `Alcove.app`
拖到 `Applications`。Release 使用免费的 Apple Development 证书签名但不经过 Apple
公证；首次打开前需要按对应 Release Notes 的说明移除下载隔离属性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Alcove.app
```

所有 push 和 Pull Request 都执行 unsigned arm64 CI。发布配置位于
[`Config/Release/manifest.json`](Config/Release/manifest.json)：只有 main CI 成功、
`release` 为 `true`、该版本尚未发布，并且 [`CHANGELOG.md`](CHANGELOG.md) 存在唯一、
非空且完全同名的版本章节时，Release workflow 才会签名、打包并发布 DMG。

支持 `x.y.z`、`x.y.z-alpha.n` 和 `x.y.z-beta.n`。Alpha/Beta 后缀用于 Release、tag、
DMG 与 CHANGELOG；App 的 `CFBundleShortVersionString` 使用对应的纯数字 `x.y.z`。

Release workflow 使用以下 GitHub Actions repository secrets：

- `CERTIFICATES_P12`：Apple Development P12 的 Base64 内容
- `CERTIFICATES_PASSWORD`：P12 导出密码
- `FEISHU_WEBHOOK`：飞书自定义机器人的 Webhook
- `FEISHU_SECRET`：飞书自定义机器人的签名密钥

## Key Design Decisions

- **Native AppKit**, not WidgetKit
- **Stable static translucency** for Portal backgrounds: a plain alpha-composited surface avoids WindowServer backdrop rebinding artifacts across Spaces, supports five global transparency levels and per-Portal colors, and becomes opaque when Reduce Transparency is enabled
- **Finder-consistent interaction**: click/Command/Shift and empty-space marquee selection, arrow navigation, Command-A, Quick Look, open, Trash, native file-URL drag in/out, and an AppKit contextual menu for Open, Quick Look, Finder reveal, Finder Get Info through user-authorized Apple Events, AirDrop, path copying, and Apple Terminal
- **Finder-style icon tiles**: separate icon/title selection regions, two-line labels, a durable integer-capacity grid shared by rendering, keyboard navigation, creation, and live resizing, and persisted Small/Medium/Large icon presets
- **Internal local folders only**: folder selection rejects removable, ejectable, and network-volume locations
- **Primary-display layout**: all Portals live on the menu-bar display (`NSScreen.screens[0]`). Primary-display changes preserve left/top point offsets, keep fitting non-conflicting panels fixed, flow overflow into new right-hand columns, and retain complete per-display layouts for return restoration. Advanced settings repairs off-screen or conflicting panels; UUID stability and real topology behavior remain Phase 0 spike gates
- **Focused file operations**: Return and the context menu provide inline conflict-safe rename; Duplicate delegates Finder-compatible naming to `NSWorkspace`; Compress creates conflict-safe Finder-compatible ZIP archives through `/usr/bin/ditto`; Command-Delete uses the system Trash; external and in-panel file drops target either the current directory or an ordinary folder tile, using Finder-style same-volume Move/cross-volume Copy semantics after fail-closed conflict validation; new-folder creation and overwrite remain out of scope
- **Pinned placement**: each portal can persistently disable user dragging and resizing without blocking system display recovery
- **Localized native UI**: English is the development and fallback language; Simplified and Traditional Chinese follow the current macOS language automatically
- **Single UI-free Swift package**: `AlcoveCore` for domain/layout; internal feature groups within the Xcode app target

## Documentation

| Document | Description |
|---|---|
| [Current Handoff](docs/HANDOFF.md) | 当前需求、实现进度、未推送提交、已知风险、踩坑记录和下一段对话接管步骤 |
| [Product Requirements](docs/PRODUCT_REQUIREMENTS.md) | Goals, personas, interaction contract, acceptance criteria |
| [Architecture](docs/ARCHITECTURE.md) | Component boundaries, domain models, persistence, concurrency |
| [Research](docs/RESEARCH.md) | Evidence table, API analysis, reference project inspections |
| [Delivery Plan](docs/DELIVERY_PLAN.md) | Phase 0 spikes, incremental slices, test matrix, gates |
| [Desktop Window Spike](docs/SPIKE_DESKTOP_WINDOW.md) | Disposable AppKit harness, automated evidence, and pending manual matrix |
| [Desktop Window Development Default](docs/SPIKE_DESKTOP_WINDOW_DEVELOPMENT_DEFAULT.md) | Replaceable NSWindow starting configuration; manual gate remains open |
| [Display Placement Spike](docs/SPIKE_DISPLAY_PLACEMENT.md) | Pure placement geometry evidence and pending screen/topology validation |
| [Folder Location Eligibility Spike](docs/SPIKE_FOLDER_LOCATION_ELIGIBILITY.md) | Internal fixed local-storage acceptance and unsupported-volume rejection |
| [Folder Observation Decision](docs/SPIKE_FOLDER_OBSERVATION_DECISION.md) | FSEvents selection and fail-closed recovery contract |

## License

TBD. The repository contains clean-room disposable spike source; no reference-project code has been copied. Reference projects inspected during research are under Apache-2.0 (TileTop) and GPL-3.0 (Pocket Finder). Intentional reuse of Pocket Finder code would require GPL analysis; none is planned.
