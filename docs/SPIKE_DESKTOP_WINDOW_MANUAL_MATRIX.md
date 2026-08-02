# Spike 0.1 Manual Desktop-Window Matrix

Status: Not Run — procedure prepared; no GUI or system-transition result is recorded

This protocol records evidence that cannot be established by compilation, object-level tests, or process launch. It must be executed on a real logged-in macOS desktop. A result applies only to the recorded OS, display setup, and system configuration.

## 1. Result Vocabulary

Use exactly one value per matrix cell:

- `NR` — Not Run.
- `PASS` — Observed behavior satisfies every expectation in that scenario.
- `FAIL` — At least one expectation failed; attach an observation record.
- `BLOCKED` — The scenario could not be executed; record the exact blocker.
- `NA` — Scenario is genuinely not applicable; explain why.

Compilation, a live process, a configured flag, or a matching diagnostics label is never a GUI `PASS`.

## 2. Environment Record

Complete this before testing:

```text
Date/time:
Tester:
Hardware model:
CPU architecture:
macOS version/build:
Display count:
Display models/connections:
Display arrangement, resolution, and scaling:
Primary display:
Stage Manager initially enabled: yes/no
Separate Spaces per display: yes/no
Automatically rearrange Spaces: yes/no
Show Desktop shortcut/gesture:
Full-screen test application/version:
Build commit:
App binary SHA-256:
Notes:
```

Record the build identity:

```bash
git rev-parse HEAD
shasum -a 256 spikes/desktop-window/build/AlcoveSpike.app/Contents/MacOS/AlcoveSpike
sw_vers
system_profiler SPDisplaysDataType
```

Do not include serial numbers or other unnecessary personal identifiers in committed evidence.

## 3. Candidate Variants

Build once with `bash spikes/desktop-window/build.sh`. Use the app menus to select each independent class/strategy pair.

| ID | Class | Strategy menu item | Key intent |
|---|---|---|---|
| W-N | NSWindow | Normal Baseline | Eligible |
| W-D | NSWindow | Desktop Candidate | Eligible |
| W-J | NSWindow | Desktop (No JoinAllSpaces) | Eligible |
| W-M | NSWindow | Desktop (MoveToActiveSpace) | Eligible |
| W-K | NSWindow | Desktop (No Key) | Ineligible |
| W-F | NSWindow | Desktop (FullScreenAuxiliary) | Eligible |
| P-N | NSPanel | Normal Baseline | Eligible |
| P-D | NSPanel | Desktop Candidate | Eligible |
| P-J | NSPanel | Desktop (No JoinAllSpaces) | Eligible |
| P-M | NSPanel | Desktop (MoveToActiveSpace) | Eligible |
| P-K | NSPanel | Desktop (No Key) | Ineligible |
| P-F | NSPanel | Desktop (FullScreenAuxiliary) | Eligible |

## 4. Reset Procedure for Every Variant

1. Quit every previous Alcove Spike process.
2. Launch `spikes/desktop-window/build/AlcoveSpike.app`.
3. Select the required class with Command-7 or Command-8.
4. Select the required strategy with Command-1 through Command-6.
5. Choose Window > Recreate Window.
6. Confirm diagnostics show the expected configured class, actual concrete type, preset identifier, level, behavior, and key intent.
7. Place the window at a documented location on the primary display and record its frame.
8. Start one scenario. Do not carry an unexplained state change from a previous scenario.
9. After the scenario, capture diagnostics and visible evidence before resetting.

If configured and actual diagnostics disagree, record `FAIL`; do not continue treating the label as evidence.

## 5. Scenario Procedures

### S01 — Layer, Focus, Mouse, and Keyboard

1. Ensure Finder desktop icons are visible behind the candidate.
2. Observe whether the candidate is above or below Finder icons.
3. Place a normal application window over the candidate and observe ordering.
4. Click the candidate background, diagnostics text, and resize edge.
5. For eligible variants, choose Activate / Make Key and record `canBecomeKey`, `isKeyWindow`, and `isMainWindow` before and after.
6. For ineligible variants, choose Activate / Make Key and confirm it does not become key; record the actual flags.
7. Verify mouse input reaches the candidate and keyboard behavior matches its key intent.

Expected product direction: above Finder icons, below normal application windows, interactive, and honest about key state. This is a candidate expectation, not a pre-recorded result.

### S02 — Move, Resize, Close, and Recreate

1. Drag the titleless background by at least 200 points in each axis.
2. Resize from each edge and one corner to both smaller and larger frames.
3. Confirm delegate logs and diagnostics update after move and resize.
4. Close with the titlebar control, then use the application reopen path.
5. Close with Command-W, then use Window > Recreate Window.
6. Confirm a fresh window uses the same selected class and strategy without duplicate windows or stale events.

