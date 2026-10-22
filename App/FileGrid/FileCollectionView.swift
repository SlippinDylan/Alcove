import AppKit

struct FileGridDropProposal {
    let operation: NSDragOperation
    let folderIndexPath: IndexPath?
}

enum FileGridKeyCommand: Equatable {
    case moveLeft(extending: Bool)
    case moveRight(extending: Bool)
    case moveUp(extending: Bool)
    case moveDown(extending: Bool)
    case selectAll
    case openSelection
    case renameSelection
    case trashSelection
    case toggleQuickLook
    case noOperation
}

@MainActor
final class FileCollectionView: NSCollectionView {
    var onNativeItemInteraction: ((Set<Int>, Int, NSEvent.ModifierFlags, Int) -> Void)?
    var onMarqueeSelection: ((Set<Int>) -> Void)?
    var onKeyCommand: ((FileGridKeyCommand) -> Void)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var onValidateDrop: ((any NSDraggingInfo) -> FileGridDropProposal?)?
    var onAcceptDrop: ((any NSDraggingInfo) -> Bool)?
    var onDropSessionEnded: (() -> Void)?
    private let marqueeLayer = CAShapeLayer()
    private var dropFolderIndexPath: IndexPath?

    // Own destination callbacks so asynchronous preparation is rechecked even at a stationary target.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDropProposal(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        if visibleRect.contains(point) {
            _ = scrollToVisible(NSRect(
                x: visibleRect.minX, y: point.y - 20, width: visibleRect.width, height: 40
            ))
        }
        return updateDropProposal(sender)
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !updateDropProposal(sender).isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { endDropSession() }
        return onAcceptDrop?(sender) ?? false
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { endDropSession() }
    override func draggingEnded(_ sender: any NSDraggingInfo) { endDropSession() }
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { endDropSession() }

    func endDropSession() {
        setDropFolder(nil)
        onDropSessionEnded?()
    }

    private func updateDropProposal(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // The directory reload determines final icon positions only after asynchronous IO.
        sender.animatesToDestination = false
        let proposal = onValidateDrop?(sender)
        setDropFolder(proposal?.folderIndexPath)
        return proposal?.operation ?? []
    }

    private func setDropFolder(_ indexPath: IndexPath?) {
        if let previous = dropFolderIndexPath { item(at: previous)?.highlightState = .none }
        dropFolderIndexPath = indexPath
        if let indexPath { item(at: indexPath)?.highlightState = .asDropTarget }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let index = indexPathForItem(at: location)?.item
        window?.makeFirstResponder(self)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if let index {
            // AppKit must receive item mouse events so it can cross the drag threshold and
            // start the collection view's native multi-item dragging session.
            super.mouseDown(with: event)
            onNativeItemInteraction?(
                Set(selectionIndexPaths.map { $0.item }),
                index,
                modifiers,
                event.clickCount
            )
        } else {
            trackMarquee(from: location, modifiers: modifiers)
        }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let command = Self.command(keyCode: event.keyCode, modifiers: modifiers) {
            onKeyCommand?(command)
        } else {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        guard let index = indexPathForItem(at: location)?.item else { return nil }
        return contextMenuProvider?(index)
    }

    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> FileGridKeyCommand? {
        let extending = modifiers.contains(.shift)

        switch keyCode {
        case 123:
            return .moveLeft(extending: extending)
        case 124:
            return .moveRight(extending: extending)
        case 125:
            return modifiers.contains(.command)
                ? .openSelection
                : .moveDown(extending: extending)
        case 126:
            return .moveUp(extending: extending)
        case 0 where modifiers.contains(.command):
            return .selectAll
        case 31 where modifiers.contains(.command):
            return .openSelection
        case 51 where modifiers.contains(.command),
             117 where modifiers.contains(.command):
            return .trashSelection
        case 36, 76:
            return .renameSelection
        case 49:
            return .toggleQuickLook
        default:
            return nil
        }
    }

    private func trackMarquee(
        from startPoint: NSPoint,
        modifiers: NSEvent.ModifierFlags
    ) {
        let initialSelection = selectionIndexPaths
        updateMarqueeSelection(
            in: NSRect(origin: startPoint, size: .zero),
            initialSelection: initialSelection,
            togglesInitialSelection: modifiers.contains(.command)
        )

        while let event = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp {
                hideMarquee()
                return
            }

            _ = autoscroll(with: event)
            let currentPoint = convert(event.locationInWindow, from: nil)
            let rect = NSRect(
                x: min(startPoint.x, currentPoint.x),
                y: min(startPoint.y, currentPoint.y),
                width: abs(currentPoint.x - startPoint.x),
                height: abs(currentPoint.y - startPoint.y)
            )
            showMarquee(rect)
            updateMarqueeSelection(
                in: rect,
                initialSelection: initialSelection,
                togglesInitialSelection: modifiers.contains(.command)
            )
        }
        hideMarquee()
    }

    private func updateMarqueeSelection(
        in rect: NSRect,
        initialSelection: Set<IndexPath>,
        togglesInitialSelection: Bool
    ) {
        let hitPaths: Set<IndexPath> = Set(
            collectionViewLayout?.layoutAttributesForElements(in: rect)
                .filter { $0.representedElementCategory == .item && $0.frame.intersects(rect) }
                .compactMap(\.indexPath) ?? []
        )
        let selectedPaths = togglesInitialSelection
            ? initialSelection.symmetricDifference(hitPaths)
            : hitPaths
        onMarqueeSelection?(Set(selectedPaths.map { $0.item }))
    }

    private func showMarquee(_ rect: NSRect) {
        wantsLayer = true
        if marqueeLayer.superlayer == nil {
            marqueeLayer.fillColor = NSColor.selectedContentBackgroundColor
                .withAlphaComponent(0.12).cgColor
            marqueeLayer.strokeColor = NSColor.keyboardFocusIndicatorColor
                .withAlphaComponent(0.8).cgColor
            marqueeLayer.lineWidth = 1
            layer?.addSublayer(marqueeLayer)
        }
        marqueeLayer.path = CGPath(rect: rect, transform: nil)
        marqueeLayer.isHidden = false
    }

    private func hideMarquee() {
        marqueeLayer.isHidden = true
    }
}
