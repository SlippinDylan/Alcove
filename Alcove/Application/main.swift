import AlcoveCore
import AppKit
import Darwin

let application = NSApplication.shared
let creationGrid: CreationGrid
do {
    creationGrid = try CreationGrid(metrics: GridMetrics(iconSize: .medium))
} catch {
    FileHandle.standardError.write(Data("Invalid portal creation metrics: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}

let portalCoordinator = PortalCoordinator()
let frameSelector = PortalFrameSelector(grid: creationGrid)
let creationCoordinator = PortalCreationCoordinator(
    frameSelector: frameSelector,
    folderPicker: OpenPanelFolderPicker(),
    portalCoordinator: portalCoordinator
)
let statusMenuController = StatusMenuController(
    onNewPortal: { creationCoordinator.beginPortalCreation() },
    onShowPortal: { portalCoordinator.showPortal($0) },
    onRemovePortal: { portalID in
        Task { await portalCoordinator.removePortal(portalID) }
    },
    onSetIconSize: { portalID, iconSize in
        Task { await portalCoordinator.setIconSize(iconSize, for: portalID) }
    },
    onFollowDesktopIconSettings: { portalID in
        Task { await portalCoordinator.followDesktopIconSettings(for: portalID) }
    }
)
portalCoordinator.onPortalsChanged = { [weak statusMenuController] entries in
    statusMenuController?.updatePortals(entries)
}
let appDelegate = AppDelegate(
    statusMenuController: statusMenuController,
    portalCoordinator: portalCoordinator
)
application.delegate = appDelegate
application.run()
