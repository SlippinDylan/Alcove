# Phase 0.5C3 Path Evidence Result

Date: 2026-08-02
Status: Local path evidence complete; Spike 0.5 remains incomplete

## Delegation

One Claude Code 2.1.220 / MiMo call exited 0 without retry and stayed within the
allowlist. It created the recovery probe, tests, scripts, Spike document, and
report after reading the required global/project and prior Spike files.

MiMo's buildable initial result was not accepted. Its second evidence window
could never signal; replacement markers were conflated with move events;
Dispatch missing-root output was actually `unknown` while the report claimed a
typed error; teardown errors were swallowed into strings; and selective JSON
tests reported 128/128 despite those failures.

## Codex Repairs

Codex replaced the core evidence orchestration with one token per mutation,
canonical marker filtering for FSEvents, separate transition/old/replacement
windows, concrete enum-case error extraction, throwing bounded teardown,
independent initial/moved/replacement identity checks, strict Codable decoding,
probe-owned cleanup assertions, and typed timeout/watchdog tests.

## Final Verification

| Command | Result |
|---|---|
| `bash build.sh` | exit 0 |
| `bash test.sh` ×3 | 238 passed / 0 failed each |
| invalid script/probe arguments | exit 64 |
| FSEvents `symlink-root --timeout 0.001` | exit 1; named timeout; fixture removed |
| outer watchdog | process terminated before pipe read |

Artifact: arm64, minimum macOS 15.0, SDK 26.5, Apple system/Swift dependencies
only, linker-generated ad-hoc signature.

## Final Local Facts

- Both candidates returned real `ENOENT` categories for a missing root.
- Both observed a target marker when started through a symlink root.
- Both observed child symlink creation; neither reported external-target
  mutation in the bounded optional window.
- DispatchSource reported a moved-root marker; FSEvents did not in its bounded
  optional window after `RootChanged`.
- After pathname replacement, DispatchSource reported the old-inode marker and
  not the replacement marker; FSEvents reported the replacement marker and not
  the moved-old marker in the bounded local windows.
- Initial and moved identities matched; replacement identity differed;
  DispatchSource observed identity matched the original inode.
- All started runs stopped, all fixtures were removed before parent cleanup,
  and every FSEvents bridge count was zero.

## Scope

No existing candidate, baseline document, architecture, or production module
was changed. No observer is selected and no recovery policy is implemented.
Actual macOS 15, TCC, removable/network volumes, dropped/revoke recovery,
sustained load, and multiple-observer evidence remain open. Full Spike 0.5 is
incomplete.
