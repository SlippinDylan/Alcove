# Slice 5B — Portal Store

Implement the versioned v1 JSON persistence boundary with separate Codable
DTOs, domain validation, ordered portal round trips, missing-file empty state,
explicit corruption/future-version failures, and same-directory atomic commit.
Writing failures must preserve the prior store and clean temporary files. Do not
add migrations before a real v2 exists.
