// WindowStrategy.swift
// Alcove Spike 0.1 — Desktop Window Experiment
// Disposable harness; not production architecture.

import AppKit
import CoreGraphics

/// Switchable window-strategy candidates for the Spike 0.1 desktop-layer experiment.
///
/// Phase 0.1A defines two strategies:
/// - `normalBaseline`: standard window level — comparison control only.
/// - `desktopCandidate`: `desktopIconWindow + 1` with `.canJoinAllSpaces`,
///   `.stationary`, `.ignoresCycle` — initial Phase 0.1 candidate, not final.
enum WindowStrategy: String, CaseIterable {
    case normalBaseline = "Normal Baseline"
    case desktopCandidate = "Desktop Candidate"

    /// Human-readable description for diagnostics display.
    var description: String { rawValue }

    /// The NSWindow.Level to apply.
    var windowLevel: NSWindow.Level {
        switch self {
        case .normalBaseline:
            return .normal
        case .desktopCandidate:
            // desktopIconWindow + 1: initial candidate from research, not final.
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    /// The collection behavior flags to apply.
    var collectionBehavior: NSWindow.CollectionBehavior {
        switch self {
        case .normalBaseline:
            return []
        case .desktopCandidate:
            return [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }
}