### S03 — Spaces

1. Create at least three Spaces with the candidate initially on Space 1.
2. Switch 1 → 2 → 3 → 1 using keyboard shortcuts, then using a trackpad or Mission Control.
3. On each Space, record visibility, location, animation, key state, and whether a duplicate appears.
4. For MoveToActiveSpace variants, explicitly record movement timing and destination.
5. Repeat once after moving the candidate to a secondary display if available.

### S04 — Show Desktop

1. Place a normal window above the candidate.
2. Trigger Show Desktop with the recorded shortcut or gesture.
3. Record candidate visibility, animation, ordering relative to icons, and frame.
4. Exit Show Desktop and record whether the candidate returns without flash, duplication, displacement, or permanent eviction.
5. Repeat twice to expose state accumulation.

### S05 — Mission Control

1. Enter Mission Control with the candidate visible.
2. Record whether and where it appears, its animation, and whether it can be selected.
3. Switch to another Space and return.
4. Exit Mission Control and compare frame, visibility, and focus flags with the precondition.
5. Repeat after the candidate has been closed and recreated.

### S06 — Stage Manager

1. Execute once with Stage Manager initially off.
2. Enable Stage Manager while the candidate is visible.
3. Switch among at least three application sets and click the desktop.
4. Record candidate visibility, grouping, ordering, animation, position, and input behavior.
5. Disable Stage Manager and record recovery.
6. Repeat from an initially enabled Stage Manager state.

### S07 — Full-Screen Application

1. Open the recorded test application in a normal window, then enter native full screen.
2. Move to its full-screen Space and record candidate visibility and ordering.
3. Return to a normal Space, then back to full screen.
4. Exit full screen and record candidate frame, visibility, focus, and duplicates.
5. For FullScreenAuxiliary variants, record whether observed behavior differs; do not infer causality from the label.

### S08 — Lock and Unlock

1. Record candidate frame, screen, visibility, key/main flags, and current Space.
2. Lock the Mac using the system command or menu.
3. Wait at least 30 seconds, then unlock normally.
4. Record first visible state, any flash or animation, final frame/screen, focus flags, and responsiveness.
5. Repeat once while the candidate is not key.

### S09 — Sleep and Wake

1. Record the same precondition as S08.
2. Put the Mac to sleep using the Apple menu; do not merely turn off the display.
3. Wait at least 60 seconds, wake, and unlock.
4. Record first visible state, recovery time, frame/screen, focus, duplicates, and event log.
5. Repeat once after changing Space before sleep.

### S10 — Deactivation and Panel Properties

1. Activate the candidate, then activate another application.
2. Record whether it remains visible and whether ordering changes.
3. For `NSPanel`, record the actual effect of `isFloatingPanel = false` and `hidesOnDeactivate = false`; do not restate configured values as observations.
4. Repeat activation/deactivation five times and check for focus theft, flashing, or accumulated windows.
5. Switch class while retaining the same strategy and compare only observed class-dependent differences.

## 6. Result Matrix

All cells start `NR`. Change a cell only after completing its full procedure and adding evidence where required.

| Variant | S01 | S02 | S03 | S04 | S05 | S06 | S07 | S08 | S09 | S10 |
|---|---|---|---|---|---|---|---|---|---|---|
| W-N | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| W-D | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| W-J | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| W-M | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| W-K | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| W-F | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| P-N | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| P-D | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| P-J | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| P-M | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| P-K | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| P-F | NR | NR | NR | NR | NR | NR | NR | NR | NR | NR |

## 7. Observation Record Template

Create one record for every `FAIL`, `BLOCKED`, or materially different observation:

```text
Record ID:
Variant / scenario:
Environment record reference:
Precondition:
Exact actions:
Expected candidate behavior:
Observed behavior:
Diagnostics before/after:
Window event log excerpt:
Screenshot or video path:
Reproducibility count:
Result: PASS / FAIL / BLOCKED / NA
Impact on product feasibility or architecture:
Follow-up:
```

Do not commit recordings containing unrelated personal data. Prefer cropped screenshots and short relevant log excerpts.

## 8. Decision Gate

Full Spike 0.1 remains `In Progress` until:

1. Every required matrix cell on the available hardware/OS matrix is resolved or explicitly blocked.
2. Failures are reproducible and documented.
3. A class, level, collection behavior, and key policy are selected from observations, or product feasibility is explicitly rejected/scoped.
4. `docs/ARCHITECTURE.md` is updated only after that evidence-backed decision.

This procedure alone does not satisfy the gate.
