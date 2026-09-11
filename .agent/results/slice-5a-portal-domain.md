# Slice 5A — Portal Domain Result

- Added non-Codable `PortalID`, `FolderTabID`, `FolderTab`, and `Portal` values.
- Tab array order is the sole creation-order representation.
- Portal construction rejects empty/duplicate tabs, unknown selection, and
  invalid frames.
- Tab append/select/remove and frame/icon updates preserve aggregate invariants.
- `swift test --package-path Packages/AlcoveCore`: 34 tests, 0 failures.
- No persistence DTO, file I/O, migration framework, or app integration added.
