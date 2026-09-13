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

    func updateIconSize(_ iconSize: IconSize) throws {
        grid = try CreationGrid(metrics: GridMetrics(iconSize: iconSize))
        iconLayout = .fixed(iconSize)
    }

}

@MainActor
final class PortalFrameSelector: PortalFrameSelecting {
    private let gridState: PortalCreationGridState
    private let occupiedFramesProvider: () -> [NSRect]
    private var activeOverlay: PortalCreationOverlayController?
    private var cornerRadius: CGFloat
    private var spacing: CGFloat

    init(
        grid: CreationGrid,
        cornerRadius: CGFloat = PortalCreationSkeletonGeometry.defaultCornerRadius,
        spacing: CGFloat = PortalFrameConstraints.defaultMinimumGap,
        occupiedFramesProvider: @escaping () -> [NSRect] = { [] }
    ) {
        gridState = PortalCreationGridState(grid: grid)
        self.cornerRadius = PortalCreationSkeletonGeometry.validatedCornerRadius(cornerRadius)
        self.spacing = max(0, spacing)
        self.occupiedFramesProvider = occupiedFramesProvider
    }

    init(
        gridState: PortalCreationGridState,
        cornerRadius: CGFloat = PortalCreationSkeletonGeometry.defaultCornerRadius,
        spacing: CGFloat = PortalFrameConstraints.defaultMinimumGap,
        occupiedFramesProvider: @escaping () -> [NSRect] = { [] }
    ) {
        self.gridState = gridState
        self.cornerRadius = PortalCreationSkeletonGeometry.validatedCornerRadius(cornerRadius)
        self.spacing = max(0, spacing)
        self.occupiedFramesProvider = occupiedFramesProvider
    }

    func updateCornerRadius(_ cornerRadius: CGFloat) {
        self.cornerRadius = PortalCreationSkeletonGeometry.validatedCornerRadius(cornerRadius)
        activeOverlay?.updateCornerRadius(self.cornerRadius)
    }

