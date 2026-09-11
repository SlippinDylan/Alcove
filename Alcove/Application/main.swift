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
let statusMenuController = StatusMenuController {
    creationCoordinator.beginPortalCreation()
}
let appDelegate = AppDelegate(
    statusMenuController: statusMenuController,
    portalCoordinator: portalCoordinator
)
application.delegate = appDelegate
application.run()
