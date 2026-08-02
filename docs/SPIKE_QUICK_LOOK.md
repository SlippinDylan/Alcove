Status: In Progress — Phase 0.3A responder bootstrap only

# Spike 0.3 — Quick Look Responder Chain

## Scope

Phase 0.3A is a disposable AppKit bootstrap for evaluating Quick Look ownership from an `NSWindow` that hosts an `NSCollectionView`. It does not choose a production architecture and does not complete Spike 0.3.

The harness provides:

- three locally created, read-only preview fixtures;
- deterministic multiple-selection projection in ascending collection index order;
- a visible selection and window-level diagnostic label;
- a Space-handling `NSCollectionView` first responder;
- a dedicated `QuickLookResponder` in the window-to-application responder chain;
- typed `QLPreviewPanelDataSource` and delegate ownership;
- switchable normal and `desktopIconWindow + 1` candidate levels; and
- explicit, throwing, idempotent fixture cleanup.

No folder enumeration, file mutation, persistence, custom preview rendering, `NSPanel`, or production Alcove module is included.

## Structure

```text
spikes/quick-look/
├── Sources/
│   ├── AppDelegate.swift
│   ├── CollectionViewController.swift
│   ├── PreviewFixture.swift
│   ├── QuickLookController.swift
│   ├── SpikeWindow.swift
│   └── main.swift
├── Tests/main.swift
├── build.sh
└── test.sh
```

The `swiftc` scripts keep the disposable harness deterministic and independent of a production Xcode project. Both app and test targets use Swift 6 complete strict concurrency, warnings as errors, and `arm64-apple-macosx15.0`.

## Responder and Ownership Design

The relevant `nextResponder` direction is:

```text
collection view → view hierarchy/controller → SpikeWindow
    → QuickLookResponder → previous window responder or NSApplication
```

`SpikeWindow.installQuickLookResponder` preserves the existing successor or establishes `NSApplication` as the terminal successor. Installing or removing the responder calls `updateController()` only when the shared panel already exists.

`QuickLookResponder` is main-actor isolated. The three Objective-C informal controller overrides import as nonisolated; each uses a narrow `MainActor.assumeIsolated` runtime check before accessing state. The data-source and delegate conformances themselves are explicitly main-actor isolated. The implementation contains no unchecked stored state, KVC, selector dispatch, `@preconcurrency`, or `nonisolated(unsafe)`.

QuickLookUI declares the panel's data source and delegate as Objective-C `assign` references. `endPreviewPanelControl` and teardown therefore clear only references that still identify this responder. Teardown also orders out a panel presented by this responder. Selection changes replace one cached preview-item snapshot, reload a controlled panel, and repair an invalid current index.

`PreviewFixtureStore` is the only temporary-directory owner. Creation is transactional, cleanup is throwing and idempotent, and the application reports creation or cleanup errors instead of swallowing them.

## Window-Level Controls

The Window menu provides:

- **Normal Level** — `NSWindow.Level.normal`;
- **Desktop Candidate Level** — `CGWindowLevelForKey(.desktopIconWindow) + 1`.

Both use `NSWindow` and remain key eligible. The desktop level is only a candidate carried into this Quick Look harness, not a selected production strategy.

## Build, Test, and Run

```bash
cd spikes/quick-look
bash test.sh
bash build.sh
open build/AlcoveQLSpike.app
```

`test.sh` builds a temporary test app so LaunchServices can supply a real application/key-window context. It then drives the real shared panel and records non-visual state assertions. Build output stays under the ignored `spikes/quick-look/build/` directory.

## Automated Evidence Executed by Codex

The final clean verification on 2026-08-02 produced:

- source-policy scan: pass; prohibited unsafe syntax and invalid `shared().toggle` usage absent;
- test compile: pass under Swift 6 strict concurrency with warnings as errors;
- 40 assertions: pass, 0 failures;
- fixture creation, path validation, rollback boundary, and idempotent cleanup: pass;
- deterministic zero/one/multiple/out-of-range selection projection: pass;
- safe out-of-range data-source fallback: pass;
- Space/no-selection real key-event path and pure visible/hidden toggle policy: pass;
- normal and desktop-candidate level calculations: pass;
- installed real first-responder chain reaches `NSApplication` once without a cycle: pass;
- real `QLPreviewPanel.updateController()` discovers the responder after actual presentation: pass;
- system begin-control assigns typed data source/delegate and normal end-control clears them: pass;
- selection replacement updates the snapshot and repairs an invalid panel index: pass;
- ownership-aware reference cleanup preserves references replaced by another participant: pass;
- app clean build: pass;
- app artifact: arm64 Mach-O, minimum macOS 15.0, SDK 26.5, system frameworks only, ad-hoc signed;
- process launch and Apple-event quit: pass.

The automated panel test establishes controller discovery, presentation-state observation, reference cleanup, and idempotent teardown. It does **not** establish that previews rendered correctly or that dismissal visibly completed.

## Manual Verification — Not Run

| Test | Status |
|---|---|
| Single preview content and Space interaction | NR |
| Multiple-item carousel and arrow navigation | NR |
| Second-Space dismissal as observed by a user | NR |
| Selection changes while the panel is visibly open | NR |
| Escape and close-button dismissal | NR |
| Normal window level behavior | NR |
| Desktop-candidate level behavior | NR |
| Key-window handoff and focus return | NR |
| Text, image, PDF, and movie rendering | NR |
| App deactivate and reactivate | NR |
| Portal close while panel is visible | NR |
| Cleanup and reopen behavior | NR |

The broader Spike 0.3 matrix must also cover the leading key-window policies from Spike 0.1 and any viable window-class result without treating one successful bootstrap configuration as final.

## Known Issues and Remaining Risk

- The harness is arm64-only; a universal binary is not needed for this disposable spike.
- Visual rendering, carousel navigation, focus return, desktop-level interaction, and repeated user-driven handoffs remain unverified.
- The Objective-C informal controller callbacks require a narrow runtime main-actor assertion because the current SDK does not import those overrides with actor isolation.
- The automated integration uses the shared system panel and real responder discovery, but it cannot evaluate appearance or human interaction quality.

## Gate Status

Full Spike 0.3 remains incomplete. Its exit gate still requires human-observed presentation and dismissal from viable desktop-level windows, multi-item carousel validation, and a documented production responder-chain decision.
