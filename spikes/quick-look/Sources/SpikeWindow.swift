// SpikeWindow.swift
// Alcove Spike 0.3A — Quick Look Responder Bootstrap
// Disposable harness; not production architecture.

import AppKit
import CoreGraphics
import Quartz

enum PreviewWindowLevelStrategy: CaseIterable {
    case normal
    case desktopCandidate

    var name: String {
        switch self {
        case .normal: "Normal"
        case .desktopCandidate: "Desktop Candidate"
        }
    }

    var level: NSWindow.Level {
        switch self {
        case .normal:
            return .normal
        case .desktopCandidate:
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }
}

@MainActor
final class SpikeWindow: NSWindow {
    private(set) var quickLookResponder: QuickLookResponder?

    func installQuickLookResponder(_ responder: QuickLookResponder) {
        uninstallQuickLookResponder()
        let originalNextResponder = nextResponder ?? NSApp
        responder.nextResponder = originalNextResponder
        nextResponder = responder
        quickLookResponder = responder
        updateSharedPanelControllerIfNeeded()
    }

    func uninstallQuickLookResponder() {
        guard let responder = quickLookResponder else { return }
        if nextResponder === responder {
            nextResponder = responder.nextResponder
        }
        responder.nextResponder = nil
        quickLookResponder = nil
        updateSharedPanelControllerIfNeeded()
    }

    private func updateSharedPanelControllerIfNeeded() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else {
            return
        }
        panel.updateController()
    }
}
