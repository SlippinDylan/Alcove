# Slice 10C — Folder Recovery

## Goal

Turn missing, replaced, unreadable, and permission-denied folder states into
explicit user-recoverable flows without silently adopting a same-path
replacement or weakening the fixed-internal-volume policy.

## Scope

- Present the affected path or folder with a concrete Locate Folder or Retry
  action.
- Reuse the standard directory-only `NSOpenPanel` for remapping.
- Revalidate every replacement through `FolderLocationValidator`.
- Preserve the durable tab identity while replacing only its mapped URL.
- Save the complete portal snapshot before updating its live window.
- Restart observation and loading after a successful remap or retry.
- Keep failed or cancelled remaps out of durable and live state.

## Exit Gate

- Error-to-action mapping and Locate dispatch tests pass.
- Successful and failed remap transaction tests pass.
- Full hosted tests and the unsigned universal Release build pass.
