import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

final class PortalCoordinatorTests: XCTestCase {
    func testStartupFolderResolverAcceptsOnlyExplicitFolderArgument() {
        XCTAssertNil(StartupFolderResolver.resolve(arguments: ["Alcove"]))
        XCTAssertNil(StartupFolderResolver.resolve(arguments: ["Alcove", "--unknown", "/tmp"]))
        XCTAssertNil(StartupFolderResolver.resolve(arguments: ["Alcove", "--folder"]))

        let result = StartupFolderResolver.resolve(
            arguments: ["Alcove", "--folder", "/tmp/example/../folder"]
        )
        XCTAssertEqual(result, URL(fileURLWithPath: "/tmp/folder"))
    }

    @MainActor
    func testRestorePresentsPortalsInStoredOrder() async throws {
        var first = try makePortal(path: "/tmp/first", x: 10)
        first.updateBackgroundStyle(.highTransparency)
        var second = try makePortal(path: "/tmp/second", x: 400)
        second.updateBackgroundStyle(.lowTransparency)
        let portals = [first, second]
        let store = PortalStoreSpy(portals: portals)
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(store: store, windowFactory: factory)

        try await coordinator.restorePortals()

        XCTAssertEqual(coordinator.portalStates.map(\.id), portals.map(\.id))
        XCTAssertTrue(coordinator.portalStates.allSatisfy { $0.backgroundStyle == .standard })
        XCTAssertEqual(factory.createdPortalIDs, portals.map(\.id))
        XCTAssertEqual(factory.createdPortals.map(\.backgroundStyle), [.standard, .standard])
        XCTAssertEqual(factory.windows.map(\.presentCount), [1, 1])
    }

