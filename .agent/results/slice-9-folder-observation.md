# Slice 9 — Folder Observation and Auto-Refresh Result

The active Portal tab now owns one FSEvents stream configured with `FileEvents`,
`WatchRoot`, and `UseCFTypes`. Ordinary events debounce into complete folder
reloads. Drop/wrap/root-change evidence tears down the old stream and revalidates
the internal-volume path plus device/inode before restarting and refreshing.
Same-path replacements are rejected as folder replacement instead of adopted.

Automated verification completed on 2026-09-12:

- AlcoveCore: 110 tests, 0 failures.
- Hosted Alcove tests: 97 tests, 0 failures.
- Real FSEvents file creation triggered a refresh request.
- A real Portal grid changed from empty state to one displayed item after file creation.
- Swift 6 strict concurrency and warnings-as-errors compilation passed.
- Unsigned Release app built for arm64 and x86_64 with minimum macOS 15.0.

Controlled TCC denial, Locate Folder remapping UI, and manual rapid Finder/Tab
interaction remain open.
