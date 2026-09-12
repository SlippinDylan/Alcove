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

let creationGridState = PortalCreationGridState(grid: creationGrid)
let portalCoordinator = PortalCoordinator()
let frameSelector = PortalFrameSelector(gridState: creationGridState)
let creationCoordinator = PortalCreationCoordinator(
    frameSelector: frameSelector,
    portalCoordinator: portalCoordinator
)
let statusMenuController = StatusMenuController(
    onNewPortal: { creationCoordinator.beginPortalCreation() },
    onShowPortal: { portalCoordinator.showPortal($0) },
    onHidePortal: { portalCoordinator.hidePortal($0) }
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
