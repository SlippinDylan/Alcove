import AppKit

@MainActor
protocol FolderPicking: AnyObject {
    func chooseFolder() async -> URL?
    func cancel()
}

@MainActor
final class OpenPanelFolderPicker: FolderPicking {
    private var activePanel: NSOpenPanel?

    func chooseFolder() async -> URL? {
        let panel = NSOpenPanel()
        Self.configure(panel)
        activePanel = panel

        return await withCheckedContinuation { continuation in
            panel.begin { [weak self] response in
                self?.activePanel = nil
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    static func configure(_ panel: NSOpenPanel) {
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder on this Mac's internal disk."
    }

    func cancel() {
        activePanel?.cancel(nil)
    }
}

@MainActor
protocol PortalCreationErrorPresenting: AnyObject {
    func present(_ error: Error)
}

@MainActor
final class PortalCreationErrorPresenter: PortalCreationErrorPresenting {
    func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to use this folder"
        if let folderError = error as? FolderAccessError {
            alert.informativeText = folderError.userMessage
        } else {
            alert.informativeText = "Choose another folder and try again."
        }
        alert.addButton(withTitle: "Choose Another Folder")
        alert.runModal()
    }
}
