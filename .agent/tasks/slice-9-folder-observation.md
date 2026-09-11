# Slice 9 — Folder Observation and Auto-Refresh

Observe only the selected tab with FSEvents `FileEvents`, `WatchRoot`, and
`UseCFTypes`. Debounce ordinary records into full snapshot reloads. Recovery
flags must stop the old stream, revalidate the mapped path and supported volume,
compare device/inode, reject replacements, restart a fresh stream before
enumeration, and suppress every stale generation. Stop on tab switch and close.
