import AppKit

@MainActor
protocol WorkspaceOpening: AnyObject {
    @discardableResult
    func open(_ url: URL) -> Bool
}

@MainActor
final class SystemWorkspaceOpener: WorkspaceOpening {
    @discardableResult
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
