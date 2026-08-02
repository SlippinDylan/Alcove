// AlcoveSpikeWindow.swift
// Alcove Spike 0.1B — Desktop Window Strategy Model
// Disposable harness; not production architecture.

import AppKit

/// Minimal NSWindow subclass that exposes configurable `canBecomeKey`.
///
/// Key-ineligible presets (e.g., `.desktopNoKey`) set `isKeyEligible = false`
/// so the window accurately returns `false` from `canBecomeKey`. This avoids
/// claiming a non-key-eligible window became key when it cannot.
final class AlcoveSpikeWindow: NSWindow {

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var canBecomeKey: Bool {
        isKeyEligible
    }
}
