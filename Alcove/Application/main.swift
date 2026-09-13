import AlcoveCore
import AppKit
import Darwin

let application = NSApplication.shared
let applicationPreferencesController = ApplicationPreferencesController()
let creationGrid: CreationGrid
do {
    creationGrid = try CreationGrid(metrics: GridMetrics(iconSize: .medium))
} catch {
    FileHandle.standardError.write(Data("Invalid portal creation metrics: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}

let creationGridState = PortalCreationGridState(grid: creationGrid)
let portalCoordinator = PortalCoordinator(
    portalAppearance: applicationPreferencesController.portalAppearance
)
let frameSelector = PortalFrameSelector(
    gridState: creationGridState,
    cornerRadius: applicationPreferencesController.portalAppearance.cornerRadius.points,
    spacing: applicationPreferencesController.portalAppearance.spacing.points,
    occupiedFramesProvider: { portalCoordinator.occupiedPortalFrames() }
)
let creationCoordinator = PortalCreationCoordinator(
    frameSelector: frameSelector,
    portalCoordinator: portalCoordinator
)
let applicationSettingsController = ApplicationSettingsWindowController(
    preferencesController: applicationPreferencesController
)
applicationPreferencesController.onPortalAppearanceChanged = { appearance in
    portalCoordinator.updatePortalAppearance(appearance)
    frameSelector.updateCornerRadius(appearance.cornerRadius.points)
    frameSelector.updateSpacing(appearance.spacing.points)
}
let statusMenuController = StatusMenuController(
    onNewPortal: { creationCoordinator.beginPortalCreation() },
    onOpenSettings: { applicationSettingsController.present() },
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
