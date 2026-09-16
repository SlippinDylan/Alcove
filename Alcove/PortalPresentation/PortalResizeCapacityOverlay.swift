import AlcoveCore
import AppKit

@MainActor
final class PortalResizeCapacityOverlay: NSView {
    var preview: GridCapacityPreview? {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let preview else { return }
        let committed = "\(preview.capacity.columns) × \(preview.capacity.rows)"
        let text: String
        if let candidate = preview.candidateCapacity {
            text = "\(committed)  →  \(candidate.columns) × \(candidate.rows)"
        } else {
            text = committed
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let badge = NSRect(
            x: bounds.midX - (textSize.width + 28) / 2,
            y: 14,
            width: textSize.width + 28,
            height: 32
        )
        NSColor.windowBackgroundColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 16, yRadius: 16).fill()
        let border = NSBezierPath(roundedRect: badge, xRadius: 16, yRadius: 16)
        border.lineWidth = 1.5
        border.setLineDash([5, 4], count: 2, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        border.stroke()
        attributedText.draw(
            at: NSPoint(
                x: badge.midX - textSize.width / 2,
                y: badge.midY - textSize.height / 2
            )
        )
    }
}
