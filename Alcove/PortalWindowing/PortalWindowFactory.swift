import AlcoveCore
import AppKit

@MainActor
protocol PortalWindowPresenting: AnyObject {
    var isUserPlacementInteractionActive: Bool { get }
    var onUserPlacementCommit: ((NSRect) -> Void)? { get set }
    var onUserResizeCommit: ((NSRect, GridCapacity) -> Void)? { get set }
    var onUserPlacementInteractionCancelled: (() -> Void)? { get set }
    var onSelectTab: ((FolderTabID) -> Void)? { get set }
    var onAddTab: (() -> Void)? { get set }
    var onCloseTab: ((FolderTabID) -> Void)? { get set }
    var onMoveTab: ((FolderTabID, PortalTabMoveDirection) -> Void)? { get set }
    var onLocateFolder: ((FolderTabID) -> Void)? { get set }
    var onSetBackgroundStyle: ((PortalBackgroundStyle) -> Void)? { get set }
    var onSetIconSize: ((IconSize) -> Void)? { get set }
    var onRemovePortal: (() -> Void)? { get set }
    var onSetPinned: ((Bool) -> Void)? { get set }
    func present()
    func hide()
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
