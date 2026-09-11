# Slice 8A — Placement Core

Migrate the verified UI-free geometry and eviction-safe placement reducer from
Spike 0.2 into AlcoveCore without changing Portal or persistence schemas. Rename
the per-display saved value to `DisplayPlacementEntry` so the later multi-display
aggregate can retain the documented `PlacementRecord` responsibility. Preserve
the rule that only explicit user placement writes durable entries; topology
reconciliation may change transient presentation and emit window directives only.
