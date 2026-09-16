import AlcoveCore
import AppKit

@MainActor
struct PortalLayoutImporter {
    private let locationValidator: FolderLocationValidator

    init(locationValidator: FolderLocationValidator) {
        self.locationValidator = locationValidator
    }

    func portals(
        from backup: AlcoveLayoutBackup,
        appearance: PortalAppearancePreferences,
        display: DisplayDescriptor
    ) async throws -> [Portal] {
        let backup = try await backupWithValidatedFolderLocations(backup)
        let spacing = appearance.spacing.points
        let usableFrame = display.visibleFrame.insetBy(dx: spacing, dy: spacing)
        let iconLayout = PortalIconLayout.fixed(appearance.iconSize)
        var portals: [Portal] = []
        var desiredFrames: [NSRect] = []
        portals.reserveCapacity(backup.portals.count)
        desiredFrames.reserveCapacity(backup.portals.count)

        for importedPortal in backup.portals {
            let contentSize = PortalViewController.contentSize(
                for: importedPortal.gridCapacity,
                iconLayout: iconLayout
            )
            let frameSize = NSWindow.frameRect(
                forContentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.resizable]
            ).size
            guard frameSize.width <= usableFrame.width,
                  frameSize.height <= usableFrame.height else {
                throw PortalCoordinatorError.placementUnavailable
            }
            let frame = NSRect(
                x: usableFrame.minX
                    + CGFloat(importedPortal.normalizedAnchor.x)
                    * (usableFrame.width - frameSize.width),
                y: usableFrame.minY
                    + CGFloat(importedPortal.normalizedAnchor.y)
                    * (usableFrame.height - frameSize.height),
                width: frameSize.width,
                height: frameSize.height
            )
            let tabs = importedPortal.folderURLs.map { FolderTab(folderURL: $0) }
            let selectedTabID = importedPortal.selectedFolderIndex.map { tabs[$0].id }
            let placement = try PlacementRecord(frame: frame, display: display)
            portals.append(try Portal(
                id: importedPortal.id,
                tabs: tabs,
                selectedTabID: selectedTabID,
                placement: placement,
                iconLayout: iconLayout,
                backgroundStyle: appearance.backgroundStyle,
                gridCapacity: importedPortal.gridCapacity,
                isPinned: importedPortal.isPinned,
                sortOrder: importedPortal.sortOrder,
                tint: importedPortal.tint
            ))
            desiredFrames.append(frame)
        }

        guard let reflowedFrames = try PortalFrameReflow.reflowedFrames(
            desiredFrames,
            visibleFrame: display.visibleFrame,
            minimumGap: spacing
        ) else {
            throw PortalCoordinatorError.placementUnavailable
        }
        for index in portals.indices {
            try portals[index].recordUserPlacement(
                frame: reflowedFrames[index],
                display: display
            )
        }
        return portals
    }

    private func backupWithValidatedFolderLocations(
        _ backup: AlcoveLayoutBackup
    ) async throws -> AlcoveLayoutBackup {
        var validatedPortals: [AlcoveLayoutBackupPortal] = []
        validatedPortals.reserveCapacity(backup.portals.count)
        for portal in backup.portals {
            var validatedFolderURLs: [URL] = []
            validatedFolderURLs.reserveCapacity(portal.folderURLs.count)
            for folderURL in portal.folderURLs {
                validatedFolderURLs.append(
                    try await locationValidator.validateForRestoration(folderURL)
                )
            }
            validatedPortals.append(AlcoveLayoutBackupPortal(
                id: portal.id,
                sortOrder: portal.sortOrder,
                tint: portal.tint,
                isPinned: portal.isPinned,
                normalizedAnchor: portal.normalizedAnchor,
                size: portal.size,
                gridCapacity: portal.gridCapacity,
                folderURLs: validatedFolderURLs,
                selectedFolderIndex: portal.selectedFolderIndex
            ))
        }
        return AlcoveLayoutBackup(global: backup.global, portals: validatedPortals)
    }
}
