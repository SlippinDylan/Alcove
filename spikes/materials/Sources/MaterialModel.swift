// MaterialModel.swift
// Alcove Spike 0.4A — Material Compatibility Boundary Bootstrap
// Pure material types and resolver; not production architecture.

import AppKit

// MARK: - Material Preference

/// User-facing preference for how chrome material is selected.
enum MaterialPreference: String, CaseIterable, Sendable {
    case automatic = "automatic"
    case forceVisualEffectFallback = "force-visual-effect"

    var description: String {
        switch self {
        case .automatic: return "Automatic"
        case .forceVisualEffectFallback: return "Force Visual Effect Fallback"
        }
    }

    var menuKeyEquivalent: String {
        switch self {
        case .automatic: return "1"
        case .forceVisualEffectFallback: return "2"
        }
    }
}

// MARK: - Resolved Material Path

/// The actual material construction path selected by the resolver.
enum ResolvedMaterialPath: String, Sendable {
    case glass = "glass"
    case visualEffect = "visual-effect"
    case opaqueAccessibility = "opaque-accessibility"

    var description: String {
        switch self {
        case .glass: return "Liquid Glass (macOS 26)"
        case .visualEffect: return "NSVisualEffectView (fallback)"
        case .opaqueAccessibility: return "Opaque (accessibility)"
        }
    }
}

// MARK: - Accessibility Display Options

/// Snapshot of the accessibility display options relevant to material selection.
struct AccessibilityDisplayOptions: Equatable, Sendable {
    let reduceTransparency: Bool
    let increaseContrast: Bool

    /// Read current system accessibility display options.
    @MainActor
    static func current() -> AccessibilityDisplayOptions {
        let ws = NSWorkspace.shared
        return AccessibilityDisplayOptions(
            reduceTransparency: ws.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: ws.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

// MARK: - Material Resolver

/// Pure resolver that maps preference + runtime facts to a material path.
///
/// The resolver is independently testable: `supportsGlass` is injected so tests
/// can cover both the macOS 26 and macOS 15 branches without pretending the
/// current runtime is a different OS version.
enum MaterialResolver {

    /// Resolve the material path from the given inputs.
    ///
    /// - Parameters:
    ///   - preference: The user's material preference.
    ///   - supportsGlass: Whether the current runtime supports Glass APIs.
    ///     Runtime construction must still use `if #available(macOS 26.0, *)`.
    ///   - accessibility: Current accessibility display options.
    /// - Returns: The resolved material path.
    static func resolve(
        preference: MaterialPreference,
        supportsGlass: Bool,
        accessibility: AccessibilityDisplayOptions
    ) -> ResolvedMaterialPath {
        // Reduce Transparency always takes priority — use opaque path.
        if accessibility.reduceTransparency {
            return .opaqueAccessibility
        }

        switch preference {
        case .automatic:
            if supportsGlass {
                return .glass
            } else {
                return .visualEffect
            }
        case .forceVisualEffectFallback:
            return .visualEffect
        }
    }
}

// MARK: - Window Level Candidate

/// Candidate window levels for the spike harness.
enum WindowLevelCandidate: String, CaseIterable, Sendable {
    case normal = "normal"
    case desktopCandidate = "desktop-candidate"

    var description: String {
        switch self {
        case .normal: return "Normal"
        case .desktopCandidate: return "Desktop Candidate (desktopIconWindow + 1)"
        }
    }

    var menuKeyEquivalent: String {
        switch self {
        case .normal: return "3"
        case .desktopCandidate: return "4"
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .normal:
            return .normal
        case .desktopCandidate:
            return NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
            )
        }
    }
}
