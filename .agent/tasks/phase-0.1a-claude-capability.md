# Phase 0.1A — Claude Capability Validation

You are the bounded implementation agent for a disposable Alcove spike harness. Codex owns architecture, review, independent verification, and any follow-up fixes. Do not expand this task into production Alcove code or claim that Spike 0.1 is resolved.

## Read First

Read only the project context needed for this task:

1. `HANDOFF.md`
2. `docs/PRODUCT_REQUIREMENTS.md`, focusing on desktop-window scope
3. `docs/RESEARCH.md`, focusing on window evidence classification
4. `docs/ARCHITECTURE.md`, focusing on the provisional window strategy
5. `docs/DELIVERY_PLAN.md`, focusing on Spike 0.1

The baseline documents are read-only. They describe a candidate architecture, not locked production architecture.

## Modification Boundary

You may create or modify only:

```text
spikes/desktop-window/
docs/SPIKE_DESKTOP_WINDOW.md
.agent/results/phase-0.1a-claude-result.md
```

Do not modify, delete, or rename any other file, including the task file, log file, `HANDOFF.md`, the four baseline documents, `.engramory-memory/`, `.DS_Store`, `README.md`, or any other existing project document. Do not create a formal Alcove Xcode project at repository root. Do not create a Git commit.

## Task Positioning

Create a minimal, disposable, buildable, runnable AppKit desktop-window experiment that can become the starting point for the later full Spike 0.1.

This Phase 0.1A validates only whether you can:

- create a correct small macOS project;
- use public AppKit APIs;
- implement two switchable window strategies;
- actually build the result; and
- honestly distinguish automated verification from manual verification.

This does not resolve or complete Spike 0.1.

## Project Form

Put all experiment source under `spikes/desktop-window/`.

Choose either:

- a minimal Xcode project; or
- SwiftPM/`swiftc` plus a deterministic `.app` build script.

State why you chose that form. The result must use native Swift and AppKit, have a minimum deployment target of macOS 15, and build with the existing local Apple toolchain.

## Technical Constraints

- Use only native Swift, AppKit, Foundation, and other public Apple framework APIs needed for the specified diagnostics.
- Minimum deployment target: macOS 15.
- Do not install Homebrew tools.
- Do not add third-party dependencies.
- Do not use private APIs.
- Do not copy TileTop, Pocket Finder, or any other reference-project source.
- Do not create `AlcoveApp`, `AlcoveCore`, or any formal production module.
- Do not implement a file grid, tabs, Quick Look, persistence, directory observation, multi-display restoration, or any other production feature.
- Avoid force unwraps, `as!`, swallowed errors, and obvious crash paths.

## Window Requirements

Provide at least one experiment window that:

- is movable and resizable;
- has no traditional title bar, or uses an experiment-appropriate titleless style;
- displays a translucent background using `NSVisualEffectView` or an equivalent public AppKit material;
- can become key;
- receives mouse and keyboard events; and
- has an explicit, stable controller/window lifecycle with strong ownership where required.

## Two Switchable Strategies

Define the strategy centrally, for example:

```swift
enum WindowStrategy {
    case normalBaseline
    case desktopCandidate
}
```

Strategy A, Normal Baseline:

- use a normal window level;
- use default or minimal collection behavior;
- serve only as the comparison control.

Strategy B, Desktop Candidate:

- use this first candidate level:

```swift
NSWindow.Level(
    rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
)
```

- use this candidate collection behavior:

```swift
[
    .canJoinAllSpaces,
    .stationary,
    .ignoresCycle
]
```

This is only the initial Phase 0.1 candidate. Code, UI text, comments, and documents must not describe it as final or selected production behavior.

## Required Operations

Provide simple controls and/or menu commands for all of the following:

- switch to Normal Baseline;
- switch to Desktop Candidate;
- activate the app and make the experiment window key;
- close the experiment window;
- recreate the experiment window after it was closed; and
- quit the application.

Closing and recreating must work without relying on a dangling or deallocated controller.

## Diagnostics

Display at least these live values inside the window:

- current strategy name;
- current window type;
- current window-level numeric value;
- current collection behavior;
- `isKeyWindow`;
- `isMainWindow`;
- current window frame;
- current `NSScreen.frame`;
- current `NSScreen.visibleFrame`;
- current display ID or another screen identifier obtainable from public API; and
- current activation policy.

The values must be read from the actual current window, screen, and application state. Refresh them on relevant changes.

Log at least these real delegate/notification events:

- `windowDidBecomeKey`
- `windowDidResignKey`
- `windowDidBecomeMain`
- `windowDidResignMain`
- `windowDidMove`
- `windowDidResize`
- `windowDidChangeScreen`
- application activation
- application deactivation

Logs may appear in the window and/or standard output.

## Build and Verification

Actually execute the deterministic build command before reporting completion. Do not report a successful build unless the command returned exit code 0. If practical, run any non-GUI smoke check supported by the chosen form. Do not claim GUI behavior, window layering, Spaces behavior, or key-window behavior was verified unless you personally exercised and observed it.

## Spike Document

Create `docs/SPIKE_DESKTOP_WINDOW.md`. Its first status declaration must be exactly:

```text
Status: In Progress — Phase 0.1A bootstrap only
```

Include:

- this round's goal;
- project structure;
- build command;
- run command;
- both window strategies;
- automated verification actually executed;
- manual verification not yet executed;
- known issues;
- strategies still required for the full Spike 0.1; and
- an explicit statement that Phase 0.1 is not complete.

The future comparison list must include at least:

- `.stationary`;
- `.moveToActiveSpace`;
- `.fullScreenAuxiliary`;
- using and omitting `.canJoinAllSpaces`;
- `NSWindow` versus `NSPanel`; and
- allowing or prohibiting key-window eligibility.

The unchecked manual verification list must include at least:

- level relative to Finder desktop icons;
- whether normal application windows cover it;
- clicking, moving, and resizing;
- Space switching;
- Show Desktop;
- Mission Control;
- Stage Manager;
- full-screen applications;
- lock/unlock; and
- sleep/wake.

Anything you did not personally execute must remain explicitly unverified.

## Implementation Report

Create `.agent/results/phase-0.1a-claude-result.md`, no more than 120 lines, containing:

1. Files created or modified.
2. Project form and why it was selected.
3. Exact build command actually run.
4. Build exit result.
5. Automated tests/checks actually run.
6. Manual tests not run.
7. Known issues.
8. The three areas you are least confident about.
9. Whether the modification boundary was strictly followed.
10. An explicit statement that the full Spike 0.1 remains incomplete.

Before finishing, inspect your own changed paths and ensure every created file is within the allowed boundary. Keep the implementation compact and maintainable; this is a disposable harness, not production architecture.
