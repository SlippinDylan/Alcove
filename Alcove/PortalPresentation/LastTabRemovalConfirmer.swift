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
        alert.messageText = "Remove this portal?"
        alert.informativeText = "Closing \(folderName) removes the portal from Alcove. Files are not changed."
        alert.addButton(withTitle: "Remove Portal")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
