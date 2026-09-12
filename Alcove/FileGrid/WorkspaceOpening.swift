import AppKit

@MainActor
protocol WorkspaceOpening: AnyObject {
    @discardableResult
    func open(_ url: URL) -> Bool
}

@MainActor
protocol WorkspaceOpenFailurePresenting: AnyObject {
    func presentFailure(for url: URL)
}

@MainActor
final class SystemWorkspaceOpener: WorkspaceOpening {
    @discardableResult
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class WorkspaceOpenFailurePresenter: WorkspaceOpenFailurePresenting {
    func presentFailure(for url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(
            "Unable to open item",
            comment: "Alert title shown when an item cannot be opened"
        )
        alert.informativeText = url.path
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Confirmation button"))
        alert.runModal()
    }
}
