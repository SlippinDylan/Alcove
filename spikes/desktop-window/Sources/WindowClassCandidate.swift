// WindowClassCandidate.swift
// Alcove Spike 0.1C — Desktop Window Class Comparison
// Disposable harness; not production architecture.

/// Typed window-class candidate for the Spike 0.1 desktop-layer experiment.
///
/// Exactly two cases: `NSWindow` and `NSPanel`. This enum is independent of
/// the strategy presets — every preset must be creatable with either class.
/// The window class is switchable at runtime and preserved across close/recreate.
enum WindowClassCandidate: String, CaseIterable, Sendable {
    case nsWindow = "ns-window"
    case nsPanel = "ns-panel"

    /// Human-readable label for menus and diagnostics.
    var displayName: String {
        switch self {
        case .nsWindow: return "NSWindow"
        case .nsPanel: return "NSPanel"
        }
    }

    /// Stable identifier for test assertions and diagnostics.
    var identifier: String { rawValue }

    /// Keyboard shortcut digit for menu items.
    var menuKeyEquivalent: String {
        switch self {
        case .nsWindow: return "7"
        case .nsPanel: return "8"
        }
    }
}
