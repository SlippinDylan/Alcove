# Phase 0.5C5 Result

## Reads and Scope

- MiMo reported `~/.codex/AGENTS.md` missing, but Codex independently confirmed
  that it exists and applied it. No repository AGENTS file exists.
- HANDOFF, all four baselines, and relevant Phase 0.5 sources/docs were read.
- Only `spikes/folder-access-errors/`, this report, and the Spike document were
  changed by the implementation task. Codex later updates HANDOFF/progress.
- No TCC/FDA change, protected-folder write, observer selection, production UI,
  dependency, private API, or Git operation was introduced by MiMo.

## Implementation and Review

- Read-only background enumeration for Desktop, Documents, and Downloads.
- Typed access categories retain raw NSError and underlying metadata.
- Owned accessible/missing/not-directory/permission fixtures include independent
  real POSIX directory-open evidence.
- Checked generations, bounded waits, permission restoration, transactional
  cleanup, active pipe draining, and TERM/SIGKILL subprocess convergence.
- MiMo's initial 46/46 was invalid: metadata was rewritten, failures were
  non-fatal, fixture I/O was on main, generation was self-proving, SIGINT was
  mislabeled as SIGKILL, and several tests did not exercise their claims.
- Codex replaced those paths. Independent review identified the original
  Critical/High/Medium issues before the rewrite.

## Commands and Exits

- `bash -n build.sh test.sh`: 0.
- Three final `bash test.sh` runs: 0, 0, 0; 124 assertions, 0 failures each.
- `protected-locations`, `fixtures`, and `all`: 0 with required JSON.
- No arguments, unknown command, and extra argument: 64, no success JSON.
- TERM-resistant watchdog child: real SIGKILL and bounded exit.
- `file`, `vtool`, `otool`, and `codesign`: 0.

## Actual Local Facts

- Desktop/Documents/Downloads enumeration succeeded with counts 30/12/9.
- Success is process/time-specific allowed access, not a TCC denial result.
- Missing enumeration: Cocoa 260 + OSStatus -43; independent open: ENOENT 2.
- File-as-directory: Cocoa 256 + POSIX 20; independent open: ENOTDIR 20.
- Mode-000 directory: Cocoa 257 + POSIX 13; independent open: EACCES 13.
- Every enumerated result ran off main and accepted a matching generation.
- Successful fixture processes restored permissions and left private TMPDIR empty.

## Least-Certain Areas

1. The responsible-process/TCC state behind current protected-folder success is
   not identified and can differ for a packaged Alcove app.
2. NSError wrapping can vary by macOS/filesystem; raw metadata must remain the
   source of truth rather than the current local wrapper shape.
3. No removable/network/ejection, induced dropped/revoke, or macOS 15 runtime
   evidence exists.

## Gate

Phase 0.5C5 is complete only as bounded local access/classifier evidence. It does
not validate TCC denial UI, volume errors, observer selection, or full Spike 0.5.
