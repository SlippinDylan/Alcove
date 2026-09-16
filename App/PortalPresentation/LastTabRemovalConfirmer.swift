import AppKit

@MainActor
protocol LastTabRemovalConfirming: AnyObject {
    func confirmRemoval(folderName: String) async -> Bool
}

@MainActor
final class LastTabRemovalConfirmer: LastTabRemovalConfirming {
    func confirmRemoval(folderName: String) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(
            "Remove this portal?",
            comment: "Confirmation title when removing the last folder tab"
        )
        let informativeTextFormat = NSLocalizedString(
            "Closing %@ removes the portal from Alcove. Files are not changed.",
            comment: "Confirmation details when removing the last folder tab"
        )
        alert.informativeText = String(format: informativeTextFormat, folderName)
        alert.addButton(
            withTitle: NSLocalizedString("Remove Portal", comment: "Button to remove a portal")
        )
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
