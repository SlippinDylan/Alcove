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

    mutating func accept(_ frame: NSRect) {
        latestFrame = frame
    }

    mutating func finish() -> NSRect? {
        let committedFrame: NSRect?
        if receivedDragEvent, latestFrame != initialFrame {
            committedFrame = latestFrame
        } else {
            committedFrame = nil
        }
        defer {
            initialPointer = nil
            initialFrame = nil
            latestFrame = nil
            receivedDragEvent = false
        }
        return committedFrame
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
    private var initialLiveResizeFrame: NSRect?
    private var lastValidLiveResizeFrame: NSRect?
    private var isRestoringLiveResizeFrame = false
    private var appliedCornerRadius: CGFloat = PortalAppearancePreferences.defaults
        .cornerRadius.points
    private(set) var isPinned = false

    var onUserPlacementCommit: ((NSRect) -> Void)?
    var onUserResizeCommit: ((NSRect) -> Void)?
    var onUserPlacementInteractionCancelled: (() -> Void)?
    var constrainUserDragFrame: ((NSRect, NSRect, NSPoint) -> NSRect)?
    var isValidUserPlacement: ((NSRect) -> Bool)?

    var isUserPlacementInteractionActive: Bool {
        placementTracker.isTracking || isPerformingLiveResize
    }

    var hasLiveResizeGeometryChanged: Bool {
        guard let initialLiveResizeFrame else { return false }
        return frame != initialLiveResizeFrame
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

    func updateAppearance(_ appearance: PortalAppearancePreferences) {
        let shapeChanged = appliedCornerRadius != appearance.cornerRadius.points
        appliedCornerRadius = appearance.cornerRadius.points
        hasShadow = appearance.shadowEnabled
        if shapeChanged, hasShadow {
            invalidateShadow()
        }
    }

    override var canBecomeKey: Bool {
        keyEligibility
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, canBecomeKey {
            NSApplication.shared.activate()
            if !isKeyWindow {
                makeKey()
            }
        }
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

    func applySystemPlacement(frame: NSRect, animated: Bool = false) -> Bool {
        guard !isUserPlacementInteractionActive else {
            return false
        }
        setFrame(frame, display: true, animate: animated)
        return true
    }

    func setPinned(_ isPinned: Bool) {
        guard self.isPinned != isPinned else { return }
        if isPinned {
            cancelUserPlacementInteraction()
            styleMask.remove(.resizable)
        } else {
            styleMask.insert(.resizable)
        }
        self.isPinned = isPinned
    }

    func beginUserResize() {
        guard !isPinned else { return }
        isPerformingLiveResize = true
        initialLiveResizeFrame = frame
        lastValidLiveResizeFrame = frame
    }

    func beginUserDrag(at pointer: NSPoint) {
        guard !isPinned else { return }
        placementTracker.begin(at: pointer, frame: frame)
    }

    func endUserResize() {
        guard isPerformingLiveResize else {
            return
        }
        isPerformingLiveResize = false
        let changedFrame = initialLiveResizeFrame != frame
        initialLiveResizeFrame = nil
        lastValidLiveResizeFrame = nil
        if changedFrame {
            onUserResizeCommit?(frame)
        } else {
            onUserPlacementInteractionCancelled?()
        }
    }

    func cancelUserPlacementInteraction(notify: Bool = true) {
        let wasActive = isUserPlacementInteractionActive
        placementTracker.cancel()
        isPerformingLiveResize = false
        initialLiveResizeFrame = nil
        lastValidLiveResizeFrame = nil
        if notify, wasActive {
            onUserPlacementInteractionCancelled?()
        }
    }

    func isPortalDragRegion(at location: NSPoint) -> Bool {
        guard !isPinned else { return false }
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
        guard !isPinned else { return }
        guard let event else {
            placementTracker.cancel()
            onUserPlacementInteractionCancelled?()
            return
        }
        switch event.type {
        case .leftMouseDragged:
            let pointer = pointerLocationProvider()
            guard let proposedFrame = placementTracker.drag(to: pointer) else {
                return
            }
            let updatedFrame = constrainUserDragFrame?(frame, proposedFrame, pointer)
                ?? proposedFrame
            placementTracker.accept(updatedFrame)
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

    func enforceLiveResizeConstraint() {
        guard isPerformingLiveResize, !isRestoringLiveResizeFrame else { return }
        guard isValidUserPlacement?(frame) == false else {
            lastValidLiveResizeFrame = frame
            return
        }
        guard let lastValidLiveResizeFrame else { return }
        isRestoringLiveResizeFrame = true
        setFrame(lastValidLiveResizeFrame, display: true)
        isRestoringLiveResizeFrame = false
    }
}
