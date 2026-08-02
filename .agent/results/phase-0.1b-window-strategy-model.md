# Phase 0.1B — NSWindow Strategy Model Result

## 1. Successfully Read Instruction/Project Files

Successfully read:
- `~/.codex/AGENTS.md`
- `HANDOFF.md`
- `docs/PRODUCT_REQUIREMENTS.md`
- `docs/RESEARCH.md`
- `docs/ARCHITECTURE.md`
- `docs/DELIVERY_PLAN.md`
- `docs/SPIKE_DESKTOP_WINDOW.md`
- `spikes/desktop-window/Sources/main.swift`
- `spikes/desktop-window/Sources/AppDelegate.swift`
- `spikes/desktop-window/Sources/WindowStrategy.swift`
- `spikes/desktop-window/Sources/DiagnosticsView.swift`
- `spikes/desktop-window/Sources/ExperimentWindowController.swift`
- `spikes/desktop-window/build.sh`

Repository `AGENTS.override.md` and `AGENTS.md` were absent, so there was no repository instruction file to read. No requested existing file failed to read.

## 2. Created/Modified Files

| File | Action |
|------|--------|
| `spikes/desktop-window/Sources/WindowStrategy.swift` | Rewritten — `StrategyConfiguration` struct + `StrategyPreset` enum |
| `spikes/desktop-window/Sources/AlcoveSpikeWindow.swift` | Created — `NSWindow` subclass with configurable `canBecomeKey` |
| `spikes/desktop-window/Sources/DiagnosticsView.swift` | Rewritten — configured intent + actual state display |
| `spikes/desktop-window/Sources/ExperimentWindowController.swift` | Rewritten — uses `StrategyPreset` and `AlcoveSpikeWindow` |
| `spikes/desktop-window/Sources/AppDelegate.swift` | Rewritten — 6 preset menu entries via `switchPresetFromMenu` |
| `spikes/desktop-window/build.sh` | Updated — added `AlcoveSpikeWindow.swift` to SOURCES |
| `spikes/desktop-window/Tests/main.swift` | Created, then strengthened by Codex — 66 structural assertions |
| `spikes/desktop-window/test.sh` | Created — deterministic test build + run |
| `docs/SPIKE_DESKTOP_WINDOW.md` | Updated — Phase 0.1B documented |
| `.agent/results/phase-0.1b-window-strategy-model.md` | This file |

## 3. Model/Preset Design

**Why focused, not Cartesian:** Six presets cover every required dimension:

- `.stationary` — presets 2, 3, 5, 6
- `.moveToActiveSpace` — preset 4
- `.fullScreenAuxiliary` — preset 6
- `.canJoinAllSpaces` present — presets 2, 5, 6
- `.canJoinAllSpaces` absent — presets 1, 3, 4
- Key eligible — presets 1, 2, 3, 4, 6
- Key ineligible — preset 5

MiMo originally combined `.canJoinAllSpaces` with `.moveToActiveSpace`, giving one preset conflicting all-Spaces and move-to-active-Space intent. Codex review replaced the unchecked flag bag with a typed `SpaceBehavior`, keeping `.moveToActiveSpace` exclusive from both `.stationary` and `.canJoinAllSpaces`. This is a harness modeling choice, not proof of runtime Space behavior. Normal baseline and original desktop candidate remain preserved.

## 4. Test and Build Commands

Claude's CLI process produced the requested artifacts and report, but the outer zsh wrapper used the reserved variable name `status` and therefore returned 1 after Claude ended. The raw Claude exit code was not preserved; Codex accepted no claim from that wrapper and independently verified every artifact below.

| Command | Exit Code | Output |
|---------|-----------|--------|
| `bash build.sh` (app) | 0 | Clean compile, no errors, no warnings |
| `bash test.sh` (MiMo original tests) | 0 | 51 passed, 0 failed; missed the conflicting Space-semantics combination |
| `bash test.sh` (after Codex review) | 0 | 66 passed, 0 failed |
| Swift 6 strict-concurrency build after Codex review | 0 | Warnings treated as errors |

## 5. Automated Facts Established

1. Preset identifiers and names are unique (6 presets).
2. Normal Baseline has `.normal` level and empty collection behavior.
3. Desktop Candidate retains `desktopIconWindow + 1`, `.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`.
4. Preset set covers stationary, move-to-active-space, full-screen-auxiliary, both can-join-all-spaces values, and both key-eligibility values.
5. No preset combines `.stationary` or `.canJoinAllSpaces` with `.moveToActiveSpace`.
6. Every preset's emitted collection behavior matches an independently declared expected flag set.
7. All non-normal presets use `desktopIconWindow + 1` and include `.ignoresCycle`.
8. The concrete `NSWindow` subclass reports configured key eligibility for both allowed values.
9. Codex review added owner cleanup for both menu-driven and titlebar-driven window closes.
10. A concrete controller close test verifies the owner callback occurs exactly once.

## 6. Manual Behaviors Not Tested

All GUI and system-transition behaviors remain unverified: Show Desktop, Spaces, Mission Control, Stage Manager, full-screen, lock, sleep/wake, key-window activation, window move/resize, preset switching at runtime, diagnostics refresh, menu shortcuts, and recreation lifecycle.

## 7. Known Issues and Least-Certain Points

1. **NSPanel not compared.** Phase 0.1C deferred.
2. **No runtime key-window verification.** `AlcoveSpikeWindow.canBecomeKey` override is structurally correct but not GUI-tested.
3. **Single architecture (arm64).** Universal binary deferred to production.
4. **Three least-certain points:**
   - Whether `AlcoveSpikeWindow.canBecomeKey = false` actually prevents key-window status at runtime (requires GUI test).
   - Whether the `orderFront` activation path for non-key presets behaves correctly in every target system state (requires GUI test).
   - Whether the diagnostics display correctly updates `canBecomeKey` after preset switching (requires GUI test).

## 8. Modification Scope

Strictly followed. Only files within `spikes/desktop-window/`, `docs/SPIKE_DESKTOP_WINDOW.md`, and `.agent/results/` were modified or created. No modifications to HANDOFF.md, baseline documents, README, .gitignore, Memory files, ChatGPT export, .DS_Store, Git configuration, or Git history. No commit, push, reset, rebase, clean, or remote commands executed.

## 9. Phase 0.1C and Full Spike 0.1 Status

- **Phase 0.1C is not implemented.** `NSWindow` versus `NSPanel` comparison belongs to Phase 0.1C and has not been started.
- **Full Spike 0.1 remains incomplete.** Phase 0.1B added the strategy model, presets, diagnostics, and structural tests. Manual system-transition testing, Phase 0.1C, and the final architecture decision are still outstanding.
