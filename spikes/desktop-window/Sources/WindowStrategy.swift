// WindowStrategy.swift
// Alcove Spike 0.1B — Desktop Window Strategy Model
// Disposable harness; not production architecture.

import AppKit
import CoreGraphics

// MARK: - Strategy Configuration

/// Typed, central representation of a window strategy's intended configuration.
///
/// Every dimension that affects desktop-layer window behavior is declared here
/// rather than scattered through menu actions or controllers. The presets below
/// compose these values into focused combinations.
enum SpaceBehavior: Equatable, Sendable {
    case stationary(joinsAllSpaces: Bool)
    case moveToActiveSpace
}

struct StrategyConfiguration: Equatable, Sendable {

    /// The window level to apply.
    let windowLevel: NSWindow.Level

    /// A typed Space behavior. Its shape keeps the semantically conflicting
    /// all-Spaces and move-to-active-Space modes out of the same preset.
    let spaceBehavior: SpaceBehavior?

    let isFullScreenAuxiliary: Bool
    let ignoresWindowCycle: Bool

    /// Whether the window is intended to be eligible to become key.
    /// Actual eligibility may differ; see `AlcoveSpikeWindow.canBecomeKey`.
    let isKeyEligible: Bool

    var collectionBehavior: NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = []
        switch spaceBehavior {
        case .stationary(let joinsAllSpaces):
            behavior.insert(.stationary)
            if joinsAllSpaces {
                behavior.insert(.canJoinAllSpaces)
            }
        case .moveToActiveSpace:
            behavior.insert(.moveToActiveSpace)
        case nil:
            break
        }
        if isFullScreenAuxiliary {
            behavior.insert(.fullScreenAuxiliary)
        }
        if ignoresWindowCycle {
            behavior.insert(.ignoresCycle)
        }
        return behavior
    }
}

// MARK: - Strategy Preset

/// Focused, reviewable strategy presets for the Spike 0.1 desktop-layer experiment.
///
/// Each preset is a named combination of `StrategyConfiguration` values that
/// exercises one or more comparison dimensions. The set is deliberately small —
/// it covers every required dimension without generating a Cartesian product.
///
/// Dimensions covered:
/// - `.stationary` — preset: `.desktopCandidate`, `.desktopCandidateNoJoinAllSpaces`
/// - `.moveToActiveSpace` — preset: `.desktopMoveToActiveSpace`
/// - `.fullScreenAuxiliary` — preset: `.desktopFullScreenAuxiliary`
/// - `.canJoinAllSpaces` present — preset: `.desktopCandidate`,
///   `.desktopFullScreenAuxiliary`
/// - `.canJoinAllSpaces` absent — preset: `.desktopCandidateNoJoinAllSpaces`,
///   `.desktopMoveToActiveSpace`
/// - Key-window eligible — preset: all except `.desktopNoKey`
/// - Key-window ineligible — preset: `.desktopNoKey`
///
/// Constraint: `.moveToActiveSpace` is never combined with `.stationary` or
/// `.canJoinAllSpaces`; the typed `SpaceBehavior` makes those invalid states
/// unrepresentable.
enum StrategyPreset: String, CaseIterable, Sendable {
    case normalBaseline = "normal-baseline"
    case desktopCandidate = "desktop-candidate"
    case desktopCandidateNoJoinAllSpaces = "desktop-no-join-all-spaces"
    case desktopMoveToActiveSpace = "desktop-move-to-active-space"
    case desktopNoKey = "desktop-no-key"
    case desktopFullScreenAuxiliary = "desktop-full-screen-auxiliary"

    /// Human-readable menu and diagnostics label.
    var description: String {
        switch self {
        case .normalBaseline: return "Normal Baseline"
        case .desktopCandidate: return "Desktop Candidate"
        case .desktopCandidateNoJoinAllSpaces: return "Desktop (No JoinAllSpaces)"
        case .desktopMoveToActiveSpace: return "Desktop (MoveToActiveSpace)"
        case .desktopNoKey: return "Desktop (No Key)"
        case .desktopFullScreenAuxiliary: return "Desktop (FullScreenAuxiliary)"
        }
    }

    /// Stable identifier for test assertions and diagnostics.
    var identifier: String { rawValue }

