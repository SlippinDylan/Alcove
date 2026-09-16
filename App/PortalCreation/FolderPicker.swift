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
        panel.prompt = NSLocalizedString("Choose", comment: "Folder picker confirmation button")
        panel.message = NSLocalizedString(
            "Choose a folder on this Mac's internal disk.",
            comment: "Folder picker instructions"
        )
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
protocol PortalPersistenceErrorPresenting: AnyObject {
    func present(_ error: Error)
}

@MainActor
final class PortalCreationErrorPresenter: PortalCreationErrorPresenting {
    func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if let coordinatorError = error as? PortalCoordinatorError,
           coordinatorError == .placementUnavailable {
            alert.messageText = NSLocalizedString(
                "portal.placement.unavailable.title",
                comment: "Portal placement error title"
            )
            alert.informativeText = coordinatorError.localizedDescription
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Confirmation button"))
            alert.runModal()
            return
        }
        alert.messageText = NSLocalizedString(
            "Unable to use this folder",
            comment: "Alert title shown when a folder cannot be used"
        )
        if let folderError = error as? FolderAccessError {
            alert.informativeText = folderError.userMessage
        } else {
            alert.informativeText = NSLocalizedString(
                "Choose another folder and try again.",
                comment: "Recovery guidance for an invalid folder"
            )
        }
        alert.addButton(
            withTitle: NSLocalizedString(
                "Choose Another Folder",
                comment: "Button to choose a different folder"
            )
        )
        alert.runModal()
    }
}

@MainActor
final class PortalPersistenceErrorPresenter: PortalPersistenceErrorPresenting {
    func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if let coordinatorError = error as? PortalCoordinatorError,
           coordinatorError == .placementUnavailable {
            alert.messageText = NSLocalizedString(
                "portal.placement.unavailable.title",
                comment: "Portal placement error title"
            )
            alert.informativeText = coordinatorError.localizedDescription
        } else {
            alert.messageText = NSLocalizedString(
                "Unable to save Alcove changes",
                comment: "Alert title shown when Alcove changes cannot be saved"
            )
            alert.informativeText = NSLocalizedString(
                "persistence.save.error.detail",
                comment: "Details shown when Alcove changes cannot be saved"
            )
        }
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Confirmation button"))
        alert.runModal()
    }
}
