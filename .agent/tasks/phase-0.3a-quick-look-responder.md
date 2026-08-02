# Phase 0.3A — Quick Look Responder Bootstrap

You are the bounded implementation agent for a disposable Alcove technical spike. This is not production code and does not resolve full Spike 0.3.

## Read First

Read and list every successfully read path; report absent instruction files honestly:

1. `~/.codex/AGENTS.md`
2. Repository `AGENTS.override.md` or `AGENTS.md`, if present
3. `HANDOFF.md`
4. `docs/PRODUCT_REQUIREMENTS.md`
5. `docs/RESEARCH.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DELIVERY_PLAN.md`
8. `docs/SPIKE_DESKTOP_WINDOW.md`
9. Relevant files under `spikes/desktop-window/`

Follow the global rules: English code/comments/docs, explicit errors, MainActor AppKit ownership, no unsafe casts/unwraps, actual verification, and no unsupported GUI claims.

## Objective

Create a minimal disposable AppKit harness under `spikes/quick-look/` that establishes a reviewable starting point for Spike 0.3:

- one custom `NSWindow` hosting a minimal `NSCollectionView` with two or more locally created, read-only preview fixtures;
- multiple selection enabled and visible selected-item diagnostics;
- a dedicated Quick Look responder/controller that owns `QLPreviewPanelDataSource` and `QLPreviewPanelDelegate` behavior;
- explicit responder-chain insertion between the portal window and `NSApplication`;
- Space with no selection is a no-op;
- Space with selection presents via the real shared `QLPreviewPanel` candidate call `makeKeyAndOrderFront(nil)`;
- Space while the panel is visible dismisses via `orderOut(nil)`;
- `beginPreviewPanelControl` assigns data source/delegate and reloads; `endPreviewPanelControl` clears only ownership that still belongs to this controller;
- selected preview items are returned in deterministic collection order, not Set iteration order;
- controller/window/fixture lifecycle has a clear strong owner and teardown removes temporary fixtures.

This phase is an ownership/responder bootstrap. It must not claim presentation, dismissal, carousel navigation, key-window transitions, desktop-level behavior, or cleanup are GUI-verified unless actually observed by a human.

## Window Scope

- Keep `NSWindow` only in 0.3A; do not add `NSPanel`.
- Provide two switchable public-API levels: normal and the existing candidate `desktopIconWindow + 1`.
- Keep key eligibility enabled for this bootstrap and document it as a controlled variable, not a final decision.
- Do not select a production window strategy or copy the Phase 0.1 implementation wholesale.

## Engineering Constraints

- Native Swift, AppKit, QuickLookUI; minimum macOS 15; Swift 6 strict concurrency.
- No third-party dependencies, private API, network, package installation, production Alcove modules, file mutation features, folder enumeration, persistence, tabs, or custom preview rendering.
- Do not use `QLPreviewPanel.shared().toggle(nil)`; that API is invalid.
- No `as!`, `try!`, normal-path force unwrap, fatal error for recoverable input, unchecked concurrency, or swallowed errors.
- Use a deterministic build/test entry point (small SwiftPM package or `swiftc` app build scripts) and explain the choice.
- Keep the change to roughly 3–8 implementation/test files where practical.

## Automated Verification

Actually clean, test, and build. Tests must meaningfully cover without presenting GUI as proven:

- ordered selection projection for zero, one, multiple, and out-of-range indices;
- preview count and preview URL mapping reflect the current selection;
- Space/no-selection produces no presentation request;
- visible/not-visible toggle decision is explicit and deterministic in a testable pure policy;
- begin assigns the real panel data source/delegate; end clears them and is safe if ownership changed;
- responder chain contains the Quick Look controller exactly once and reaches `NSApplication` without a cycle;
- replacing selection reloads owned visible panel state without stale items;
- teardown is idempotent and releases/removes fixture resources;
- structural checks reject unsafe syntax and invalid `shared().toggle` usage.

Tests may invoke lifecycle methods directly and inspect properties, but must call that automated lifecycle evidence, not proof that the system panel visually presented.

## Manual Checklist

Document all as not run (`NR`): single preview, multiple carousel, second-Space dismissal, selection changes while visible, Escape/close, normal level, desktop-candidate level, key-window handoff/return, focus after dismissal, common text/image/PDF types, app deactivate/reactivate, portal close while panel visible, and cleanup/reopen.

## Allowed Modifications

Only create or modify:

- `spikes/quick-look/`
- `docs/SPIKE_QUICK_LOOK.md`
- `.agent/results/phase-0.3a-quick-look-responder.md`

Do not modify HANDOFF, progress, README, `.gitignore`, baseline documents, existing spikes/docs, Memory, Git config, or Git history. Do not commit, push, reset, rebase, clean Git files, or alter remotes.

## Documentation

Create `docs/SPIKE_QUICK_LOOK.md` with:

```text
Status: In Progress — Phase 0.3A responder bootstrap only
```

Include structure, exact build/test/run commands, responder chain, ownership lifecycle, actual automated evidence, all manual items as `NR`, limitations, known issues, and an explicit statement that full Spike 0.3 is incomplete.

## Result Report

Create `.agent/results/phase-0.3a-quick-look-responder.md`, at most 120 lines:

1. Read/absent/failure paths.
2. Created/modified files.
3. Engineering form and reason.
4. Exact commands and exit codes.
5. Automated facts and limitations.
6. Unperformed GUI tests.
7. Known issues and three least-certain points.
8. Strict scope statement.
9. Explicit statement that full Spike 0.3 is incomplete.

Implement now. A prose-only response is a failure.
