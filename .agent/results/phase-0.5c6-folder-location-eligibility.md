# Phase 0.5C6 — Folder Location Eligibility Result

## Outcome

The confirmed product rule is recorded and verified: Alcove accepts a mapped
folder only when its resolved hosting volume reports local/internal true and
removable/ejectable false. Every other or incomplete metadata state fails closed
before tab creation, re-mapping, or persistence.

## Files

- `spikes/folder-location-eligibility/` — pure policy, Foundation adapter, CLI,
  tests, and scripts.
- `docs/SPIKE_FOLDER_LOCATION_ELIGIBILITY.md` — evidence and gate status.
- Product requirements, architecture, delivery plan, research, README, HANDOFF,
  and progress were synchronized with the confirmed scope decision.
- The obsolete untracked virtual-volume 0.5C6 task, report, document, source,
  scripts, and ignored binaries were deleted with explicit user confirmation.

## Verification

- `bash -n build.sh test.sh`: exit 0.
- Three consecutive `bash test.sh` runs: exit 0; 20 assertions, 0 failures each;
  CLI checks passed each time.
- Standalone repository-path probe: exit 0 and eligible JSON.
- `file`, `vtool`, `otool`, and `codesign` inspection: arm64, macOS 15.0 minimum,
  SDK 26.5, system/Foundation/Swift dependencies, linker ad-hoc signature.
- `git diff --check`: exit 0.

## Actual Local Fact

The repository directory resolved on this macOS 26 runtime to
`isLocal=true`, `isInternal=true`, `isRemovable=false`, and
`isEjectable=false`, so the policy accepted it.

## Least-Certain Areas

1. The same public resource keys still require a real macOS 15 runtime check.
2. Unusual filesystem and File Provider configurations may omit volume metadata;
   the intentional behavior is rejection, not an eligibility guess.
3. The production `NSOpenPanel` flow does not exist yet; its integration must use
   this boundary before creating or updating persisted tab state.

## Gate

Unsupported-volume lifecycle work is removed from product scope. Phase 0.5C6 is
complete as folder-source policy evidence. Observer selection, controlled TCC
evidence, and dropped-event recovery remain open for full Spike 0.5.
