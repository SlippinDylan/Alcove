Status: Complete — Phase 0.5C6 folder-source policy evidence

# Spike 0.5C6 — Folder Location Eligibility

## Product Decision

Alcove accepts mapped folders only when the resolved directory is hosted on the
Mac's internal, fixed local storage. Folder selection and re-mapping reject
removable, ejectable, external, and network-volume locations before creating or
persisting a tab.

## Harness

The disposable harness reads public Foundation URL resource values:

- `volumeIsLocal`
- `volumeIsInternal`
- `volumeIsRemovable`
- `volumeIsEjectable`

Eligibility requires all four values to be present and equal to `true`, `true`,
`false`, and `false`, respectively. Missing metadata fails closed. Symbolic links
are resolved before directory and hosting-volume validation.

```bash
cd spikes/folder-location-eligibility
bash build.sh
bash test.sh
build/folder-location-probe /path/to/directory
```

## Boundary

This spike validates folder-source eligibility only. It does not implement the
production `NSOpenPanel` flow, select DispatchSource or FSEvents, alter TCC
permissions, or claim behavior for unsupported volumes. Historical removable-
volume experiments are not required for the product gate after this scope
decision.

## Automated Verification

Three consecutive final `bash test.sh` runs each passed 20 assertions with zero
failures, followed by successful CLI checks. Coverage includes:

- the one accepted metadata combination;
- non-local, non-internal, removable, and ejectable rejection;
- fail-closed behavior when any required metadata value is absent;
- a real temporary directory on the current internal volume;
- symlink resolution before volume classification;
- regular-file and missing-path rejection;
- fixture cleanup and invalid CLI arguments.

The standalone probe classified the repository directory with actual metadata:
`isLocal=true`, `isInternal=true`, `isRemovable=false`, and
`isEjectable=false`. The resulting decision was eligible. This is a local fact
from the current macOS 26 runtime, not a cross-version API-behavior guarantee.

The probe is an arm64 Mach-O with minimum macOS 15.0, SDK 26.5, Foundation and
system/Swift runtime dependencies only, and a linker-generated ad-hoc signature.

## Gate Status

The product-scope question for removable, ejectable, external, and network
volume folders is resolved by explicit rejection rather than lifecycle support.
Spike 0.5 still requires the observer selection, controlled TCC evidence, and
dropped-event recovery decision before the product-and-architecture gate closes.
