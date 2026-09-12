import AlcoveCore
import AppKit

@MainActor
final class PortalCreationGridState {
    private(set) var grid: CreationGrid
    private(set) var iconLayout: PortalIconLayout

    init(grid: CreationGrid, iconLayout: PortalIconLayout = .fixed(.medium)) {
        self.grid = grid
        self.iconLayout = iconLayout
    }

}

@MainActor
final class PortalFrameSelector: PortalFrameSelecting {
    private let gridState: PortalCreationGridState
    private var activeOverlay: PortalCreationOverlayController?

    init(grid: CreationGrid) {
        gridState = PortalCreationGridState(grid: grid)
    }

    init(gridState: PortalCreationGridState) {
        self.gridState = gridState
    }

    func selectFrame() async -> PortalFrameSelection? {
        guard activeOverlay == nil else { return nil }
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let overlay = PortalCreationOverlayController(
                screen: screen,
                grid: gridState.grid,
                iconLayout: gridState.iconLayout
            ) {
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
    private var completion: ((PortalFrameSelection?) -> Void)?

    init(
        screen: NSScreen,
        grid: CreationGrid,
        iconLayout: PortalIconLayout,
        completion: @escaping (PortalFrameSelection?) -> Void
    ) {
        self.completion = completion
        let overlayView = PortalCreationOverlayView(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            grid: grid,
            iconLayout: iconLayout
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

    private func finish(_ selection: PortalFrameSelection?) {
        guard let completion else { return }
        self.completion = nil
        close()
        completion(selection)
    }
}

private final class PortalCreationOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PortalCreationOverlayView: NSView {
    var onCompletion: ((PortalFrameSelection?) -> Void)?

    private let screenFrame: NSRect
    private let visibleFrame: NSRect
    private let grid: CreationGrid
    private let iconLayout: PortalIconLayout
    private var mouseDownPoint: NSPoint?
    private(set) var selectedRectangle: CreationRectangle?
    private var didDrag = false
    private var growsPositiveX = true
    private var growsPositiveY = true

    init(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        grid: CreationGrid,
        iconLayout: PortalIconLayout = .fixed(.medium)
    ) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.grid = grid
        self.iconLayout = iconLayout
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(
            NSLocalizedString("Create portal area", comment: "Accessibility label for portal creation")
        )
        setAccessibilityHelp(
            NSLocalizedString(
                "Drag to choose a portal frame, or press Return to use a default frame.",
                comment: "Accessibility instructions for portal creation"
            )
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

        guard let selectedRectangle else { return }
        let localFrame = selectedRectangle.frame.offsetBy(
            dx: -screenFrame.minX,
            dy: -screenFrame.minY
        )
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        localFrame.fill()
        let path = NSBezierPath(rect: localFrame)
        path.lineWidth = 2
        path.setLineDash([8, 5], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
        drawSkeleton(in: localFrame, capacity: selectedRectangle.capacity)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = globalPoint(for: event)
        if let mouseDownPoint {
            selectedRectangle = defaultRectangle(around: mouseDownPoint)
        }
        didDrag = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint else { return }
        didDrag = true
        do {
            let currentPoint = globalPoint(for: event)
            growsPositiveX = currentPoint.x >= mouseDownPoint.x
            growsPositiveY = currentPoint.y >= mouseDownPoint.y
            selectedRectangle = try CreationGeometry.rectangle(
                mouseDown: mouseDownPoint,
                currentPoint: currentPoint,
                visibleFrame: visibleFrame,
                grid: grid
            )
            needsDisplay = true
        } catch {
            finish(nil)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard didDrag else {
            finish(selectedRectangle)
            return
        }
        mouseDragged(with: event)
        finish(selectedRectangle)
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
            selectedRectangle = try CreationGeometry.rectangle(
                mouseDown: CGPoint(x: center.x - halfWidth, y: center.y - halfHeight),
                currentPoint: CGPoint(x: center.x + halfWidth, y: center.y + halfHeight),
                visibleFrame: visibleFrame,
                grid: grid
            )
            finish(selectedRectangle)
            return true
        } catch {
            finish(nil)
            return false
        }
    }

    private func defaultRectangle(around point: NSPoint) -> CreationRectangle? {
        do {
            return try CreationGeometry.rectangle(
                mouseDown: CGPoint(
                    x: point.x - grid.minimumSize.width / 2,
                    y: point.y - grid.minimumSize.height / 2
                ),
                currentPoint: CGPoint(
                    x: point.x + grid.minimumSize.width / 2,
                    y: point.y + grid.minimumSize.height / 2
                ),
                visibleFrame: visibleFrame,
                grid: grid
            )
        } catch {
            return nil
        }
    }

    private func drawSkeleton(in frame: NSRect, capacity: GridCapacity) {
        let titleWidth = min(160, max(48, frame.width - 32))
        let titleFrame = NSRect(
            x: frame.midX - titleWidth / 2,
            y: frame.maxY - 34,
            width: titleWidth,
            height: 28
        )
        strokeDashed(titleFrame, cornerRadius: 14, alpha: 0.9)

        let pathWidth = min(260, max(80, frame.width - 32))
        let pathFrame = NSRect(
            x: frame.midX - pathWidth / 2,
            y: frame.minY + 6,
            width: pathWidth,
            height: 28
        )
        strokeDashed(pathFrame, cornerRadius: 14, alpha: 0.9)

        for row in 0..<capacity.rows {
            for column in 0..<capacity.columns {
                drawSlot(
                    row: row,
                    column: column,
                    in: frame,
                    alpha: 0.9
                )
            }
        }

        let columnProgress = selectedRectangle?.ghostColumnProgress ?? 0
        if columnProgress > 0 {
            let ghostColumn = growsPositiveX ? capacity.columns : -1
            for row in 0..<capacity.rows {
                drawSlot(
                    row: row,
                    column: ghostColumn,
                    in: frame,
                    alpha: 0.15 + columnProgress * 0.65
                )
            }
        }

        let rowProgress = selectedRectangle?.ghostRowProgress ?? 0
        if rowProgress > 0 {
            let row = growsPositiveY ? -1 : capacity.rows
            for column in 0..<capacity.columns {
                drawSlot(
                    row: row,
                    column: column,
                    in: frame,
                    alpha: 0.15 + rowProgress * 0.65
                )
            }
        }
    }

    private func drawSlot(
        row: Int,
        column: Int,
        in frame: NSRect,
        alpha: CGFloat
    ) {
        let metrics = grid.metrics
        let bodyTop = frame.maxY - PortalLayoutMetrics.tabBarHeight
        let tileFrame = NSRect(
            x: frame.minX + metrics.contentInsets.leading
                + CGFloat(column) * grid.columnIncrement,
            y: bodyTop - metrics.contentInsets.top - metrics.itemSize.height
                - CGFloat(row) * grid.rowIncrement,
            width: metrics.itemSize.width,
            height: metrics.itemSize.height
        )
        let iconFrame = NSRect(
            x: tileFrame.midX - metrics.iconSelectionSize.width / 2,
            y: tileFrame.maxY - metrics.iconSelectionSize.height,
            width: metrics.iconSelectionSize.width,
            height: metrics.iconSelectionSize.height
        )
        let labelFrame = NSRect(
            x: tileFrame.minX + 6,
            y: tileFrame.minY + 2,
            width: max(1, tileFrame.width - 12),
            height: max(8, metrics.labelHeight - 4)
        )
        strokeDashed(iconFrame, cornerRadius: 10, alpha: alpha)
        strokeDashed(labelFrame, cornerRadius: 6, alpha: alpha)
    }

    private func strokeDashed(
        _ rect: NSRect,
        cornerRadius: CGFloat,
        alpha: CGFloat
    ) {
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.lineWidth = 1.5
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private func globalPoint(for event: NSEvent) -> NSPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return NSPoint(
            x: localPoint.x + screenFrame.minX,
            y: localPoint.y + screenFrame.minY
        )
    }

    private func finish(_ rectangle: CreationRectangle?) {
        guard let onCompletion else { return }
        self.onCompletion = nil
        onCompletion(
            rectangle.map {
                PortalFrameSelection(
                    frame: $0.frame,
                    capacity: $0.capacity,
                    iconLayout: iconLayout
                )
            }
        )
    }
}
