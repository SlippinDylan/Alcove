import AlcoveCore
import AppKit

@MainActor
protocol PortalWindowPresenting: AnyObject {
    var onUserPlacementCommit: ((NSRect) -> Void)? { get set }
    var onUserPlacementInteractionCancelled: (() -> Void)? { get set }
    var onSelectTab: ((FolderTabID) -> Void)? { get set }
    var onAddTab: (() -> Void)? { get set }
    var onCloseTab: ((FolderTabID) -> Void)? { get set }
    var onLocateFolder: ((FolderTabID) -> Void)? { get set }
    func present()
    func updatePortal(_ portal: Portal)
    func reloadSelectedFolder()
    func applySystemPlacement(frame: NSRect) -> Bool
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