    @MainActor
    func testSpacingPreferenceReflowsExistingPortalsAndReturnsToSavedFrames() async throws {
        let upper = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/upper"),
            frame: NSRect(x: 12, y: 488, width: 500, height: 400),
            display: coordinatorTestDisplay
        )
        let lower = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/lower"),
            frame: NSRect(x: 12, y: 176, width: 500, height: 300),
            display: coordinatorTestDisplay
        )
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let factory = PortalWindowFactorySpy()
        let minimumAppearance = PortalAppearancePreferences(
            cornerRadius: .maximum,
            spacing: .minimum,
            shadowEnabled: true
        )
        let store = PortalStoreSpy(portals: [upper, lower])
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            portalAppearance: minimumAppearance,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let minimumFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(minimumFrames[0].minX, 4)
        XCTAssertEqual(minimumFrames[0].maxY, coordinatorTestDisplay.visibleFrame.maxY - 4)
        XCTAssertEqual(minimumFrames[0].minY - minimumFrames[1].maxY, 4)

        var maximumAppearance = minimumAppearance
        maximumAppearance.spacing = .maximum
        XCTAssertTrue(coordinator.updatePortalAppearance(maximumAppearance))

        let maximumFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(maximumFrames[0].minX, 20)
        XCTAssertEqual(maximumFrames[0].maxY, coordinatorTestDisplay.visibleFrame.maxY - 20)
        XCTAssertEqual(maximumFrames[0].minY - maximumFrames[1].maxY, 20)
        XCTAssertEqual(factory.windows.flatMap(\.systemPlacementAnimations).last, true)

        XCTAssertTrue(coordinator.updatePortalAppearance(minimumAppearance))
        let restoredFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(restoredFrames, minimumFrames)
        let saves = await store.savedSnapshots()
        XCTAssertTrue(saves.isEmpty)
    }

    @MainActor
    func testGlobalContentSizeKeepsAttachedPortalsAtTheSelectedGap() async throws {
        let capacity = GridCapacity.minimum
        let mediumContentSize = PortalViewController.contentSize(
            for: capacity,
            iconLayout: .fixed(.medium)
        )
        let mediumFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: mediumContentSize),
            styleMask: [.resizable]
        ).size
        let spacing = PortalSpacing.medium.points
        let visibleFrame = coordinatorTestDisplay.visibleFrame
        let upperFrame = NSRect(
            x: visibleFrame.minX + spacing,
            y: visibleFrame.maxY - spacing - mediumFrameSize.height,
            width: mediumFrameSize.width,
            height: mediumFrameSize.height
        )
        let lowerFrame = NSRect(
            x: upperFrame.minX,
            y: upperFrame.minY - spacing - mediumFrameSize.height,
            width: mediumFrameSize.width,
            height: mediumFrameSize.height
        )
        let upper = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/upper"),
            frame: upperFrame,
            display: coordinatorTestDisplay,
            iconLayout: .fixed(.medium),
            gridCapacity: capacity
        )
        let lower = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/lower"),
            frame: lowerFrame,
            display: coordinatorTestDisplay,
            iconLayout: .fixed(.medium),
            gridCapacity: capacity
        )
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let factory = PortalWindowFactorySpy()
        let mediumAppearance = PortalAppearancePreferences(
            iconSize: .medium,
            backgroundStyle: .standard,
            cornerRadius: .maximum,
            spacing: .medium,
            shadowEnabled: true
        )
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [upper, lower]),
            windowFactory: factory,
            portalAppearance: mediumAppearance,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        var smallAppearance = mediumAppearance
        smallAppearance.iconSize = .small
        XCTAssertTrue(coordinator.updatePortalAppearance(smallAppearance))
        let smallFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(smallFrames[0].maxY, upperFrame.maxY)
        XCTAssertEqual(smallFrames[0].minY - smallFrames[1].maxY, spacing)
        XCTAssertGreaterThan(smallFrames[1].minY, lowerFrame.minY)

        var largeAppearance = mediumAppearance
        largeAppearance.iconSize = .large
        largeAppearance.spacing = .maximum
        XCTAssertTrue(coordinator.updatePortalAppearance(largeAppearance))
        let largeFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(
            largeFrames[0].maxY,
            visibleFrame.maxY - PortalSpacing.maximum.points
        )
        XCTAssertEqual(
            largeFrames[0].minY - largeFrames[1].maxY,
            PortalSpacing.maximum.points
        )
        XCTAssertLessThan(largeFrames[1].minY, smallFrames[1].minY)

        XCTAssertTrue(coordinator.updatePortalAppearance(mediumAppearance))
        let restoredFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(restoredFrames, [upperFrame, lowerFrame])
    }

    @MainActor
    func testRestoreNormalizesGlobalContentSizeWithoutLosingAttachment() async throws {
        let capacity = GridCapacity.minimum
        let mediumContentSize = PortalViewController.contentSize(
            for: capacity,
            iconLayout: .fixed(.medium)
        )
        let mediumFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: mediumContentSize),
            styleMask: [.resizable]
        ).size
        let smallContentSize = PortalViewController.contentSize(
            for: capacity,
            iconLayout: .fixed(.small)
        )
        let smallFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: smallContentSize),
            styleMask: [.resizable]
        ).size
        let gap = PortalSpacing.medium.points
        let upperFrame = NSRect(
            x: gap,
            y: coordinatorTestDisplay.visibleFrame.maxY - gap - mediumFrameSize.height,
            width: mediumFrameSize.width,
            height: mediumFrameSize.height
        )
        let lowerFrame = NSRect(
            x: gap,
            y: upperFrame.minY - gap - smallFrameSize.height,
            width: smallFrameSize.width,
            height: smallFrameSize.height
        )
        let portals = try [
            Portal(
                folderURL: URL(fileURLWithPath: "/tmp/upper"),
                frame: upperFrame,
                display: coordinatorTestDisplay,
                iconLayout: .fixed(.medium),
                gridCapacity: capacity
            ),
            Portal(
                folderURL: URL(fileURLWithPath: "/tmp/lower"),
                frame: lowerFrame,
                display: coordinatorTestDisplay,
                iconLayout: .fixed(.small),
                gridCapacity: capacity
            ),
        ]
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let store = PortalStoreSpy(portals: portals)
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            portalAppearance: PortalAppearancePreferences(
                iconSize: .small,
                backgroundStyle: .standard,
                cornerRadius: .maximum,
                spacing: .medium,
                shadowEnabled: true
            ),
            displaySnapshotProvider: { .success(snapshot) }
        )

        try await coordinator.restorePortals()

        XCTAssertTrue(coordinator.portalStates.allSatisfy { $0.iconSize == .small })
        XCTAssertEqual(
            coordinator.portalStates[0].frame.minY - coordinator.portalStates[1].frame.maxY,
            gap
        )
        XCTAssertEqual(
            try factory.windows.map { try XCTUnwrap($0.presentedFrame) },
            coordinator.portalStates.map(\.frame)
        )
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves, [coordinator.portalStates])
    }

    @MainActor
    func testRestoreSizeNormalizationPreservesDisconnectedHomeDisplay() async throws {
        let portal = try makePortal(path: "/tmp/disconnected", x: 10)
        let fallback = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "fallback-display"),
            visibleFrame: CGRect(x: -1000, y: 0, width: 1000, height: 700)
        )
        let snapshot = try DisplaySnapshot(
            displays: [fallback],
            primaryDisplay: fallback.identity
        )
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal]),
            windowFactory: factory,
            portalAppearance: PortalAppearancePreferences(
                iconSize: .large,
                backgroundStyle: .standard,
                cornerRadius: .maximum,
                spacing: .medium,
                shadowEnabled: true
            ),
            displaySnapshotProvider: { .success(snapshot) }
        )

        try await coordinator.restorePortals()

        XCTAssertEqual(coordinator.portalStates[0].iconSize, .large)
        XCTAssertEqual(
            coordinator.portalStates[0].placement.homeDisplay,
            portal.placement.homeDisplay
        )
        XCTAssertTrue(
            fallback.visibleFrame.contains(try XCTUnwrap(factory.windows[0].presentedFrame))
        )
    }

    @MainActor
    func testDisplaySnapshotFailurePreservesLoadedStateAndBlocksOverwrite() async throws {
        try await withPortalDirectory { folder in
            let portal = try makePortal(path: "/tmp/existing", x: 10)
            let store = PortalStoreSpy(portals: [portal])
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(
                store: store,
                windowFactory: factory,
                displaySnapshotProvider: { .failure(.missingPrimaryScreen) }
            )

            try await coordinator.restorePortals()
            XCTAssertEqual(coordinator.portalStates, [portal])
            XCTAssertTrue(factory.windows.isEmpty)

            do {
                try await coordinator.createPortal(for: folder, frame: nil)
                XCTFail("Creation without a valid display snapshot must fail closed")
            } catch let error as DisplaySnapshotError {
                XCTAssertEqual(error, .missingPrimaryScreen)
            }

            XCTAssertEqual(coordinator.portalStates, [portal])
            let saves = await store.savedSnapshots()
            XCTAssertEqual(saves, [])
            let recovered = try DisplaySnapshot(
                displays: [coordinatorTestDisplay],
                primaryDisplay: coordinatorTestDisplay.identity
            )
            coordinator.reconcileDisplayTopology(.success(recovered))
            await coordinator.waitForPersistenceForTesting()
            XCTAssertEqual(factory.windows.count, 1)
        }
    }

    @MainActor
    func testCreatePersistsBeforePresenting() async throws {
        try await withPortalDirectory { folder in
            let store = PortalStoreSpy(portals: [])
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(store: store, windowFactory: factory)
            let frame = NSRect(x: 30, y: 40, width: 320, height: 240)
            let capacity = try GridCapacity(columns: 4, rows: 2)
            try await coordinator.restorePortals()

            try await coordinator.createPortal(
                for: folder,
                frame: frame,
                gridCapacity: capacity
            )

            let saves = await store.savedSnapshots()
            XCTAssertEqual(saves.count, 1)
            XCTAssertEqual(saves[0], coordinator.portalStates)
            let createdPortal = try XCTUnwrap(coordinator.portalStates.first)
            XCTAssertEqual(createdPortal.gridCapacity, capacity)
            let contentSize = NSWindow.contentRect(
                forFrameRect: createdPortal.frame,
                styleMask: [.resizable]
            ).size
            XCTAssertEqual(
                contentSize,
                PortalViewController.contentSize(
                    for: capacity,
                    iconLayout: .fixed(.medium)
                )
            )
            XCTAssertEqual(factory.windows.first?.presentCount, 1)
        }
    }

    @MainActor
    func testCreateClampsRequestedSecondaryFrameToMenuBarPrimary() async throws {
        let secondary = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "secondary"),
            visibleFrame: CGRect(x: 1_440, y: 0, width: 1_200, height: 800)
        )
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay, secondary],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let store = PortalStoreSpy(portals: [])
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: PortalWindowFactorySpy(),
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        try await coordinator.createPortal(
            for: nil,
            frame: CGRect(x: 1_600, y: 100, width: 400, height: 300),
            gridCapacity: .minimum,
            iconLayout: .fixed(.medium)
        )

        let portal = try XCTUnwrap(coordinator.portalStates.first)
        XCTAssertEqual(portal.placement.homeDisplay, coordinatorTestDisplay.identity)
        XCTAssertTrue(coordinatorTestDisplay.visibleFrame.contains(portal.frame))
    }

    @MainActor
    func testLayoutImportPersistsCompleteReplacementBeforeSwappingRuntimeWindows() async throws {
        let existing = try makePortal(path: "/tmp/existing", x: 10)
        let store = PortalStoreSpy(portals: [existing])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let importedID = PortalID(rawValue: UUID())
        let backup = try makeLayoutBackup(portalID: importedID)

        try await coordinator.replaceLayout(with: backup)

        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves[0], coordinator.portalStates)
        let imported = try XCTUnwrap(coordinator.portalStates.first)
        XCTAssertEqual(imported.id, importedID)
        XCTAssertEqual(imported.iconSize, .large)
        XCTAssertEqual(imported.backgroundStyle, .highTransparency)
        XCTAssertEqual(imported.sortOrder, .creationDate)
        XCTAssertEqual(imported.tint, .purple)
        XCTAssertTrue(imported.isPinned)
        XCTAssertEqual(imported.selectedTabID, imported.tabs[1].id)
        XCTAssertEqual(
            imported.tabs.map(\.folderURL),
            [URL(fileURLWithPath: "/missing/one"), URL(fileURLWithPath: "/missing/two")]
        )
        XCTAssertEqual(factory.windows.count, 2)
        XCTAssertEqual(factory.windows[0].closeCount, 1)
        XCTAssertEqual(factory.windows[1].presentCount, 1)
        XCTAssertEqual(factory.windows[1].updatedAppearances.last?.backgroundType, .frostedGlass)
        XCTAssertEqual(factory.windows[1].updatedAppearances.last?.spacing, .maximum)
    }

    @MainActor
    func testLayoutImportSaveFailureLeavesRuntimeStateUntouched() async throws {
        let existing = try makePortal(path: "/tmp/existing", x: 10)
        let store = PortalStoreSpy(portals: [existing], saveError: .rejected)
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        do {
            try await coordinator.replaceLayout(
                with: try makeLayoutBackup(portalID: PortalID(rawValue: UUID()))
            )
            XCTFail("A failed replacement save must be reported")
        } catch let error as PortalStoreFixtureError {
            XCTAssertEqual(error, .rejected)
        }

        XCTAssertEqual(coordinator.portalStates, [existing])
        XCTAssertEqual(factory.windows.count, 1)
        XCTAssertEqual(factory.windows[0].closeCount, 0)
        XCTAssertEqual(factory.windows[0].presentCount, 1)
        let saves = await store.savedSnapshots()
        XCTAssertTrue(saves.isEmpty)
    }

    @MainActor
    func testLayoutImportPreflightFailureDoesNotSaveOrChangeRuntimeState() async throws {
        let existing = try makePortal(path: "/tmp/existing", x: 10)
        let store = PortalStoreSpy(portals: [existing])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let oversizedCapacity = try GridCapacity(columns: 100, rows: 100)

        do {
            try await coordinator.replaceLayout(
                with: try makeLayoutBackup(
                    portalID: PortalID(rawValue: UUID()),
                    gridCapacity: oversizedCapacity
                )
            )
            XCTFail("An imported layout that cannot fit must fail preflight")
        } catch let error as PortalCoordinatorError {
            XCTAssertEqual(error, .placementUnavailable)
        }

        XCTAssertEqual(coordinator.portalStates, [existing])
        XCTAssertEqual(factory.windows.count, 1)
        XCTAssertEqual(factory.windows[0].closeCount, 0)
        let saves = await store.savedSnapshots()
        XCTAssertTrue(saves.isEmpty)
    }

    @MainActor
    private func makeLayoutBackup(
        portalID: PortalID,
        gridCapacity: GridCapacity = .minimum
    ) throws -> AlcoveLayoutBackup {
        AlcoveLayoutBackup(
            global: AlcoveLayoutBackupGlobal(
                iconSize: .large,
                backgroundType: .frostedGlass,
                backgroundStyle: .highTransparency,
                spacing: .maximum,
                cornerRadius: .small,
                shadowEnabled: false
            ),
            portals: [
                AlcoveLayoutBackupPortal(
                    id: portalID,
                    sortOrder: .creationDate,
                    tint: .purple,
                    isPinned: true,
                    normalizedAnchor: try NormalizedAnchor(x: 0.25, y: 0.75),
                    size: CGSize(width: 1, height: 1),
                    gridCapacity: gridCapacity,
                    folderURLs: [
                        URL(fileURLWithPath: "/missing/one"),
                        URL(fileURLWithPath: "/missing/two"),
                    ],
                    selectedFolderIndex: 1
                ),
            ]
        )
    }

    @MainActor
    func testCreateRejectsAFrameOccupiedByAnotherPortal() async throws {
        let existing = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/existing"),
            frame: NSRect(x: 100, y: 100, width: 320, height: 240),
            display: coordinatorTestDisplay
        )
        let store = PortalStoreSpy(portals: [existing])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        do {
            try await coordinator.createPortal(for: nil, frame: existing.frame)
            XCTFail("Creation must reject an occupied frame")
        } catch let error as PortalCoordinatorError {
            XCTAssertEqual(error, .placementUnavailable)
        }

        XCTAssertEqual(coordinator.portalStates, [existing])
        let saves = await store.savedSnapshots()
        XCTAssertTrue(saves.isEmpty)
    }

    @MainActor
    func testRuntimeDragConstraintStopsAtAnotherPresentedPortal() async throws {
        let first = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: NSRect(x: 100, y: 100, width: 320, height: 240),
            display: coordinatorTestDisplay
        )
        let second = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/second"),
            frame: NSRect(x: 600, y: 100, width: 320, height: 240),
            display: coordinatorTestDisplay
        )
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [first, second]),
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let constrainDrag = try XCTUnwrap(factory.windows[0].constrainDrag)

        let result = constrainDrag(
            first.frame,
            first.frame.offsetBy(dx: 700, dy: 0),
            NSPoint(x: 800, y: 200)
        )

        XCTAssertEqual(result.maxX, second.frame.minX - PortalSpacing.medium.points)
    }

    @MainActor
    func testRuntimeDragConstraintKeepsPortalOnMenuBarPrimaryDisplay() async throws {
        let destinationDisplay = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "destination-display"),
            visibleFrame: NSRect(x: 1440, y: 40, width: 1200, height: 800)
        )
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: NSRect(x: 100, y: 100, width: 320, height: 240),
            display: coordinatorTestDisplay
        )
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay, destinationDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal]),
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let constrainDrag = try XCTUnwrap(factory.windows[0].constrainDrag)

        let result = constrainDrag(
            portal.frame,
            NSRect(x: 1500, y: 100, width: 320, height: 240),
            NSPoint(x: 1600, y: 200)
        )

        XCTAssertTrue(
            coordinatorTestDisplay.visibleFrame
                .insetBy(dx: PortalSpacing.medium.points, dy: PortalSpacing.medium.points)
                .contains(result)
        )
    }

    @MainActor
    func testEmptyPortalPersistsThenChoosesItsFirstFolderInsideTheWindow() async throws {
        try await withPortalDirectory { folder in
            let store = PortalStoreSpy(portals: [])
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(
                store: store,
                windowFactory: factory,
                tabFolderPicker: TabFolderPickerStub(folders: [folder])
            )
            try await coordinator.restorePortals()

            try await coordinator.createPortal(for: nil)

            let emptyPortal = try XCTUnwrap(coordinator.portalStates.first)
            XCTAssertTrue(emptyPortal.tabs.isEmpty)
            XCTAssertNil(emptyPortal.selectedTabID)
            XCTAssertEqual(factory.windows.count, 1)

            factory.windows[0].onAddTab?()
            await coordinator.waitForTabMutationForTesting()

            XCTAssertEqual(coordinator.portalStates[0].tabs.map(\.folderURL), [folder])
            XCTAssertEqual(
                coordinator.portalStates[0].selectedTabID,
                coordinator.portalStates[0].tabs[0].id
            )
            let saves = await store.savedSnapshots()
            XCTAssertEqual(saves.count, 2)
            XCTAssertTrue(saves[0][0].tabs.isEmpty)
            XCTAssertEqual(saves[1], coordinator.portalStates)
        }
    }

    @MainActor
    func testUserPlacementCommitPersistsUpdatedState() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let updatedFrame = NSRect(x: 90, y: 100, width: 480, height: 360)
        let expectedFrame = try snappedPlacementFrame(updatedFrame)

        factory.windows[0].simulateUserPlacementCommit(updatedFrame)
        await coordinator.waitForPersistenceForTesting()

        XCTAssertEqual(coordinator.portalStates[0].frame, expectedFrame)
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves.last?.first?.frame, expectedFrame)
        XCTAssertNil(coordinator.persistenceError)
    }

    @MainActor
    func testUserResizeCommitPersistsFrameAndCapacityTogether() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let capacity = try GridCapacity(columns: 5, rows: 3)
        let contentSize = PortalViewController.contentSize(
            for: capacity,
            iconLayout: portal.iconLayout
        )
        let frameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.resizable]
        ).size
        let resizedFrame = NSRect(
            origin: NSPoint(x: 90, y: 100),
            size: frameSize
        )
        let expectedFrame = try snappedPlacementFrame(resizedFrame)

        factory.windows[0].simulateUserResizeCommit(resizedFrame, capacity: capacity)
        await coordinator.waitForPersistenceForTesting()

        XCTAssertEqual(coordinator.portalStates[0].gridCapacity, capacity)
        XCTAssertEqual(coordinator.portalStates[0].frame, expectedFrame)
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves[0], coordinator.portalStates)
    }

    @MainActor
    func testTopologyReconciliationMovesWindowWithoutPersistingHomePlacement() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let originalPlacement = portal.placement
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let initialSnapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(initialSnapshot) }
        )
        try await coordinator.restorePortals()
        let changedDisplay = DisplayDescriptor(
            identity: coordinatorTestDisplay.identity,
            visibleFrame: CGRect(x: 0, y: 0, width: 900, height: 700)
        )
        let changedSnapshot = try DisplaySnapshot(
            displays: [changedDisplay],
            primaryDisplay: changedDisplay.identity
        )

        coordinator.reconcileDisplayTopology(.success(changedSnapshot))
        await coordinator.waitForPersistenceForTesting()
        let saves = await store.savedSnapshots()

        XCTAssertEqual(coordinator.portalStates[0].placement, originalPlacement)
        XCTAssertEqual(saves, [])
        let presentedFrame = try XCTUnwrap(factory.windows[0].systemFrames.last)
        XCTAssertTrue(try PortalFrameConstraints.isValidPlacement(
            frame: presentedFrame,
            visibleFrame: changedDisplay.visibleFrame,
            otherPortalFrames: [],
            minimumGap: PortalSpacing.medium.points
        ))
        XCTAssertNil(coordinator.displayError)
    }

    @MainActor
    func testPrimarySwitchMovesEveryPortalEvenWhenOldPrimaryRemainsConnected() async throws {
        let first = try makePortal(path: "/tmp/first", x: 100)
        let second = try makePortal(path: "/tmp/second", x: 500)
        let store = PortalStoreSpy(portals: [first, second])
        let factory = PortalWindowFactorySpy()
        let oldPrimary = coordinatorTestDisplay
        let newPrimary = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "new-primary"),
            visibleFrame: CGRect(x: -1800, y: 100, width: 1200, height: 700)
        )
        let initialSnapshot = try DisplaySnapshot(
            displays: [oldPrimary, newPrimary],
            primaryDisplay: oldPrimary.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(initialSnapshot) }
        )
        try await coordinator.restorePortals()

        let switchedSnapshot = try DisplaySnapshot(
            displays: [newPrimary, oldPrimary],
            primaryDisplay: newPrimary.identity
        )
        coordinator.reconcileDisplayTopology(.success(switchedSnapshot))
        await coordinator.waitForPersistenceForTesting()

        XCTAssertTrue(factory.windows.allSatisfy {
            newPrimary.visibleFrame.intersects($0.presentedFrame ?? .zero)
        })
        XCTAssertEqual(coordinator.portalStates.map(\.placement), [first.placement, second.placement])
        let savedSnapshots = await store.savedSnapshots()
        XCTAssertTrue(savedSnapshots.isEmpty)
    }

    @MainActor
    func testPrimarySwitchNeverMixesAPartialRememberedLayoutWithCurrentFrames() async throws {
        let oldPrimary = coordinatorTestDisplay
        let newPrimary = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "new-primary"),
            visibleFrame: CGRect(x: -1800, y: 100, width: 1200, height: 700)
        )
        let firstOldFrame = CGRect(x: 100, y: 600, width: 320, height: 240)
        var first = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: firstOldFrame,
            display: oldPrimary
        )
        let second = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/second"),
            frame: CGRect(x: 500, y: 600, width: 320, height: 240),
            display: oldPrimary
        )
        let staleRememberedFrame = CGRect(x: -1300, y: 500, width: 320, height: 240)
        try first.recordUserPlacement(frame: staleRememberedFrame, display: newPrimary)
        try first.recordUserPlacement(frame: firstOldFrame, display: oldPrimary)

        let store = PortalStoreSpy(portals: [first, second])
        let factory = PortalWindowFactorySpy()
        let initialSnapshot = try DisplaySnapshot(
            displays: [oldPrimary, newPrimary],
            primaryDisplay: oldPrimary.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(initialSnapshot) }
        )
        try await coordinator.restorePortals()

        let switchedSnapshot = try DisplaySnapshot(
            displays: [newPrimary, oldPrimary],
            primaryDisplay: newPrimary.identity
        )
        coordinator.reconcileDisplayTopology(.success(switchedSnapshot))
        await coordinator.waitForPersistenceForTesting()

        let frames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertNotEqual(frames[0], staleRememberedFrame)
        XCTAssertFalse(frames[0].intersects(frames[1]))
        XCTAssertTrue(frames.allSatisfy(newPrimary.visibleFrame.contains))
    }

    @MainActor
    func testManualRepairPersistsOnlyPanelsOutsidePrimaryDisplay() async throws {
        let visible = try makePortal(path: "/tmp/visible", x: 100)
        let lost = try makePortal(path: "/tmp/lost", x: 500)
        let store = PortalStoreSpy(portals: [visible, lost])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let visibleFrame = try XCTUnwrap(factory.windows[0].presentedFrame)
        factory.windows[1].presentedFrame = CGRect(
            x: 4_000,
            y: -2_000,
            width: lost.frame.width,
            height: lost.frame.height
        )

        let repairedCount = try await coordinator.repairPanelPositions()

        XCTAssertEqual(repairedCount, 1)
        XCTAssertEqual(factory.windows[0].presentedFrame, visibleFrame)
        XCTAssertTrue(coordinatorTestDisplay.visibleFrame.intersects(
            try XCTUnwrap(factory.windows[1].presentedFrame)
        ))
        XCTAssertEqual(coordinator.portalStates[0].placement, visible.placement)
        XCTAssertEqual(coordinator.portalStates[1].placement.homeDisplay, coordinatorTestDisplay.identity)
        let savedSnapshots = await store.savedSnapshots()
        XCTAssertEqual(savedSnapshots.count, 1)
        XCTAssertEqual(factory.windows[1].systemPlacementAnimations.last, true)
    }

    @MainActor
    func testManualRepairDoesNothingWhenEveryPanelIsAlreadyVisible() async throws {
        let portal = try makePortal(path: "/tmp/visible", x: 100)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let frame = factory.windows[0].presentedFrame

        let repairedCount = try await coordinator.repairPanelPositions()

        XCTAssertEqual(repairedCount, 0)
        XCTAssertEqual(factory.windows[0].presentedFrame, frame)
        let savedSnapshots = await store.savedSnapshots()
        XCTAssertTrue(savedSnapshots.isEmpty)
    }

    @MainActor
    func testManualRepairMovesOnlyTheLaterConflictingPanel() async throws {
        let first = try makePortal(path: "/tmp/first", x: 100)
        let second = try makePortal(path: "/tmp/second", x: 500)
        let store = PortalStoreSpy(portals: [first, second])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let fixedFrame = try XCTUnwrap(factory.windows[0].presentedFrame)
        factory.windows[1].presentedFrame = fixedFrame.offsetBy(dx: 40, dy: 20)

        let repairedCount = try await coordinator.repairPanelPositions()

        XCTAssertEqual(repairedCount, 1)
        XCTAssertEqual(factory.windows[0].presentedFrame, fixedFrame)
        XCTAssertFalse(try XCTUnwrap(factory.windows[1].presentedFrame).intersects(fixedFrame))
        XCTAssertEqual(coordinator.portalStates[0].placement, first.placement)
        let savedSnapshots = await store.savedSnapshots()
        XCTAssertEqual(savedSnapshots.count, 1)
    }

    @MainActor
    func testManualRepairSaveFailureLeavesEveryRuntimeFrameUntouched() async throws {
        let portal = try makePortal(path: "/tmp/lost", x: 100)
        let store = PortalStoreSpy(portals: [portal], saveError: .rejected)
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let lostFrame = CGRect(x: 4_000, y: -2_000, width: 320, height: 240)
        factory.windows[0].presentedFrame = lostFrame

        do {
            _ = try await coordinator.repairPanelPositions()
            XCTFail("Repair should surface persistence failure")
        } catch {
            XCTAssertEqual(error as? PortalStoreFixtureError, .rejected)
        }

        XCTAssertEqual(factory.windows[0].presentedFrame, lostFrame)
        XCTAssertEqual(coordinator.portalStates[0], portal)
        let savedSnapshots = await store.savedSnapshots()
        XCTAssertTrue(savedSnapshots.isEmpty)
    }

    @MainActor
    func testManualRepairDoesNotReportSuccessWhenWindowDeclinesPlacement() async throws {
        let portal = try makePortal(path: "/tmp/lost", x: 100)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let lostFrame = CGRect(x: 4_000, y: -2_000, width: 320, height: 240)
        factory.windows[0].presentedFrame = lostFrame
        factory.windows[0].acceptsSystemPlacement = false

        do {
            _ = try await coordinator.repairPanelPositions()
            XCTFail("Repair should not report success when the window declines placement")
        } catch {
            XCTAssertEqual(error as? PortalCoordinatorError, .layoutRepairBusy)
        }
        await coordinator.waitForPersistenceForTesting()

        XCTAssertEqual(factory.windows[0].presentedFrame, lostFrame)
        let savedSnapshots = await store.savedSnapshots()
        XCTAssertEqual(savedSnapshots.count, 1)
    }

    @MainActor
    func testPrimarySwitchKeepsPortalsOnPrimaryWithoutOverwritingDurablePlacement() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let originalPlacement = portal.placement
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let initialSnapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(initialSnapshot) }
        )
        try await coordinator.restorePortals()
        let fallback = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "fallback-display"),
            visibleFrame: CGRect(x: -1000, y: 0, width: 1000, height: 700)
        )
        let displacedSnapshot = try DisplaySnapshot(
            displays: [fallback],
            primaryDisplay: fallback.identity
        )
        let returnedSnapshot = try DisplaySnapshot(
            displays: [fallback, coordinatorTestDisplay],
            primaryDisplay: fallback.identity
        )

        coordinator.reconcileDisplayTopology(.success(displacedSnapshot))
        coordinator.reconcileDisplayTopology(.success(returnedSnapshot))
        await coordinator.waitForPersistenceForTesting()
        let saves = await store.savedSnapshots()

        XCTAssertEqual(coordinator.portalStates[0].placement, originalPlacement)
        XCTAssertEqual(saves, [])
        let returnedFrame = try XCTUnwrap(factory.windows[0].systemFrames.last)
        XCTAssertTrue(fallback.visibleFrame.contains(returnedFrame))
    }

    @MainActor
    func testDeferredTopologyReconcilesAfterUserInteractionCommits() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        factory.windows[0].acceptsSystemPlacement = false
        let changedDisplay = DisplayDescriptor(
            identity: coordinatorTestDisplay.identity,
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 700)
        )
        let changedSnapshot = try DisplaySnapshot(
            displays: [changedDisplay],
            primaryDisplay: changedDisplay.identity
        )

        coordinator.reconcileDisplayTopology(.success(changedSnapshot))
        await coordinator.waitForPersistenceForTesting()
        factory.windows[0].acceptsSystemPlacement = true
        let userFrame = CGRect(x: 120, y: 140, width: 360, height: 280)
        let expectedFrame = try snappedPlacementFrame(userFrame)
        factory.windows[0].simulateUserPlacementCommit(userFrame)
        await coordinator.waitForPersistenceForTesting()
        let saves = await store.savedSnapshots()

        XCTAssertEqual(coordinator.portalStates[0].frame, expectedFrame)
        XCTAssertEqual(saves.last?.first?.frame, expectedFrame)
        XCTAssertEqual(factory.windows[0].systemFrames.last, expectedFrame)
        XCTAssertNil(coordinator.displayError)
        XCTAssertNil(coordinator.persistenceError)
    }

    @MainActor
    func testUserPlacementRetriesAfterTransientDisplaySnapshotFailure() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let snapshotBox = DisplaySnapshotResultBox(.success(snapshot))
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { snapshotBox.result }
        )
        try await coordinator.restorePortals()
        snapshotBox.result = .failure(.missingPrimaryScreen)
        let movedFrame = CGRect(x: 130, y: 150, width: 360, height: 280)
        let expectedFrame = try snappedPlacementFrame(movedFrame)

        factory.windows[0].simulateUserPlacementCommit(movedFrame)
        await coordinator.waitForPersistenceForTesting()
        let savesBeforeRecovery = await store.savedSnapshots()
        XCTAssertEqual(coordinator.portalStates[0].frame, portal.frame)
        XCTAssertEqual(savesBeforeRecovery, [])

        snapshotBox.result = .success(snapshot)
        coordinator.reconcileDisplayTopology(.success(snapshot))
        await coordinator.waitForPersistenceForTesting()
        let saves = await store.savedSnapshots()

        XCTAssertEqual(coordinator.portalStates[0].frame, expectedFrame)
        XCTAssertEqual(saves.last?.first?.frame, expectedFrame)
        XCTAssertNil(coordinator.displayError)
    }

    @MainActor
    func testNewerPendingUserPlacementSurvivesOlderSaveCompletion() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = SuspendingPortalStore(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let snapshotBox = DisplaySnapshotResultBox(.success(snapshot))
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { snapshotBox.result }
        )
        try await coordinator.restorePortals()
        await store.suspendNextSave()
        let firstFrame = CGRect(x: 80, y: 90, width: 360, height: 280)
        factory.windows[0].simulateUserPlacementCommit(firstFrame)
        await store.waitUntilSaveIsSuspended()
        snapshotBox.result = .failure(.missingPrimaryScreen)
        let latestFrame = CGRect(x: 180, y: 190, width: 380, height: 300)
        let expectedFirstFrame = try snappedPlacementFrame(firstFrame)
        let expectedLatestFrame = try snappedPlacementFrame(latestFrame)
        factory.windows[0].simulateUserPlacementCommit(latestFrame)

        await store.resumeSave()
        await coordinator.waitForPersistenceForTesting()
        snapshotBox.result = .success(snapshot)
        coordinator.reconcileDisplayTopology(.success(snapshot))
        await coordinator.waitForPersistenceForTesting()
        let saves = await store.savedSnapshots()

        XCTAssertEqual(saves.map { $0[0].frame }, [expectedFirstFrame, expectedLatestFrame])
        XCTAssertEqual(coordinator.portalStates[0].frame, expectedLatestFrame)
    }

    @MainActor
    func testPlacementSaveFailureStillAppliesSafeDurableTopology() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal], saveError: .rejected)
        let factory = PortalWindowFactorySpy()
        let persistenceErrors = PersistenceErrorPresenterSpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            persistenceErrorPresenter: persistenceErrors,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let durableRuntimeFrame = try XCTUnwrap(factory.windows[0].presentedFrame)

        factory.windows[0].simulateUserPlacementCommit(
            CGRect(x: 180, y: 190, width: 380, height: 300)
        )
        await coordinator.waitForPersistenceForTesting()

        XCTAssertEqual(coordinator.portalStates[0].frame, portal.frame)
        XCTAssertEqual(factory.windows[0].systemFrames.last, durableRuntimeFrame)
        XCTAssertEqual(coordinator.persistenceError as? PortalStoreFixtureError, .rejected)
        XCTAssertEqual(persistenceErrors.errors.count, 1)
    }

    @MainActor
    func testTerminationRetriesPendingPlacementWithRecoveredSnapshot() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let snapshotBox = DisplaySnapshotResultBox(.success(snapshot))
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { snapshotBox.result }
        )
        try await coordinator.restorePortals()
        snapshotBox.result = .failure(.missingPrimaryScreen)
        let movedFrame = CGRect(x: 160, y: 170, width: 380, height: 300)
        let expectedFrame = try snappedPlacementFrame(movedFrame)
        factory.windows[0].simulateUserPlacementCommit(movedFrame)
        await coordinator.waitForPersistenceForTesting()
        snapshotBox.result = .success(snapshot)

        await coordinator.prepareForTermination()
        let saves = await store.savedSnapshots()

        XCTAssertEqual(saves.last?.first?.frame, expectedFrame)
        XCTAssertEqual(coordinator.portalStates[0].frame, expectedFrame)
    }

    @MainActor
    func testCreateAndPlacementSaveAreSerializedWithoutStaleOverwrite() async throws {
        try await withPortalDirectory { folder in
            let existing = try makePortal(path: "/tmp/existing", x: 10)
            let store = SuspendingPortalStore(portals: [existing])
            let factory = PortalWindowFactorySpy()
            let snapshot = try DisplaySnapshot(
                displays: [coordinatorTestDisplay],
                primaryDisplay: coordinatorTestDisplay.identity
            )
            let coordinator = PortalCoordinator(
                store: store,
                windowFactory: factory,
                displaySnapshotProvider: { .success(snapshot) }
            )
            try await coordinator.restorePortals()
            await store.suspendNextSave()

            let createTask = Task {
                try await coordinator.createPortal(
                    for: folder,
                    frame: CGRect(x: 500, y: 20, width: 320, height: 240)
                )
            }
            await store.waitUntilSaveIsSuspended()
            let movedFrame = CGRect(x: 90, y: 100, width: 360, height: 280)
            let expectedFrame = try snappedPlacementFrame(movedFrame)
            factory.windows[0].simulateUserPlacementCommit(movedFrame)
            let fallback = DisplayDescriptor(
                identity: DisplayIdentity(rawValue: "fallback-display"),
                visibleFrame: CGRect(x: -1000, y: 0, width: 1000, height: 700)
            )
            coordinator.reconcileDisplayTopology(
                .success(
                    try DisplaySnapshot(
                        displays: [fallback],
                        primaryDisplay: fallback.identity
                    )
                )
            )
            await store.resumeSave()
            try await createTask.value
            await coordinator.waitForPersistenceForTesting()
            let saves = await store.savedSnapshots()

            XCTAssertEqual(coordinator.portalStates.count, 2)
            XCTAssertEqual(coordinator.portalStates[0].frame, expectedFrame)
            XCTAssertEqual(saves.map(\.count), [2, 2])
            XCTAssertEqual(saves.last?.first?.frame, expectedFrame)
            XCTAssertEqual(factory.windows.count, 2)
            for window in factory.windows {
                let frame = try XCTUnwrap(window.systemFrames.last)
                XCTAssertTrue(fallback.visibleFrame.contains(frame))
            }
        }
    }

    @MainActor
    func testTerminationPreparationWaitsForQueuedPlacementSave() async throws {
        let portal = try makePortal(path: "/tmp/existing", x: 10)
        let store = SuspendingPortalStore(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        await store.suspendNextSave()
        let movedFrame = CGRect(x: 90, y: 100, width: 360, height: 280)
        let expectedFrame = try snappedPlacementFrame(movedFrame)
        factory.windows[0].simulateUserPlacementCommit(movedFrame)
        await store.waitUntilSaveIsSuspended()
        var didPrepare = false
        let prepareTask = Task {
            await coordinator.prepareForTermination()
            didPrepare = true
        }

        await Task.yield()
        XCTAssertFalse(didPrepare)
        await store.resumeSave()
        await prepareTask.value
        let saves = await store.savedSnapshots()

        XCTAssertTrue(didPrepare)
        XCTAssertEqual(saves.last?.first?.frame, expectedFrame)
    }

    @MainActor
    func testCancelledQueuedMutationDoesNotSaveOrChangeState() async throws {
        var portal = try makePortal(path: "/tmp/existing", x: 10)
        let secondTab = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let portalID = portal.id
        let originalSelection = portal.selectedTabID
        let store = SuspendingPortalStore(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        await store.suspendNextSave()
        factory.windows[0].simulateUserPlacementCommit(
            CGRect(x: 80, y: 90, width: 360, height: 280)
        )
        await store.waitUntilSaveIsSuspended()

        let selectionTask = Task {
            try await coordinator.selectTab(secondTab, in: portalID)
        }
        await Task.yield()
        selectionTask.cancel()
        await store.resumeSave()
        do {
            try await selectionTask.value
            XCTFail("A cancelled queued mutation must not execute")
        } catch is CancellationError {
            // Expected.
        }
        await coordinator.waitForPersistenceForTesting()
        let saves = await store.savedSnapshots()

        XCTAssertEqual(coordinator.portalStates[0].selectedTabID, originalSelection)
        XCTAssertEqual(saves.count, 1)
    }

    @MainActor
    func testSaveFailureDoesNotCreatePartialPortal() async throws {
        try await withPortalDirectory { folder in
            let store = PortalStoreSpy(portals: [], saveError: .rejected)
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(store: store, windowFactory: factory)
            try await coordinator.restorePortals()

            do {
                try await coordinator.createPortal(
                    for: folder,
                    frame: NSRect(x: 0, y: 0, width: 320, height: 240)
                )
                XCTFail("Persistence failure must abort portal creation")
            } catch let error as PortalStoreFixtureError {
                XCTAssertEqual(error, .rejected)
            }

            XCTAssertTrue(coordinator.portalStates.isEmpty)
            XCTAssertTrue(factory.windows.isEmpty)
        }
    }

    @MainActor
    func testSelectingAndClosingTabsPersistAndUpdateWindow() async throws {
        var portal = try makePortal(path: "/tmp/first", x: 10)
        let secondID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let firstID = portal.selectedTabID
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(store: store, windowFactory: factory)
        try await coordinator.restorePortals()

        try await coordinator.selectTab(secondID, in: portal.id)
        XCTAssertEqual(coordinator.portalStates[0].selectedTabID, secondID)
        XCTAssertEqual(factory.windows[0].updatedPortals.last?.selectedTabID, secondID)

        await coordinator.closeTab(secondID, in: portal.id)
        XCTAssertEqual(coordinator.portalStates[0].tabs.map(\.id), [firstID])
        XCTAssertEqual(coordinator.portalStates[0].selectedTabID, firstID)
        XCTAssertEqual(factory.windows[0].updateCount, 2)
    }

    @MainActor
    func testSettingsTabMovePersistsOrderAndPreservesSelection() async throws {
        var portal = try makePortal(path: "/tmp/first", x: 10)
        let secondID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let thirdID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/third"))
        let selectedID = try XCTUnwrap(portal.selectedTabID)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(store: store, windowFactory: factory)
        try await coordinator.restorePortals()

        factory.windows[0].onMoveTab?(thirdID, 0)
        await coordinator.waitForTabMutationForTesting()

        XCTAssertEqual(coordinator.portalStates[0].tabs.map(\.id), [thirdID, selectedID, secondID])
        XCTAssertEqual(coordinator.portalStates[0].selectedTabID, selectedID)
        XCTAssertEqual(
            factory.windows[0].updatedPortals.last?.tabs.map(\.id),
            [thirdID, selectedID, secondID]
        )
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves.last?.first?.tabs.map(\.id), [thirdID, selectedID, secondID])
    }

    @MainActor
    func testCancelledCloseTabDoesNotPresentPersistenceFailure() async throws {
        var portal = try makePortal(path: "/tmp/first", x: 10)
        let secondID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let factory = PortalWindowFactorySpy()
        let persistenceErrors = PersistenceErrorPresenterSpy()
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal], saveError: .cancelled),
            windowFactory: factory,
            persistenceErrorPresenter: persistenceErrors
        )
        try await coordinator.restorePortals()

        factory.windows[0].onCloseTab?(secondID)
        await coordinator.waitForTabMutationForTesting()

        XCTAssertEqual(coordinator.portalStates, [portal])
        XCTAssertNil(coordinator.persistenceError)
        XCTAssertTrue(persistenceErrors.errors.isEmpty)
    }

    @MainActor
    func testAddingTabValidatesPersistsAndSelectsIt() async throws {
        try await withPortalDirectory { newFolder in
            let portal = try makePortal(path: "/tmp/first", x: 10)
            let picker = TabFolderPickerStub(folders: [newFolder])
            let store = PortalStoreSpy(portals: [portal])
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(
                store: store,
                windowFactory: factory,
                tabFolderPicker: picker
            )
            try await coordinator.restorePortals()

            await coordinator.addTab(to: portal.id)

            XCTAssertEqual(coordinator.portalStates[0].tabs.count, 2)
            XCTAssertEqual(coordinator.portalStates[0].tabs.last?.folderURL, newFolder.standardizedFileURL)
            XCTAssertEqual(
                coordinator.portalStates[0].selectedTabID,
                coordinator.portalStates[0].tabs.last?.id
            )
            XCTAssertEqual(factory.windows[0].updateCount, 1)
        }
    }

    @MainActor
    func testFolderSelectionInOnePortalDoesNotBlockAnotherPortalTabMutation() async throws {
        let firstPortal = try makePortal(path: "/tmp/first", x: 10)
        var secondPortal = try makePortal(path: "/tmp/second", x: 400)
        let secondTabID = try secondPortal.appendTab(
            folderURL: URL(fileURLWithPath: "/tmp/second-extra")
        )
        let picker = SuspendedTabFolderPicker()
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [firstPortal, secondPortal]),
            windowFactory: factory,
            tabFolderPicker: picker
        )
        try await coordinator.restorePortals()

        factory.windows[0].onAddTab?()
        for _ in 0..<100 where picker.selectionCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(picker.selectionCount, 1)

        factory.windows[1].onSelectTab?(secondTabID)
        for _ in 0..<100 where coordinator.portalStates[1].selectedTabID != secondTabID {
            await Task.yield()
        }

        XCTAssertEqual(coordinator.portalStates[1].selectedTabID, secondTabID)
        picker.complete(with: nil)
        await coordinator.waitForTabMutationForTesting()
    }

    @MainActor
    func testPortalManagementPublishesShowsAndPersistsBeforeUpdating() async throws {
        var portal = try makePortal(path: "/tmp/first", x: 10)
        let selectedID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/selected"))
        try portal.selectTab(selectedID)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(store: store, windowFactory: factory)
        var menus: [[PortalMenuEntry]] = []
        coordinator.onPortalsChanged = { menus.append($0) }
        try await coordinator.restorePortals()

        XCTAssertEqual(menus.last, [
            PortalMenuEntry(
                id: portal.id,
                title: "selected"
            ),
        ])
        coordinator.showPortal(portal.id)
        XCTAssertEqual(factory.windows[0].presentCount, 2)
        coordinator.hidePortal(portal.id)
        XCTAssertEqual(factory.windows[0].hideCount, 1)
        coordinator.showPortalSettings(portal.id)
        coordinator.confirmPortalRemoval(portal.id)
        XCTAssertEqual(factory.windows[0].showPortalSettingsCount, 1)
        XCTAssertEqual(factory.windows[0].confirmPortalRemovalCount, 1)

        await coordinator.setIconSize(.large, for: portal.id)

        XCTAssertEqual(coordinator.portalStates[0].iconSize, .large)
        XCTAssertEqual(factory.windows[0].updatedPortals.last?.iconSize, .large)
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves.last?.first?.iconSize, .large)
        XCTAssertEqual(menus.last?.first?.title, "selected")

        await coordinator.removePortal(portal.id)
        XCTAssertTrue(coordinator.portalStates.isEmpty)
        XCTAssertEqual(factory.windows[0].closeCount, 1)
        XCTAssertEqual(menus.last, [])
    }

    @MainActor
    func testPortalManagementSaveFailureLeavesRuntimeStateUntouched() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal], saveError: .rejected)
        let factory = PortalWindowFactorySpy()
        let persistenceErrors = PersistenceErrorPresenterSpy()
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            persistenceErrorPresenter: persistenceErrors
        )
        try await coordinator.restorePortals()

        await coordinator.setIconSize(.large, for: portal.id)
        XCTAssertEqual(coordinator.portalStates, [portal])
        XCTAssertEqual(factory.windows[0].updateCount, 0)
        XCTAssertEqual(coordinator.persistenceError as? PortalStoreFixtureError, .rejected)
        XCTAssertEqual(persistenceErrors.errors.count, 1)

        await coordinator.removePortal(portal.id)
        XCTAssertEqual(coordinator.portalStates, [portal])
        XCTAssertEqual(factory.windows[0].closeCount, 0)
        XCTAssertEqual(coordinator.persistenceError as? PortalStoreFixtureError, .rejected)
        XCTAssertEqual(persistenceErrors.errors.count, 2)
    }

    @MainActor
    func testFailedSortAndTintPersistenceRestoresSettingsPresentation() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal], saveError: .rejected),
            windowFactory: factory,
            persistenceErrorPresenter: PersistenceErrorPresenterSpy()
        )
        try await coordinator.restorePortals()

        await coordinator.setSortOrder(.modificationDate, for: portal.id)
        await coordinator.setTint(.purple, for: portal.id)

        XCTAssertEqual(coordinator.portalStates, [portal])
        XCTAssertEqual(factory.windows[0].updatedPortals, [portal, portal])
    }

    @MainActor
    func testPortalMenuCanChangeSortTintPinAndRemovePortal() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal]),
            windowFactory: factory
        )
        try await coordinator.restorePortals()

        factory.windows[0].onSetSortOrder?(.modificationDate)
        await coordinator.waitForTabMutationForTesting()
        XCTAssertEqual(coordinator.portalStates[0].sortOrder, .modificationDate)

        factory.windows[0].onSetTint?(.indigo)
        await coordinator.waitForTabMutationForTesting()
        XCTAssertEqual(coordinator.portalStates[0].tint, .indigo)

        factory.windows[0].onSetPinned?(true)
        await coordinator.waitForTabMutationForTesting()
        XCTAssertTrue(coordinator.portalStates[0].isPinned)
        XCTAssertEqual(factory.windows[0].updatedPortals.last?.isPinned, true)

        factory.windows[0].onRemovePortal?()
        await coordinator.waitForTabMutationForTesting()
        XCTAssertTrue(coordinator.portalStates.isEmpty)
        XCTAssertEqual(factory.windows[0].closeCount, 1)
    }

    @MainActor
    func testBackgroundStyleUpdatesOnlyRequestedPortalAfterPersistence() async throws {
        let first = try makePortal(path: "/tmp/first", x: 10)
        let second = try makePortal(path: "/tmp/second", x: 400)
        let store = PortalStoreSpy(portals: [first, second])
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(store: store, windowFactory: factory)
        try await coordinator.restorePortals()

        await coordinator.setBackgroundStyle(.lowTransparency, for: second.id)

        XCTAssertEqual(coordinator.portalStates[0].backgroundStyle, .standard)
        XCTAssertEqual(coordinator.portalStates[1].backgroundStyle, .lowTransparency)
        XCTAssertEqual(factory.windows[0].updateCount, 0)
        XCTAssertEqual(
            factory.windows[1].updatedPortals.last?.backgroundStyle,
            .lowTransparency
        )
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves.last?.map(\.backgroundStyle), [.standard, .lowTransparency])
    }

    @MainActor
    func testGlobalBackgroundTypeUpdatesEveryWindowWithoutChangingPortalTints() async throws {
        var first = try makePortal(path: "/tmp/first", x: 10)
        first.updateTint(.red)
        var second = try makePortal(path: "/tmp/second", x: 400)
        second.updateTint(.blue)
        let store = PortalStoreSpy(portals: [first, second])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        var appearance = PortalAppearancePreferences.defaults
        appearance.backgroundType = .frostedGlass

        XCTAssertTrue(coordinator.updatePortalAppearance(appearance))

        XCTAssertEqual(coordinator.portalStates.map(\.tint), [.red, .blue])
        XCTAssertTrue(factory.windows.allSatisfy {
            $0.updatedAppearances.last?.backgroundType == .frostedGlass
        })
        let saves = await store.savedSnapshots()
        XCTAssertTrue(saves.isEmpty)
    }

    @MainActor
    func testBackgroundStyleSaveFailureLeavesPortalAndWindowUntouched() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal], saveError: .rejected)
        let factory = PortalWindowFactorySpy()
        let persistenceErrors = PersistenceErrorPresenterSpy()
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            persistenceErrorPresenter: persistenceErrors
        )
        try await coordinator.restorePortals()

        await coordinator.setBackgroundStyle(.highTransparency, for: portal.id)

        XCTAssertEqual(coordinator.portalStates, [portal])
        XCTAssertEqual(factory.windows[0].updateCount, 0)
        XCTAssertEqual(coordinator.persistenceError as? PortalStoreFixtureError, .rejected)
        XCTAssertEqual(persistenceErrors.errors.count, 1)
    }

    @MainActor
    func testPinnedStateSaveFailureLeavesPortalAndWindowUntouched() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal], saveError: .rejected)
        let factory = PortalWindowFactorySpy()
        let persistenceErrors = PersistenceErrorPresenterSpy()
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            persistenceErrorPresenter: persistenceErrors
        )
        try await coordinator.restorePortals()

        factory.windows[0].onSetPinned?(true)
        await coordinator.waitForTabMutationForTesting()

        XCTAssertFalse(coordinator.portalStates[0].isPinned)
        XCTAssertEqual(factory.windows[0].updateCount, 0)
        XCTAssertEqual(coordinator.persistenceError as? PortalStoreFixtureError, .rejected)
        XCTAssertEqual(persistenceErrors.errors.count, 1)
    }

    @MainActor
    func testLargeIconPresetPersistsAndAppliesMinimumPlacement() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        await coordinator.setIconSize(.large, for: portal.id)

        let updated = coordinator.portalStates[0]
        XCTAssertEqual(updated.iconSize, .large)
        XCTAssertEqual(updated.gridCapacity, portal.gridCapacity)
        let updatedContentSize = NSWindow.contentRect(
            forFrameRect: updated.frame,
            styleMask: [.resizable]
        ).size
        XCTAssertEqual(
            updatedContentSize,
            PortalViewController.contentSize(
                for: portal.gridCapacity,
                iconLayout: .fixed(.large)
            )
        )
        let appliedFrame = try XCTUnwrap(factory.windows[0].systemFrames.last)
        XCTAssertEqual(appliedFrame.size, updated.frame.size)
        XCTAssertTrue(coordinatorTestDisplay.visibleFrame.contains(appliedFrame))
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves.last, [updated])
    }

    @MainActor
    func testIconPresetExpansionIsRejectedWhenItWouldHitAnotherPortal() async throws {
        let first = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: NSRect(x: 100, y: 300, width: 320, height: 240),
            display: coordinatorTestDisplay
        )
        let largeContentSize = PortalViewController.contentSize(
            for: first.gridCapacity,
            iconLayout: .fixed(.large)
        )
        let largeFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: largeContentSize),
            styleMask: [.resizable]
        ).size
        let second = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/second"),
            frame: NSRect(
                x: first.frame.minX + largeFrameSize.width + 5,
                y: 300,
                width: 320,
                height: 240
            ),
            display: coordinatorTestDisplay
        )
        let store = PortalStoreSpy(portals: [first, second])
        let errors = PersistenceErrorPresenterSpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: PortalWindowFactorySpy(),
            persistenceErrorPresenter: errors,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        await coordinator.setIconSize(.large, for: first.id)

        XCTAssertEqual(coordinator.portalStates[0], first)
        XCTAssertEqual(
            errors.errors.compactMap { $0 as? PortalCoordinatorError },
            [.placementUnavailable]
        )
        let saves = await store.savedSnapshots()
        XCTAssertTrue(saves.isEmpty)
    }

    @MainActor
    func testIconLayoutChangePreservesCapacityAndFitsNewMetrics() async throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: NSRect(x: 20, y: 30, width: 560, height: 480),
            display: coordinatorTestDisplay
        )
        let store = PortalStoreSpy(portals: [portal])
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: PortalWindowFactorySpy()
        )
        try await coordinator.restorePortals()
        let expectedContentSize = PortalViewController.contentSize(
            for: portal.gridCapacity,
            iconLayout: .fixed(.large)
        )

        await coordinator.setIconSize(.large, for: portal.id)

        let updatedContentSize = NSWindow.contentRect(
            forFrameRect: NSRect(
                origin: .zero,
                size: coordinator.portalStates[0].frame.size
            ),
            styleMask: [.resizable]
        ).size
        XCTAssertEqual(updatedContentSize, expectedContentSize)
        XCTAssertEqual(coordinator.portalStates[0].gridCapacity, portal.gridCapacity)
    }

    @MainActor
    func testIconPresetChangesKeepThePortalTopLeftCornerFixed() async throws {
        let capacity = try GridCapacity(columns: 4, rows: 2)
        let mediumContentSize = PortalViewController.contentSize(
            for: capacity,
            iconLayout: .fixed(.medium)
        )
        let mediumFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: mediumContentSize),
            styleMask: [.resizable]
        ).size
        let visibleFrame = coordinatorTestDisplay.visibleFrame
        let initialFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.maxY - mediumFrameSize.height,
            width: mediumFrameSize.width,
            height: mediumFrameSize.height
        )
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: initialFrame,
            display: coordinatorTestDisplay,
            iconLayout: .fixed(.medium),
            gridCapacity: capacity
        )
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal]),
            windowFactory: PortalWindowFactorySpy(),
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        for iconSize: IconSize in [.large, .medium, .small] {
            await coordinator.setIconSize(iconSize, for: portal.id)
            let frame = coordinator.portalStates[0].frame
            XCTAssertEqual(frame.minX, initialFrame.minX)
            XCTAssertEqual(frame.maxY, initialFrame.maxY)
        }
    }

    @MainActor
    func testIconPresetChangeUsesTheCurrentHomeDisplayVisibleFrame() async throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: NSRect(x: 0, y: 500, width: 560, height: 400),
            display: coordinatorTestDisplay
        )
        let currentDisplay = DisplayDescriptor(
            identity: coordinatorTestDisplay.identity,
            visibleFrame: NSRect(x: 0, y: 0, width: 1280, height: 760)
        )
        let snapshot = try DisplaySnapshot(
            displays: [currentDisplay],
            primaryDisplay: currentDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal]),
            windowFactory: PortalWindowFactorySpy(),
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        await coordinator.setIconSize(.large, for: portal.id)

        let updated = coordinator.portalStates[0]
        XCTAssertEqual(updated.frame.maxY, currentDisplay.visibleFrame.maxY)
        XCTAssertEqual(
            updated.placement.homeEntry.referenceVisibleFrame,
            currentDisplay.visibleFrame
        )
    }

    @MainActor
    func testIconPresetDuringPrimarySwitchPreservesDurableHomeAndFollowsPrimary() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let fallback = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "fallback-display"),
            visibleFrame: CGRect(x: -1000, y: 0, width: 1000, height: 700)
        )
        let snapshotBox = DisplaySnapshotResultBox(
            .success(
                try DisplaySnapshot(
                    displays: [coordinatorTestDisplay],
                    primaryDisplay: coordinatorTestDisplay.identity
                )
            )
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { snapshotBox.result }
        )
        try await coordinator.restorePortals()
        snapshotBox.result = .success(
            try DisplaySnapshot(displays: [fallback], primaryDisplay: fallback.identity)
        )
        coordinator.reconcileDisplayTopology(snapshotBox.result)
        await coordinator.waitForPersistenceForTesting()

        await coordinator.setIconSize(.large, for: portal.id)

        XCTAssertEqual(coordinator.portalStates[0].placement.homeDisplay, portal.placement.homeDisplay)
        XCTAssertTrue(fallback.visibleFrame.contains(try XCTUnwrap(factory.windows[0].systemFrames.last)))

        snapshotBox.result = .success(
            try DisplaySnapshot(
                displays: [fallback, coordinatorTestDisplay],
                primaryDisplay: fallback.identity
            )
        )
        coordinator.reconcileDisplayTopology(snapshotBox.result)
        await coordinator.waitForPersistenceForTesting()

        XCTAssertTrue(fallback.visibleFrame.contains(try XCTUnwrap(factory.windows[0].systemFrames.last)))
        XCTAssertEqual(coordinator.portalStates[0].placement.homeDisplay, portal.placement.homeDisplay)
    }

    @MainActor
    func testLocatingFolderPreservesTabIdentityAndPersistsBeforeWindowUpdate() async throws {
        try await withPortalDirectory { replacement in
            var portal = try makePortal(path: "/tmp/missing", x: 10)
            portal.updateBackgroundStyle(.lowTransparency)
            portal.updateIconSize(.large)
            let store = PortalStoreSpy(portals: [portal])
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(
                store: store,
                windowFactory: factory,
                tabFolderPicker: TabFolderPickerStub(folders: [replacement])
            )
            try await coordinator.restorePortals()

            factory.windows[0].onLocateFolder?(try XCTUnwrap(portal.selectedTabID))
            await coordinator.waitForTabMutationForTesting()

            let updated = coordinator.portalStates[0]
            XCTAssertEqual(updated.tabs[0].id, portal.selectedTabID)
            XCTAssertEqual(updated.tabs[0].folderURL, replacement.standardizedFileURL)
            XCTAssertEqual(updated.backgroundStyle, .standard)
            XCTAssertEqual(updated.iconLayout, .fixed(.medium))
            XCTAssertEqual(factory.windows[0].updatedPortals.last, updated)
            let saves = await store.savedSnapshots()
            XCTAssertEqual(saves.last, [updated])
        }
    }

    @MainActor
    func testLocatingSamePathExplicitlyRestartsSelectedFolder() async throws {
        try await withPortalDirectory { folder in
            let portal = try makePortal(path: folder.path, x: 10)
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(
                store: PortalStoreSpy(portals: [portal]),
                windowFactory: factory,
                tabFolderPicker: TabFolderPickerStub(folders: [folder])
            )
            try await coordinator.restorePortals()

            factory.windows[0].onLocateFolder?(try XCTUnwrap(portal.selectedTabID))
            await coordinator.waitForTabMutationForTesting()

            XCTAssertEqual(coordinator.portalStates[0].tabs[0].folderURL, folder)
            XCTAssertEqual(factory.windows[0].selectedFolderReloadCount, 1)
        }
    }

    @MainActor
    func testLocateSaveFailureDoesNotRemapLivePortal() async throws {
        try await withPortalDirectory { replacement in
            let portal = try makePortal(path: "/tmp/missing", x: 10)
            let store = PortalStoreSpy(portals: [portal], saveError: .rejected)
            let factory = PortalWindowFactorySpy()
            let errors = CoordinatorErrorPresenterSpy()
            let persistenceErrors = PersistenceErrorPresenterSpy()
            let coordinator = PortalCoordinator(
                store: store,
                windowFactory: factory,
                tabFolderPicker: TabFolderPickerStub(folders: [replacement]),
                errorPresenter: errors,
                persistenceErrorPresenter: persistenceErrors
            )
            try await coordinator.restorePortals()

            factory.windows[0].onLocateFolder?(try XCTUnwrap(portal.selectedTabID))
            await coordinator.waitForTabMutationForTesting()

            XCTAssertEqual(coordinator.portalStates, [portal])
            XCTAssertEqual(factory.windows[0].updateCount, 0)
            XCTAssertTrue(errors.errors.isEmpty)
            XCTAssertEqual(persistenceErrors.errors.count, 1)
        }
    }

    @MainActor
    func testClosingLastTabRequiresConfirmationBeforeRemovingPortal() async throws {
        let portal = try makePortal(path: "/tmp/only", x: 10)
        let cancelConfirmer = LastTabConfirmerStub(responses: [false])
        let cancelStore = PortalStoreSpy(portals: [portal])
        let cancelFactory = PortalWindowFactorySpy()
        let cancelCoordinator = PortalCoordinator(
            store: cancelStore,
            windowFactory: cancelFactory,
            lastTabRemovalConfirmer: cancelConfirmer
        )
        try await cancelCoordinator.restorePortals()

        await cancelCoordinator.closeTab(try XCTUnwrap(portal.selectedTabID), in: portal.id)
        XCTAssertEqual(cancelCoordinator.portalStates, [portal])
        XCTAssertEqual(cancelFactory.windows[0].closeCount, 0)

        let confirmConfirmer = LastTabConfirmerStub(responses: [true])
        let confirmStore = PortalStoreSpy(portals: [portal])
        let confirmFactory = PortalWindowFactorySpy()
        let confirmCoordinator = PortalCoordinator(
            store: confirmStore,
            windowFactory: confirmFactory,
            lastTabRemovalConfirmer: confirmConfirmer
        )
        try await confirmCoordinator.restorePortals()

        await confirmCoordinator.closeTab(try XCTUnwrap(portal.selectedTabID), in: portal.id)
        XCTAssertTrue(confirmCoordinator.portalStates.isEmpty)
        XCTAssertEqual(confirmFactory.windows[0].closeCount, 1)
        let saves = await confirmStore.savedSnapshots()
        XCTAssertEqual(saves.last, [])
    }

    private func makePortal(path: String, x: CGFloat) throws -> Portal {
        try Portal(
            folderURL: URL(fileURLWithPath: path),
            frame: CGRect(x: x, y: 20, width: 320, height: 240),
            display: coordinatorTestDisplay
        )
    }

    private func snappedPlacementFrame(_ frame: CGRect) throws -> CGRect {
        let entry = try PlacementGeometry.capture(
            windowFrame: frame,
            visibleFrame: coordinatorTestDisplay.visibleFrame
        )
        return try PlacementGeometry.restore(
            record: entry,
            currentVisibleFrame: coordinatorTestDisplay.visibleFrame,
            gridSpacing: .snap(GridMetrics(iconSize: .medium).horizontalSpacing)
        )
    }
}

