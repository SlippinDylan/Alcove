import AppKit

enum FileGridKeyCommand: Equatable {
    case moveLeft(extending: Bool)
    case moveRight(extending: Bool)
    case moveUp(extending: Bool)
    case moveDown(extending: Bool)
    case selectAll
    case openSelection
    case noOperation
}

@MainActor
final class FileCollectionView: NSCollectionView {
    var onItemClick: ((Int?, NSEvent.ModifierFlags, Int) -> Void)?
    var onKeyCommand: ((FileGridKeyCommand) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let index = indexPathForItem(at: location)?.item
        onItemClick?(
            index,
            event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            event.clickCount
        )
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let command = Self.command(keyCode: event.keyCode, modifiers: modifiers) {
            onKeyCommand?(command)
        } else {
            super.keyDown(with: event)
        }
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
        case 36, 76:
            return .noOperation
        default:
            return nil
        }
    }
}
