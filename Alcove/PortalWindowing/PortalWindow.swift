import AppKit

final class PortalWindow: NSWindow {
    private let keyEligibility: Bool

    init(
        contentRect: NSRect,
        strategy: PortalWindowStrategy,
        contentViewController: NSViewController
    ) {
        keyEligibility = strategy.canBecomeKey
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        level = strategy.level
        collectionBehavior = strategy.collectionBehavior
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 240, height: 240)
        self.contentViewController = contentViewController
    }

    override var canBecomeKey: Bool {
        keyEligibility
    }
}
