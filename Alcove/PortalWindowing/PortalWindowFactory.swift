import AlcoveCore
import AppKit

@MainActor
protocol PortalWindowPresenting: AnyObject {
    var onFrameChange: ((NSRect) -> Void)? { get set }
    func present()
}

@MainActor
protocol PortalWindowBuilding: AnyObject {
    func makeWindow(for portal: Portal) -> any PortalWindowPresenting
}

@MainActor
final class PortalWindowFactory: PortalWindowBuilding {
    func makeWindow(for portal: Portal) -> any PortalWindowPresenting {
        guard let selectedTab = portal.tabs.first(where: { $0.id == portal.selectedTabID }) else {
            preconditionFailure("Portal selected-tab invariant violated")
        }
        return PortalWindowController(
            folderURL: selectedTab.folderURL,
            loadingCoordinator: FolderLoadingCoordinator(),
            initialFrame: portal.frame
        )
    }
}