    func updateSpacing(_ spacing: CGFloat) {
        self.spacing = max(0, spacing)
        activeOverlay?.updateSpacing(self.spacing)
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
                iconLayout: gridState.iconLayout,
                cornerRadius: cornerRadius,
                spacing: spacing,
                occupiedFrames: occupiedFramesProvider()
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
        cornerRadius: CGFloat,
        spacing: CGFloat,
        occupiedFrames: [NSRect],
        completion: @escaping (PortalFrameSelection?) -> Void
    ) {
        self.completion = completion
        let overlayView = PortalCreationOverlayView(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            grid: grid,
            iconLayout: iconLayout,
            cornerRadius: cornerRadius,
            spacing: spacing,
            occupiedFrames: occupiedFrames
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

    func updateCornerRadius(_ cornerRadius: CGFloat) {
        (window?.contentView as? PortalCreationOverlayView)?.updateCornerRadius(cornerRadius)
    }

    func updateSpacing(_ spacing: CGFloat) {
        (window?.contentView as? PortalCreationOverlayView)?.updateSpacing(spacing)
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

struct PortalCreationSkeletonGeometry {
    static let defaultCornerRadius: CGFloat = 24

    let frame: NSRect
    let capacity: GridCapacity
    let cornerRadius: CGFloat
    let topSeparatorStart: NSPoint
    let topSeparatorEnd: NSPoint
    let bottomSeparatorStart: NSPoint
    let bottomSeparatorEnd: NSPoint
    let tileFrames: [NSRect]

    init(
        frame: NSRect,
        capacity: GridCapacity,
        grid: CreationGrid,
        cornerRadius: CGFloat = Self.defaultCornerRadius
    ) {
        self.frame = frame
        self.capacity = capacity
        self.cornerRadius = min(
            Self.validatedCornerRadius(cornerRadius),
            min(frame.width, frame.height) / 2
        )
        gridHorizontalSpacing = grid.metrics.horizontalSpacing
        gridVerticalSpacing = grid.metrics.verticalSpacing

        let topSeparatorY = frame.maxY - PortalLayoutMetrics.tabBarHeight
        topSeparatorStart = NSPoint(x: frame.minX, y: topSeparatorY)
        topSeparatorEnd = NSPoint(x: frame.maxX, y: topSeparatorY)

        let bottomSeparatorY = frame.minY + PortalLayoutMetrics.pathBarHeight
        bottomSeparatorStart = NSPoint(x: frame.minX, y: bottomSeparatorY)
        bottomSeparatorEnd = NSPoint(x: frame.maxX, y: bottomSeparatorY)

        tileFrames = (0..<capacity.rows).flatMap { row in
            (0..<capacity.columns).map { column in
                Self.makeTileFrame(row: row, column: column, frame: frame, grid: grid)
            }
        }
    }

    func tileFrame(row: Int, column: Int) -> NSRect {
        guard let firstTile = tileFrames.first else { return .zero }
        let columnStep = firstTile.width + gridHorizontalSpacing
        return NSRect(
            x: firstTile.minX + CGFloat(column) * columnStep,
            y: firstTile.maxY - CGFloat(row + 1) * firstTile.height - CGFloat(row) * gridVerticalSpacing,
            width: firstTile.width,
            height: firstTile.height
        )
    }

    static func validatedCornerRadius(_ cornerRadius: CGFloat) -> CGFloat {
        guard cornerRadius.isFinite else { return defaultCornerRadius }
        return max(0, cornerRadius)
    }

    private let gridHorizontalSpacing: CGFloat
    private let gridVerticalSpacing: CGFloat

    private static func makeTileFrame(
        row: Int,
        column: Int,
        frame: NSRect,
        grid: CreationGrid
    ) -> NSRect {
        let metrics = grid.metrics
        let bodyTop = frame.maxY - PortalLayoutMetrics.tabBarHeight
        return NSRect(
            x: frame.minX + metrics.contentInsets.leading
                + CGFloat(column) * grid.columnIncrement,
            y: bodyTop - metrics.contentInsets.top - metrics.itemSize.height
                - CGFloat(row) * grid.rowIncrement,
            width: metrics.itemSize.width,
            height: metrics.itemSize.height
        )
    }
}

@MainActor
final class PortalCreationOverlayView: NSView {
    var onCompletion: ((PortalFrameSelection?) -> Void)?

    private let screenFrame: NSRect
    private let visibleFrame: NSRect
    private let grid: CreationGrid
    private let iconLayout: PortalIconLayout
    private let occupiedFrames: [NSRect]
    private var cornerRadius: CGFloat
    private var spacing: CGFloat
    private var mouseDownPoint: NSPoint?
    private(set) var selectedRectangle: CreationRectangle?
    private var didDrag = false
    private var growsPositiveX = true
    private var growsPositiveY = true

    init(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        grid: CreationGrid,
        iconLayout: PortalIconLayout = .fixed(.medium),
        cornerRadius: CGFloat = PortalCreationSkeletonGeometry.defaultCornerRadius,
        spacing: CGFloat = PortalFrameConstraints.defaultMinimumGap,
        occupiedFrames: [NSRect] = []
    ) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.grid = grid
        self.iconLayout = iconLayout
        self.occupiedFrames = occupiedFrames
        self.cornerRadius = PortalCreationSkeletonGeometry.validatedCornerRadius(cornerRadius)
        self.spacing = max(0, spacing)
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
        let skeleton = PortalCreationSkeletonGeometry(
            frame: localFrame,
            capacity: selectedRectangle.capacity,
            grid: grid,
            cornerRadius: cornerRadius
        )
        let selectionPath = NSBezierPath(
            roundedRect: skeleton.frame,
            xRadius: skeleton.cornerRadius,
            yRadius: skeleton.cornerRadius
        )
        let isValid = isValidPlacement(selectedRectangle.frame)
        let selectionColor = isValid ? NSColor.controlAccentColor : NSColor.systemRed
        selectionColor.withAlphaComponent(0.15).setFill()
        selectionPath.fill()
        strokeDashed(
            skeleton.frame,
            cornerRadius: skeleton.cornerRadius,
            alpha: 1,
            lineWidth: 2,
            color: selectionColor
        )
        drawSkeleton(
            skeleton,
            selectedRectangle: selectedRectangle,
            color: selectionColor
        )
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
                visibleFrame: selectionBounds,
                grid: grid
            )
            needsDisplay = true
        } catch {
            finish(nil)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard didDrag else {
            if let selectedRectangle, isValidPlacement(selectedRectangle.frame) {
                finish(selectedRectangle)
            }
            return
        }
        mouseDragged(with: event)
        if let selectedRectangle, isValidPlacement(selectedRectangle.frame) {
            finish(selectedRectangle)
        }
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
                visibleFrame: selectionBounds,
                grid: grid
            )
            guard let selectedRectangle, isValidPlacement(selectedRectangle.frame) else {
                needsDisplay = true
                return false
            }
            finish(selectedRectangle)
            return true
        } catch {
            finish(nil)
            return false
        }
    }

