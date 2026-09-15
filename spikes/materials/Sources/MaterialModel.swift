// MaterialModel.swift
// Alcove Spike 0.4A — Material Compatibility Boundary Bootstrap
// Pure material types and resolver; not production architecture.

import AppKit

enum BackgroundType: String, CaseIterable, Sendable {
    case liquidGlass = "liquid-glass"
    case frostedGlass = "frosted-glass"

    var description: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .frostedGlass: "Frosted Glass"
        }
    }

    var menuKeyEquivalent: String {
        switch self {
        case .liquidGlass: "1"
        case .frostedGlass: "2"
        }
    }
}

// MARK: - Resolved Material Path

/// The actual material construction path selected by the resolver.
enum ResolvedMaterialPath: String, Sendable {
    case glass = "glass"
    case frosted = "frosted"
    case opaqueAccessibility = "opaque-accessibility"

    var description: String {
        switch self {
        case .glass: return "Liquid Glass"
        case .frosted: return "Frosted Glass"
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

/// Pure resolver for the macOS 26+ Glass path and its accessibility override.
enum MaterialResolver {

    /// Resolve the material path from the given inputs.
    ///
    /// - Parameter accessibility: Current accessibility display options.
    /// - Returns: The resolved material path.
    static func resolve(
        backgroundType: BackgroundType,
        accessibility: AccessibilityDisplayOptions
    ) -> ResolvedMaterialPath {
        if accessibility.reduceTransparency {
            return .opaqueAccessibility
        }
        return switch backgroundType {
        case .liquidGlass: .glass
        case .frostedGlass: .frosted
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
