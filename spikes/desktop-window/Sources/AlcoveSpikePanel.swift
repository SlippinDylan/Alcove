// AlcoveSpikePanel.swift
// Alcove Spike 0.1C — Desktop Window Class Comparison
// Disposable harness; not production architecture.

import AppKit

/// Minimal NSPanel subclass that exposes configurable `canBecomeKey`.
///
/// Key-ineligible presets set `isKeyEligible = false` so the panel accurately
/// returns `false` from `canBecomeKey`. This avoids claiming a non-key-eligible
/// panel became key when it cannot.
///
/// Experimental panel property choices (not final behavior):
/// - `isFloatingPanel = false` — disables the panel's floating-panel flag while
///   the explicit window level remains the ordering input under test.
/// - `hidesOnDeactivate = false` — requests that deactivation not automatically
///   hide the panel. Actual visibility still requires manual observation.
///
/// Neither property is a confirmed production decision; both require manual
/// testing against Show Desktop, Spaces, Stage Manager, and system transitions.
final class AlcoveSpikePanel: NSPanel {

    /// Controls the return value of `canBecomeKey`.
    /// Set during initialization from the strategy preset.
    private let isKeyEligible: Bool

    init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool,
        isKeyEligible: Bool
    ) {
        self.isKeyEligible = isKeyEligible
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        // Experimental: disable NSPanel floating behavior while level remains
        // an independent strategy input. Not a production decision.
        isFloatingPanel = false

        // Experimental request: do not hide automatically on deactivation.
        // Actual visibility is not established without manual observation.
        hidesOnDeactivate = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var canBecomeKey: Bool {
        isKeyEligible
    }
}
