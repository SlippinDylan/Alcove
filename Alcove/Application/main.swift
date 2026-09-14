import AlcoveCore
import AppKit
import Darwin

let application = NSApplication.shared
let applicationPreferencesController = ApplicationPreferencesController()
let creationGrid: CreationGrid
do {
    creationGrid = try CreationGrid(
        metrics: GridMetrics(iconSize: applicationPreferencesController.portalAppearance.iconSize)
    )
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
let layoutBackupController = ApplicationLayoutBackupController(
    snapshotProvider: {
        (portalCoordinator.portalStates, applicationPreferencesController.portalAppearance)
    },
    replaceHandler: { backup in
        try await portalCoordinator.replaceLayout(with: backup)
    },
    importCompletion: { appearance in
        applicationPreferencesController.replacePortalAppearanceFromImport(appearance)
        do {
            try creationGridState.updateIconSize(appearance.iconSize)
        } catch {
            assertionFailure("Imported preset icon size must produce valid creation metrics: \(error)")
        }
        frameSelector.updateCornerRadius(appearance.cornerRadius.points)
        frameSelector.updateSpacing(appearance.spacing.points)
    }
)
let applicationSettingsController = ApplicationSettingsWindowController(
    preferencesController: applicationPreferencesController,
    layoutBackupController: layoutBackupController,
    panelPositionRepairer: portalCoordinator
)
applicationPreferencesController.onPortalAppearanceChanged = { appearance in
    guard portalCoordinator.updatePortalAppearance(appearance) else { return false }
    do {
        try creationGridState.updateIconSize(appearance.iconSize)
    } catch {
        assertionFailure("Preset icon size must produce valid creation metrics: \(error)")
        return false
    }
    frameSelector.updateCornerRadius(appearance.cornerRadius.points)
    frameSelector.updateSpacing(appearance.spacing.points)
    return true
}
let statusMenuController = StatusMenuController(
    onNewPortal: { creationCoordinator.beginPortalCreation() },
    onOpenSettings: { applicationSettingsController.present() },
    onShowPortal: { portalCoordinator.showPortal($0) },
    onHidePortal: { portalCoordinator.hidePortal($0) },
    onSetPortalPinned: { portalID, isPinned in
        Task { await portalCoordinator.setPinned(isPinned, for: portalID) }
    },
    onOpenPortalSettings: { portalCoordinator.showPortalSettings($0) },
    onRequestPortalRemoval: { portalCoordinator.confirmPortalRemoval($0) }
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
