import AlcoveCore
import AppKit

@MainActor
final class PortalFrameSelector: PortalFrameSelecting {
    private let grid: CreationGrid
    private var activeOverlay: PortalCreationOverlayController?

    init(grid: CreationGrid) {
        self.grid = grid
    }

    func selectFrame() async -> NSRect? {
        guard activeOverlay == nil else { return nil }
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let overlay = PortalCreationOverlayController(screen: screen, grid: grid) {
                [weak self] frame in
                self?.activeOverlay = nil
                continuation.resume(returning: frame)
            }
            activeOverlay = overlay
            overlay.present()
        }
    }

    func cancel() {
        activeOverlay?.cancel()
    }
}

@MainActor
private final class PortalCreationOverlayController: NSWindowController {
    private var completion: ((NSRect?) -> Void)?

    init(
        screen: NSScreen,
        grid: CreationGrid,
        completion: @escaping (NSRect?) -> Void
    ) {
        self.completion = completion
        let overlayView = PortalCreationOverlayView(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            grid: grid
        )
        let window = PortalCreationOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = overlayView
        super.init(window: window)
        overlayView.onCompletion = { [weak self] frame in
            self?.finish(frame)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ frame: NSRect?) {
        guard let completion else { return }
        self.completion = nil
        close()
        completion(frame)
    }
}

private final class PortalCreationOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PortalCreationOverlayView: NSView {
    var onCompletion: ((NSRect?) -> Void)?

    private let screenFrame: NSRect
    private let visibleFrame: NSRect
    private let grid: CreationGrid
    private var mouseDownPoint: NSPoint?
    private var selectedFrame: NSRect?
    private var didDrag = false

    init(screenFrame: NSRect, visibleFrame: NSRect, grid: CreationGrid) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.grid = grid
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Create portal area")
        setAccessibilityHelp(
            "Drag to choose a portal frame, or press Return to use a default frame."
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        dirtyRect.fill()

        guard let selectedFrame else { return }
        let localFrame = selectedFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        localFrame.fill()
        let path = NSBezierPath(rect: localFrame)
        path.lineWidth = 2
        path.setLineDash([8, 5], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = globalPoint(for: event)
        selectedFrame = nil
        didDrag = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint else { return }
        didDrag = true
        do {
            selectedFrame = try CreationGeometry.rectangle(
                mouseDown: mouseDownPoint,
                currentPoint: globalPoint(for: event),
                visibleFrame: visibleFrame,
                grid: grid
            ).frame
            needsDisplay = true
        } catch {
            finish(nil)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard didDrag else {
            finish(nil)
            return
        }
        mouseDragged(with: event)
        finish(selectedFrame)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finish(nil)
        } else if event.keyCode == 36 || event.keyCode == 76 {
            _ = selectDefaultFrame()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        selectDefaultFrame()
    }

    @discardableResult
    func selectDefaultFrame() -> Bool {
        let center = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        let halfWidth = grid.minimumSize.width / 2
        let halfHeight = grid.minimumSize.height / 2
        do {
            let frame = try CreationGeometry.rectangle(
                mouseDown: CGPoint(x: center.x - halfWidth, y: center.y - halfHeight),
                currentPoint: CGPoint(x: center.x + halfWidth, y: center.y + halfHeight),
                visibleFrame: visibleFrame,
                grid: grid
            ).frame
            selectedFrame = frame
            finish(frame)
            return true
        } catch {
            finish(nil)
            return false
        }
    }

    private func globalPoint(for event: NSEvent) -> NSPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return NSPoint(
            x: localPoint.x + screenFrame.minX,
            y: localPoint.y + screenFrame.minY
        )
    }

    private func finish(_ frame: NSRect?) {
        guard let onCompletion else { return }
        self.onCompletion = nil
        onCompletion(frame)
    }
}