private actor PortalStoreSpy: PortalStoring {
    private var portals: [Portal]
    private var saves: [[Portal]] = []
    private let saveError: PortalStoreFixtureError?

    init(portals: [Portal], saveError: PortalStoreFixtureError? = nil) {
        self.portals = portals
        self.saveError = saveError
    }

    func load() async throws -> [Portal] {
        portals
    }

    func save(_ portals: [Portal]) async throws {
        switch saveError {
        case .rejected:
            throw PortalStoreFixtureError.rejected
        case .cancelled:
            throw CancellationError()
        case nil:
            break
        }
        self.portals = portals
        saves.append(portals)
    }

    func savedSnapshots() -> [[Portal]] {
        saves
    }
}

private actor SuspendingPortalStore: PortalStoring {
    private var portals: [Portal]
    private var saves: [[Portal]] = []
    private var shouldSuspendNextSave = false
    private var isSaveSuspended = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveContinuation: CheckedContinuation<Void, Never>?

    init(portals: [Portal]) {
        self.portals = portals
    }

    func load() async throws -> [Portal] {
        portals
    }

    func save(_ portals: [Portal]) async throws {
        if shouldSuspendNextSave {
            shouldSuspendNextSave = false
            isSaveSuspended = true
            let waiters = startWaiters
            startWaiters = []
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                saveContinuation = continuation
            }
            isSaveSuspended = false
        }
        self.portals = portals
        saves.append(portals)
    }

    func suspendNextSave() {
        shouldSuspendNextSave = true
    }

    func waitUntilSaveIsSuspended() async {
        guard !isSaveSuspended else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }

    func savedSnapshots() -> [[Portal]] {
        saves
    }
}

