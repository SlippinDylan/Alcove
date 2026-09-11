# Slice 8 — Display Placement Persistence

Integrate canonical display identity, per-display durable placement, v1-to-v2
migration, explicit user move/resize commits, and transient topology recovery.
System moves must never overwrite the remembered home placement. Preserve the
first v1 backup, serialize every durable mutation, retry confirmed user placement
after transient screen failure, observe screen changes and wake, and flush queued
mutations before termination.