    /// Keyboard shortcut digit for menu items (1–6).
    var menuKeyEquivalent: String {
        switch self {
        case .normalBaseline:              return "1"
        case .desktopCandidate:            return "2"
        case .desktopCandidateNoJoinAllSpaces: return "3"
        case .desktopMoveToActiveSpace:    return "4"
        case .desktopNoKey:                return "5"
        case .desktopFullScreenAuxiliary:  return "6"
        }
    }

    /// Typed configuration — the single source of truth for this preset's intent.
    var configuration: StrategyConfiguration {
        switch self {

        case .normalBaseline:
            return StrategyConfiguration(
                windowLevel: .normal,
                spaceBehavior: nil,
                isFullScreenAuxiliary: false,
                ignoresWindowCycle: false,
                isKeyEligible: true
            )

        case .desktopCandidate:
            // Original Phase 0.1A desktop candidate — preserved exactly.
            return StrategyConfiguration(
                windowLevel: NSWindow.Level(
                    rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
                ),
                spaceBehavior: .stationary(joinsAllSpaces: true),
                isFullScreenAuxiliary: false,
                ignoresWindowCycle: true,
                isKeyEligible: true
            )

        case .desktopCandidateNoJoinAllSpaces:
            // Same as desktopCandidate but without .canJoinAllSpaces.
            return StrategyConfiguration(
                windowLevel: NSWindow.Level(
                    rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
                ),
                spaceBehavior: .stationary(joinsAllSpaces: false),
                isFullScreenAuxiliary: false,
                ignoresWindowCycle: true,
                isKeyEligible: true
            )

        case .desktopMoveToActiveSpace:
            // The typed mode cannot also carry .canJoinAllSpaces or .stationary.
            return StrategyConfiguration(
                windowLevel: NSWindow.Level(
                    rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
                ),
                spaceBehavior: .moveToActiveSpace,
                isFullScreenAuxiliary: false,
                ignoresWindowCycle: true,
                isKeyEligible: true
            )

        case .desktopNoKey:
            // Same desktop candidate but key-window ineligible.
            return StrategyConfiguration(
                windowLevel: NSWindow.Level(
                    rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
                ),
                spaceBehavior: .stationary(joinsAllSpaces: true),
                isFullScreenAuxiliary: false,
                ignoresWindowCycle: true,
                isKeyEligible: false
            )

        case .desktopFullScreenAuxiliary:
            // .fullScreenAuxiliary with .stationary (not .moveToActiveSpace).
            return StrategyConfiguration(
                windowLevel: NSWindow.Level(
                    rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
                ),
                spaceBehavior: .stationary(joinsAllSpaces: true),
                isFullScreenAuxiliary: true,
                ignoresWindowCycle: true,
                isKeyEligible: true
            )
        }
    }

    // MARK: - Derived Properties

    /// The window level from the configuration.
    var windowLevel: NSWindow.Level { configuration.windowLevel }

    /// The collection behavior from the configuration.
    var collectionBehavior: NSWindow.CollectionBehavior { configuration.collectionBehavior }

    /// Whether this preset intends the window to be key-eligible.
    var isKeyEligible: Bool { configuration.isKeyEligible }

    // MARK: - Diagnostics

    /// Human-readable description of the configured collection behavior flags.
    var configuredBehaviorDescription: String {
        Self.describeCollectionBehavior(configuration.collectionBehavior)
    }

    /// Human-readable description of the configured key eligibility.
    var configuredKeyEligibilityDescription: String {
        configuration.isKeyEligible ? "eligible" : "ineligible"
    }

    // MARK: - Helpers

    /// Describe a set of collection behavior flags as a comma-separated string.
    static func describeCollectionBehavior(_ b: NSWindow.CollectionBehavior) -> String {
        var parts: [String] = []
        if b.contains(.canJoinAllSpaces) { parts.append("canJoinAllSpaces") }
        if b.contains(.stationary) { parts.append("stationary") }
        if b.contains(.ignoresCycle) { parts.append("ignoresCycle") }
        if b.contains(.moveToActiveSpace) { parts.append("moveToActiveSpace") }
        if b.contains(.fullScreenAuxiliary) { parts.append("fullScreenAuxiliary") }
        if b.contains(.fullScreenPrimary) { parts.append("fullScreenPrimary") }
        if b.contains(.fullScreenNone) { parts.append("fullScreenNone") }
        if b.contains(.participatesInCycle) { parts.append("participatesInCycle") }
        if parts.isEmpty { return "none" }
        return parts.joined(separator: ", ")
    }
}