private enum PortalStoreFixtureError: Error, Equatable {
    case rejected
    case cancelled
}

@MainActor
private final class PortalWindowFactorySpy: PortalWindowBuilding {
    private(set) var createdPortalIDs: [PortalID] = []
    private(set) var createdPortals: [Portal] = []
    private(set) var windows: [PortalWindowPresenterSpy] = []

    func makeWindow(for portal: Portal) -> any PortalWindowPresenting {
        createdPortalIDs.append(portal.id)
        createdPortals.append(portal)
        let window = PortalWindowPresenterSpy()
        window.presentedFrame = portal.frame
        windows.append(window)
        return window
    }
}

@MainActor
private final class PortalWindowPresenterSpy: PortalWindowPresenting {
    var isUserPlacementInteractionActive = false
    var presentedFrame: NSRect?
    var onUserPlacementCommit: ((NSRect) -> Void)?
    var onUserResizeCommit: ((NSRect, GridCapacity) -> Void)?
    var onUserPlacementInteractionCancelled: (() -> Void)?
    var onSelectTab: ((FolderTabID) -> Void)?
    var onAddTab: (() -> Void)?
    var onCloseTab: ((FolderTabID) -> Void)?
    var onMoveTab: ((FolderTabID, Int) -> Void)?
    var onLocateFolder: ((FolderTabID) -> Void)?
    var onSetBackgroundStyle: ((PortalBackgroundStyle) -> Void)?
    var onSetIconSize: ((IconSize) -> Void)?
    var onRemovePortal: (() -> Void)?
    var onSetPinned: ((Bool) -> Void)?
    var onSetSortOrder: ((PortalSortOrder) -> Void)?
    var onSetTint: ((PortalTint) -> Void)?
    private(set) var presentCount = 0
    private(set) var hideCount = 0
    private(set) var updateCount = 0
    private(set) var closeCount = 0
    private(set) var updatedPortals: [Portal] = []
    private(set) var updatedAppearances: [PortalAppearancePreferences] = []
    private(set) var systemFrames: [NSRect] = []
    private(set) var systemPlacementAnimations: [Bool] = []
    private(set) var selectedFolderReloadCount = 0
    private(set) var showPortalSettingsCount = 0
    private(set) var confirmPortalRemovalCount = 0
    private(set) var constrainDrag: ((NSRect, NSRect, NSPoint) -> NSRect)?
    private(set) var isValidFrame: ((NSRect) -> Bool)?
    var acceptsSystemPlacement = true