    func updateCornerRadius(_ cornerRadius: CGFloat) {
        self.cornerRadius = PortalCreationSkeletonGeometry.validatedCornerRadius(cornerRadius)
        needsDisplay = true
    }

    func updateSpacing(_ spacing: CGFloat) {
        self.spacing = max(0, spacing)
        selectedRectangle = nil
        needsDisplay = true
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
                visibleFrame: selectionBounds,
                grid: grid
            )
        } catch {
            return nil
        }
    }

    private func drawSkeleton(
        _ skeleton: PortalCreationSkeletonGeometry,
        selectedRectangle: CreationRectangle,
        color: NSColor
    ) {
        strokeDashedLine(
            from: skeleton.topSeparatorStart,
            to: skeleton.topSeparatorEnd,
            alpha: 0.9,
            color: color
        )
        strokeDashedLine(
            from: skeleton.bottomSeparatorStart,
            to: skeleton.bottomSeparatorEnd,
            alpha: 0.9,
            color: color
        )

        skeleton.tileFrames.forEach {
            strokeDashed($0, cornerRadius: 12, alpha: 0.9, color: color)
        }

        let columnProgress = selectedRectangle.ghostColumnProgress
        if columnProgress > 0 {
            let ghostColumn = growsPositiveX ? skeleton.capacity.columns : -1
            for row in 0..<skeleton.capacity.rows {
                strokeDashed(
                    skeleton.tileFrame(row: row, column: ghostColumn),
                    cornerRadius: 12,
                    alpha: 0.15 + columnProgress * 0.65,
                    color: color
                )
            }
        }

        let rowProgress = selectedRectangle.ghostRowProgress
        if rowProgress > 0 {
            let row = growsPositiveY ? -1 : skeleton.capacity.rows
            for column in 0..<skeleton.capacity.columns {
                strokeDashed(
                    skeleton.tileFrame(row: row, column: column),
                    cornerRadius: 12,
                    alpha: 0.15 + rowProgress * 0.65,
                    color: color
                )
            }
        }
    }

    private func strokeDashed(
        _ rect: NSRect,
        cornerRadius: CGFloat,
        alpha: CGFloat,
        lineWidth: CGFloat = 1.5,
        color: NSColor = .controlAccentColor
    ) {
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.lineWidth = lineWidth
        path.setLineDash([6, 4], count: 2, phase: 0)
        color.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private func strokeDashedLine(
        from start: NSPoint,
        to end: NSPoint,
        alpha: CGFloat,
        color: NSColor
    ) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 1.5
        path.setLineDash([6, 4], count: 2, phase: 0)
        color.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private func globalPoint(for event: NSEvent) -> NSPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return NSPoint(
            x: localPoint.x + screenFrame.minX,
            y: localPoint.y + screenFrame.minY
        )
    }

    private var selectionBounds: NSRect {
        visibleFrame.insetBy(dx: spacing, dy: spacing)
    }

    private func isValidPlacement(_ frame: NSRect) -> Bool {
        (try? PortalFrameConstraints.isValidPlacement(
            frame: frame,
            visibleFrame: visibleFrame,
            otherPortalFrames: occupiedFrames,
            minimumGap: spacing
        )) == true
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
