import AlcoveCore
import AppKit

@MainActor
protocol PortalWindowPresenting: AnyObject {
    var onFrameChange: ((NSRect) -> Void)? { get set }
    var onSelectTab: ((FolderTabID) -> Void)? { get set }
    var onAddTab: (() -> Void)? { get set }
    var onCloseTab: ((FolderTabID) -> Void)? { get set }
    func present()
    func updatePortal(_ portal: Portal)
    func close()
}

@MainActor
protocol PortalWindowBuilding: AnyObject {
    func makeWindow(for portal: Portal) -> any PortalWindowPresenting
}

@MainActor
final class PortalWindowFactory: PortalWindowBuilding {
    func makeWindow(for portal: Portal) -> any PortalWindowPresenting {
        return PortalWindowController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(),
            initialFrame: portal.frame
        )
    }
}