    func present() {
        presentCount += 1
    }

    func hide() {
        hideCount += 1
    }

    func updatePortal(_ portal: Portal) {
        updateCount += 1
        updatedPortals.append(portal)
    }

    func updateAppearance(_ appearance: PortalAppearancePreferences) {
        updatedAppearances.append(appearance)
    }

    func configureUserPlacementConstraints(
        constrainDrag: @escaping (NSRect, NSRect, NSPoint) -> NSRect,
        isValidFrame: @escaping (NSRect) -> Bool
    ) {
        self.constrainDrag = constrainDrag
        self.isValidFrame = isValidFrame
    }

    func reloadSelectedFolder() {
        selectedFolderReloadCount += 1
    }

    func showPortalSettings() {
        showPortalSettingsCount += 1
    }

    func confirmPortalRemoval() {
        confirmPortalRemovalCount += 1
    }

    func applySystemPlacement(frame: NSRect, animated: Bool) -> Bool {
        guard acceptsSystemPlacement else { return false }
        systemFrames.append(frame)
        systemPlacementAnimations.append(animated)
        presentedFrame = frame
        return true
    }

    func close() {
        closeCount += 1
    }

    func simulateUserPlacementCommit(_ frame: NSRect) {
        onUserPlacementCommit?(frame)
    }

