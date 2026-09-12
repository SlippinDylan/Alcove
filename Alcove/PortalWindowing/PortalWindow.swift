import AppKit

struct PortalWindowUserPlacementTracker {
    private var initialPointer: NSPoint?
    private var initialFrame: NSRect?
    private var latestFrame: NSRect?
    private var receivedDragEvent = false

    var isTracking: Bool {
        initialPointer != nil
    }

    mutating func begin(at pointer: NSPoint, frame: NSRect) {
        initialPointer = pointer
        initialFrame = frame
        latestFrame = frame
        receivedDragEvent = false
    }

    mutating func drag(to pointer: NSPoint) -> NSRect? {
        guard let initialPointer, let initialFrame else {
            return nil
        }

        receivedDragEvent = true
        let frame = initialFrame.offsetBy(
            dx: pointer.x - initialPointer.x,
            dy: pointer.y - initialPointer.y
        )
        latestFrame = frame
        return frame
    }

    mutating func finish() -> NSRect? {
        defer {
            initialPointer = nil
            initialFrame = nil
            latestFrame = nil
            receivedDragEvent = false
        }
        guard receivedDragEvent else {
            return nil
        }
        return latestFrame
    }

    mutating func cancel() {
        initialPointer = nil
        initialFrame = nil
        latestFrame = nil
        receivedDragEvent = false
    }
}

final class PortalWindow: NSWindow {
    private let keyEligibility: Bool
    private let dragRegionHeight: CGFloat
    private let pointerLocationProvider: () -> NSPoint
    private var placementTracker = PortalWindowUserPlacementTracker()
    private var isPerformingLiveResize = false

    var onUserPlacementCommit: ((NSRect) -> Void)?
    var onUserPlacementInteractionCancelled: (() -> Void)?

    var isUserPlacementInteractionActive: Bool {
        placementTracker.isTracking || isPerformingLiveResize
    }

    init(
        contentRect: NSRect,
        strategy: PortalWindowStrategy,
        contentViewController: NSViewController,
        dragRegionHeight: CGFloat = 40,
        pointerLocationProvider: @escaping () -> NSPoint = { NSEvent.mouseLocation }
    ) {
        keyEligibility = strategy.canBecomeKey
        self.dragRegionHeight = dragRegionHeight
        self.pointerLocationProvider = pointerLocationProvider
        super.init(
            contentRect: contentRect,
            styleMask: [.resizable],
            backing: .buffered,
            defer: false
        )
        level = strategy.level
        collectionBehavior = strategy.collectionBehavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 240, height: 240)
        self.contentViewController = contentViewController
    }

    override var canBecomeKey: Bool {
        keyEligibility
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown, isPortalDragRegion(at: event.locationInWindow) else {
            super.sendEvent(event)
            return
        }

        beginUserDrag(at: pointerLocationProvider())
        trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .infinity,
            mode: .eventTracking
        ) { [weak self] event, stop in
            guard let self else {
                stop.pointee = true
                return
            }
            handleUserDragEvent(event)
            if event?.type == .leftMouseUp || event == nil {
                stop.pointee = true
            }
        }
    }

    func applySystemPlacement(frame: NSRect) -> Bool {
        guard !isUserPlacementInteractionActive else {
            return false
        }
        setFrame(frame, display: true)
        return true
    }

    func beginUserResize() {
        isPerformingLiveResize = true
    }

    func beginUserDrag(at pointer: NSPoint) {
        placementTracker.begin(at: pointer, frame: frame)
    }

    func endUserResize() {
        guard isPerformingLiveResize else {
            return
        }
        isPerformingLiveResize = false
        onUserPlacementCommit?(frame)
    }

    func cancelUserPlacementInteraction(notify: Bool = true) {
        let wasActive = isUserPlacementInteractionActive
        placementTracker.cancel()
        isPerformingLiveResize = false
        if notify, wasActive {
            onUserPlacementInteractionCancelled?()
        }
    }

    func isPortalDragRegion(at location: NSPoint) -> Bool {
        let resizeBorderWidth: CGFloat = 8
        let dragRect = NSRect(
            x: contentLayoutRect.minX + resizeBorderWidth,
            y: contentLayoutRect.maxY - dragRegionHeight,
            width: contentLayoutRect.width - resizeBorderWidth * 2,
            height: dragRegionHeight - resizeBorderWidth
        )
        guard dragRect.contains(location) else {
            return false
        }
        guard let contentView else { return true }
        let contentPoint = contentView.convert(location, from: nil)
        var hitView = contentView.hitTest(contentPoint)
        while let current = hitView {
            if current is NSControl {
                return false
            }
            guard current !== contentView else { break }
            hitView = current.superview
        }
        return true
    }

    func handleUserDragEvent(_ event: NSEvent?) {
        guard let event else {
            placementTracker.cancel()
            onUserPlacementInteractionCancelled?()
            return
        }
        switch event.type {
        case .leftMouseDragged:
            guard let updatedFrame = placementTracker.drag(to: pointerLocationProvider()) else {
                return
            }
            setFrame(updatedFrame, display: true)

        case .leftMouseUp:
            guard let committedFrame = placementTracker.finish() else {
                onUserPlacementInteractionCancelled?()
                return
            }
            onUserPlacementCommit?(committedFrame)

        default:
            return
        }
    }
}
