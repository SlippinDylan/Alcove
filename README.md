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
> Slices 1–10 now provide the tested universal AppKit shell, multi-tab portals,
> Finder-style interaction and icon tiles, transactional empty-portal creation, Quick Look, v11 portal
> persistence, multi-display recovery, automatic FSEvents folder refresh,
> menu-bar portal management, global Small/Medium/Large content sizing and five-step frosted-background control, global five-step panel spacing and corner radius, a system-shadow toggle, collision-safe placement, adaptive macOS 26
> Glass/macOS 15 fallback chrome, accessibility display-option handling, and
> explicit recovery from missing, replaced, permission, read, and persistence
> failures. Portals can be pinned against user movement and resizing, expose the selected folder path with copy support, and localize all user-facing UI into English, Simplified Chinese, or Traditional Chinese. The menu bar provides portal show/hide commands and a reserved application-settings entry. Three production-wide code review passes are complete, and CI tests
> and publishes an unsigned universal verification artifact. Manual system
> behavior and the separate signing release gate remain open.

## Platform

| Property | Value |
|---|---|
| Deployment target | macOS 15 (Sequoia) |
| Primary design target | macOS 26 (Tahoe) |
| Build SDK | Xcode / macOS 26 SDK |
| Architecture | arm64 + x86_64 (universal) |
| App type | Menu-bar LSUIElement (accessory), non-sandboxed |
| Distribution | GitHub Releases — unsigned PR builds; main releases signed with free Apple Development identity |

## Key Design Decisions

- **Native AppKit**, not WidgetKit
- **Adaptive native material** with one global five-step background level on always-active frosted surfaces; lightweight separators divide the top controls and bottom path row from file content, while macOS 26 Glass remains limited to suitable settings actions
- **Finder-consistent interaction**: click selects, Command-click toggles, Shift-click ranges, arrow keys navigate, Command-A selects all, Space for Quick Look, Command-Down or Command-O opens selection
- **Finder-style icon tiles**: separate icon/title selection regions, two-line labels, a durable integer-capacity grid shared by rendering, keyboard navigation, creation, and live resizing, and persisted Small/Medium/Large icon presets
- **Internal local folders only**: folder selection rejects removable, ejectable, and network-volume locations
- **Eviction-safe placement design**: persists display UUID plus absolute and normalized placement, while preserving remembered home placement during system-driven moves; UUID stability and transition behavior are Phase 0 spike gates
- **Read-only MVP**: no rename, trash, new folder, or file mutations
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