    func simulateUserResizeCommit(_ frame: NSRect, capacity: GridCapacity) {
        onUserResizeCommit?(frame, capacity)
    }
}

private let coordinatorTestDisplay = DisplayDescriptor(
    identity: DisplayIdentity(rawValue: "test-display"),
    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
)

@MainActor
private final class DisplaySnapshotResultBox {
    var result: Result<DisplaySnapshot, DisplaySnapshotError>

    init(_ result: Result<DisplaySnapshot, DisplaySnapshotError>) {
        self.result = result
    }
}

@MainActor
private final class TabFolderPickerStub: FolderPicking {
    private var folders: [URL]

    init(folders: [URL]) {
        self.folders = folders
    }

    func chooseFolder() async -> URL? {
        guard !folders.isEmpty else { return nil }
        return folders.removeFirst()
    }

    func cancel() {}
}

@MainActor
private final class SuspendedTabFolderPicker: FolderPicking {
    private var continuation: CheckedContinuation<URL?, Never>?
    private(set) var selectionCount = 0

    func chooseFolder() async -> URL? {
        selectionCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        complete(with: nil)
    }

    func complete(with url: URL?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: url)
    }
}

@MainActor
private final class LastTabConfirmerStub: LastTabRemovalConfirming {
    private var responses: [Bool]

    init(responses: [Bool]) {
        self.responses = responses
    }

    func confirmRemoval(folderName: String) async -> Bool {
        guard !responses.isEmpty else { return false }
        return responses.removeFirst()
    }
}

@MainActor
private final class CoordinatorErrorPresenterSpy: PortalCreationErrorPresenting {
    private(set) var errors: [Error] = []

    func present(_ error: Error) {
        errors.append(error)
    }
}

@MainActor
private final class PersistenceErrorPresenterSpy: PortalPersistenceErrorPresenting {
    private(set) var errors: [Error] = []

    func present(_ error: Error) {
        errors.append(error)
    }
}

@MainActor
private func withPortalDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("alcove-portal-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    do {
        try await body(directory)
    } catch {
        let bodyError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw PortalCoordinatorFixtureError.bodyAndCleanup(
                body: String(describing: bodyError),
                cleanup: String(describing: error)
            )
        }
        throw bodyError
    }
    try FileManager.default.removeItem(at: directory)
}

private enum PortalCoordinatorFixtureError: Error {
    case bodyAndCleanup(body: String, cleanup: String)
}
