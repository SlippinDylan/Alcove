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

enum FileContextActionError: LocalizedError, Equatable {
    case airDropUnavailable
    case terminalUnavailable
    case terminalLaunchFailed

    var errorDescription: String? {
        let key: String
        switch self {
        case .airDropUnavailable:
            key = "portal.files.airdrop_unavailable"
        case .terminalUnavailable:
            key = "portal.path.terminal_unavailable"
        case .terminalLaunchFailed:
            key = "portal.path.terminal_failed"
        }
        return NSLocalizedString(key, comment: "Contextual file action failure")
    }
}

@MainActor
protocol FileContextActionPerforming: AnyObject {
    func revealInFinder(_ urls: [URL])
    func copyPaths(_ urls: [URL])
    func canSendViaAirDrop(_ urls: [URL]) -> Bool
    @discardableResult
    func sendViaAirDrop(_ urls: [URL]) -> Bool
    func openInTerminal(
        _ urls: [URL],
        completion: @escaping @MainActor @Sendable (FileContextActionError?) -> Void
    )
}

@MainActor
final class SystemFileContextActionPerformer: FileContextActionPerforming {
    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyPaths(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func canSendViaAirDrop(_ urls: [URL]) -> Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        return service.canPerform(withItems: urls)
    }

    func sendViaAirDrop(_ urls: [URL]) -> Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else { return false }
        service.perform(withItems: urls)
        return true
    }

    func openInTerminal(
        _ urls: [URL],
        completion: @escaping @MainActor @Sendable (FileContextActionError?) -> Void
    ) {
        let workspace = NSWorkspace.shared
        guard let terminalURL = workspace.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else {
            completion(.terminalUnavailable)
            return
        }
        workspace.open(
            urls,
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            Task { @MainActor in
                completion(error == nil ? nil : .terminalLaunchFailed)
            }
        }
    }
}

enum FolderPathOpenError: Error, Equatable, Sendable {
    case finderLaunchFailed
    case terminalUnavailable
    case terminalLaunchFailed
}

@MainActor
protocol FolderPathOpening: AnyObject {
    func openInFinder(_ url: URL) -> Bool
    func openInTerminal(
        _ url: URL,
        completion: @escaping @MainActor @Sendable (FolderPathOpenError?) -> Void
    )
}

@MainActor
final class SystemFolderPathOpener: FolderPathOpening {
    func openInFinder(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    func openInTerminal(
        _ url: URL,
        completion: @escaping @MainActor @Sendable (FolderPathOpenError?) -> Void
    ) {
        let workspace = NSWorkspace.shared
        guard let terminalURL = workspace.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else {
            completion(.terminalUnavailable)
            return
        }
        workspace.open(
            [url],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            Task { @MainActor in
                completion(error == nil ? nil : .terminalLaunchFailed)
            }
        }
    }
}

@MainActor
protocol FolderPathOpenFailurePresenting: AnyObject {
    func present(_ error: FolderPathOpenError, for url: URL)
}

@MainActor
final class FolderPathOpenFailurePresenter: FolderPathOpenFailurePresenting {
    func present(_ error: FolderPathOpenError, for url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let key: String
        switch error {
        case .finderLaunchFailed:
            key = "portal.path.finder_failed"
        case .terminalUnavailable:
            key = "portal.path.terminal_unavailable"
        case .terminalLaunchFailed:
            key = "portal.path.terminal_failed"
        }
        alert.messageText = NSLocalizedString(key, comment: "Folder path open failure")
        alert.informativeText = url.path
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Confirmation button"))
        alert.runModal()
    }
}
