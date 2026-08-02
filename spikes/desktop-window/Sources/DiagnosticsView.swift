// DiagnosticsView.swift
// Alcove Spike 0.1C — Desktop Window Class Comparison
// Disposable harness; not production architecture.

import AppKit

/// Lightweight diagnostics label that displays both configured intent and actual
/// window state as attributed monospace text. Refreshed by the window controller
/// on every relevant delegate/notification event.
///
/// Phase 0.1B adds: preset identifier, configured key eligibility, actual
/// `canBecomeKey`, actual window type, and a clear intent-vs-actual distinction.
final class DiagnosticsView: NSTextField {

    // MARK: - Initialization

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Configuration

    private func configure() {
        isEditable = false
        isBordered = false
        isSelectable = true
        drawsBackground = true
        backgroundColor = NSColor(white: 0.12, alpha: 1.0)
        textColor = NSColor(white: 0.9, alpha: 1.0)
        font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        lineBreakMode = .byClipping
        maximumNumberOfLines = 0
        preferredMaxLayoutWidth = 580
        translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Content Update

    /// Rebuilds the diagnostics display showing both configured intent and actual state.
    func refresh(
        preset: StrategyPreset,
        windowClass: WindowClassCandidate,
        window: NSWindow?,
        actualCanBecomeKey: Bool,
        activationPolicy: NSApplication.ActivationPolicy
    ) {
        let screen = window?.screen ?? NSScreen.main
        let isKey = window?.isKeyWindow ?? false
        let isMain = window?.isMainWindow ?? false
        let canBecomeMain = window?.canBecomeMain ?? false
        let frame = window?.frame ?? .zero
        let screenFrame = screen?.frame ?? .zero
        let visibleFrame = screen?.visibleFrame ?? .zero
        let displayID = screen.flatMap { screen -> CGDirectDisplayID? in
            let desc = screen.deviceDescription
            guard let screenNumber = desc[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return CGDirectDisplayID(screenNumber.uint32Value)
        }

        let actualBehaviorStr = StrategyPreset.describeCollectionBehavior(
            window?.collectionBehavior ?? []
        )
        let activationStr = describeActivationPolicy(activationPolicy)
        let displayIDStr = displayID.map { String($0) } ?? "N/A"
        let windowType = window.map { String(describing: type(of: $0)) } ?? "N/A"

        let text = """
            === CONFIGURED INTENT ===
            Preset: \(preset.identifier)
            Window Class: \(windowClass.displayName)
            Configured Level: \(preset.windowLevel.rawValue)
            Configured Behavior: \(preset.configuredBehaviorDescription)
            Configured Key Eligibility: \(preset.configuredKeyEligibilityDescription)

            === ACTUAL STATE ===
            Window Type: \(windowType)
            Window Level: \(window?.level.rawValue ?? -1)
            Actual Behavior: \(actualBehaviorStr)
            canBecomeKey: \(actualCanBecomeKey)
            canBecomeMain: \(canBecomeMain)
            isKeyWindow: \(isKey)
            isMainWindow: \(isMain)

            === GEOMETRY ===
            Window Frame: \(formatRect(frame))
            Screen Frame: \(formatRect(screenFrame))
            Visible Frame: \(formatRect(visibleFrame))
            Display ID: \(displayIDStr)
            Activation Policy: \(activationStr)
            """
        attributedStringValue = makeAttributedText(text)
    }

    // MARK: - Formatting Helpers

    private func formatRect(_ r: NSRect) -> String {
        String(
            format: "(%.1f, %.1f, %.1f, %.1f)",
            r.origin.x, r.origin.y, r.size.width, r.size.height
        )
    }

    private func describeActivationPolicy(_ p: NSApplication.ActivationPolicy) -> String {
        switch p {
        case .regular: return "regular"
        case .accessory: return "accessory"
        case .prohibited: return "prohibited"
        @unknown default: return "unknown"
        }
    }

    private func makeAttributedText(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(white: 0.9, alpha: 1.0),
            .paragraphStyle: paragraph,
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }
}
