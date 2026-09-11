# Slice 5B — Portal Store Result

- Added actor-isolated `PortalStore` and injectable filesystem boundary.
- Added human-readable, sorted-key, snake_case v1 envelope and separate DTOs.
- DTO restoration validates AlcoveCore Portal invariants.
- Missing file loads empty; malformed, future version, invalid portal, read,
  write, and combined write/cleanup failures are typed.
- New saves move a same-directory temp file; existing saves use atomic replace.
- Replacement-failure test proves the old store remains and temp is removed.
- Hosted app suite: 33 tests, 0 failures.
- No migration, backup policy, app restoration, or frame observation added yet.
