# Slice 7 — Quick Look

Add production `QLPreviewPanel` integration for the active tab. Space with an
ordered non-empty grid selection presents the shared panel; Space with no
selection is a no-op; a second Space dismisses only an Alcove-owned visible
panel. Keep panel ownership explicit, relinquish it on tab changes, restore the
window responder chain exactly on detach, and never clear references taken over
by another responder. Cover behavior without requiring system UI presentation.
