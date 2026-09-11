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
        let portals = [
            try makePortal(path: "/tmp/first", x: 10),
            try makePortal(path: "/tmp/second", x: 400),
        ]
        let store = PortalStoreSpy(portals: portals)
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(store: store, windowFactory: factory)

        try await coordinator.restorePortals()

        XCTAssertEqual(coordinator.portalStates, portals)
        XCTAssertEqual(factory.createdPortalIDs, portals.map(\.id))
        XCTAssertEqual(factory.windows.map(\.presentCount), [1, 1])
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
            try await coordinator.restorePortals()

            try await coordinator.createPortal(for: folder, frame: frame)

            let saves = await store.savedSnapshots()
            XCTAssertEqual(saves.count, 1)
            XCTAssertEqual(saves[0], coordinator.portalStates)
            XCTAssertEqual(coordinator.portalStates.first?.frame, frame)
            XCTAssertEqual(factory.windows.first?.presentCount, 1)
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
        XCTAssertEqual(factory.windows[0].systemFrames.count, 2)
        XCTAssertNil(coordinator.displayError)
    }

    @MainActor
    func testTemporaryEvictionAndHomeReturnNeverOverwriteDurablePlacement() async throws {
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
        XCTAssertEqual(factory.windows[0].systemFrames.count, 3)
        XCTAssertEqual(
            factory.windows[0].systemFrames.last,
            try snappedPlacementFrame(portal.frame)
        )
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

        factory.windows[0].simulateUserPlacementCommit(
            CGRect(x: 180, y: 190, width: 380, height: 300)
        )
        await coordinator.waitForPersistenceForTesting()

        XCTAssertEqual(coordinator.portalStates[0].frame, portal.frame)
        XCTAssertEqual(
            factory.windows[0].systemFrames.last,
            try snappedPlacementFrame(portal.frame)
        )
        XCTAssertEqual(coordinator.persistenceError as? PortalStoreFixtureError, .rejected)
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
            PortalMenuEntry(id: portal.id, title: "selected", iconSize: .medium),
        ])
        coordinator.showPortal(portal.id)
        XCTAssertEqual(factory.windows[0].presentCount, 2)

        await coordinator.setIconSize(.large, for: portal.id)

        XCTAssertEqual(coordinator.portalStates[0].iconSize, .large)
        XCTAssertEqual(factory.windows[0].updatedPortals.last?.iconSize, .large)
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves.last?.first?.iconSize, .large)
        XCTAssertEqual(menus.last?.first?.iconSize, .large)

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
        let coordinator = PortalCoordinator(store: store, windowFactory: factory)
        try await coordinator.restorePortals()

        await coordinator.setIconSize(.large, for: portal.id)
        XCTAssertEqual(coordinator.portalStates, [portal])
        XCTAssertEqual(factory.windows[0].updateCount, 0)
        XCTAssertEqual(coordinator.persistenceError as? PortalStoreFixtureError, .rejected)

        await coordinator.removePortal(portal.id)
        XCTAssertEqual(coordinator.portalStates, [portal])
        XCTAssertEqual(factory.windows[0].closeCount, 0)
        XCTAssertEqual(coordinator.persistenceError as? PortalStoreFixtureError, .rejected)
    }

    @MainActor
    func testLocatingFolderPreservesTabIdentityAndPersistsBeforeWindowUpdate() async throws {
        try await withPortalDirectory { replacement in
            let portal = try makePortal(path: "/tmp/missing", x: 10)
            let store = PortalStoreSpy(portals: [portal])
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(
                store: store,
                windowFactory: factory,
                tabFolderPicker: TabFolderPickerStub(folders: [replacement])
            )
            try await coordinator.restorePortals()

            factory.windows[0].onLocateFolder?(portal.selectedTabID)
            await coordinator.waitForTabMutationForTesting()

            let updated = coordinator.portalStates[0]
            XCTAssertEqual(updated.tabs[0].id, portal.selectedTabID)
            XCTAssertEqual(updated.tabs[0].folderURL, replacement.standardizedFileURL)
            XCTAssertEqual(factory.windows[0].updatedPortals.last, updated)
            let saves = await store.savedSnapshots()
            XCTAssertEqual(saves.last, [updated])
        }
    }

    @MainActor
    func testLocateSaveFailureDoesNotRemapLivePortal() async throws {
        try await withPortalDirectory { replacement in
            let portal = try makePortal(path: "/tmp/missing", x: 10)
            let store = PortalStoreSpy(portals: [portal], saveError: .rejected)
            let factory = PortalWindowFactorySpy()
            let errors = CoordinatorErrorPresenterSpy()
            let coordinator = PortalCoordinator(
                store: store,
                windowFactory: factory,
                tabFolderPicker: TabFolderPickerStub(folders: [replacement]),
                errorPresenter: errors
            )
            try await coordinator.restorePortals()

            factory.windows[0].onLocateFolder?(portal.selectedTabID)
            await coordinator.waitForTabMutationForTesting()

            XCTAssertEqual(coordinator.portalStates, [portal])
            XCTAssertEqual(factory.windows[0].updateCount, 0)
            XCTAssertEqual(errors.errors.count, 1)
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

        await cancelCoordinator.closeTab(portal.selectedTabID, in: portal.id)
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

        await confirmCoordinator.closeTab(portal.selectedTabID, in: portal.id)
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
        if let saveError {
            throw saveError
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
}

@MainActor
private final class PortalWindowFactorySpy: PortalWindowBuilding {
    private(set) var createdPortalIDs: [PortalID] = []
    private(set) var windows: [PortalWindowPresenterSpy] = []

    func makeWindow(for portal: Portal) -> any PortalWindowPresenting {
        createdPortalIDs.append(portal.id)
        let window = PortalWindowPresenterSpy()
        windows.append(window)
        return window
    }
}

@MainActor
private final class PortalWindowPresenterSpy: PortalWindowPresenting {
    var onUserPlacementCommit: ((NSRect) -> Void)?
    var onUserPlacementInteractionCancelled: (() -> Void)?
    var onSelectTab: ((FolderTabID) -> Void)?
    var onAddTab: (() -> Void)?
    var onCloseTab: ((FolderTabID) -> Void)?
    var onLocateFolder: ((FolderTabID) -> Void)?
    private(set) var presentCount = 0
    private(set) var updateCount = 0
    private(set) var closeCount = 0
    private(set) var updatedPortals: [Portal] = []
    private(set) var systemFrames: [NSRect] = []
    var acceptsSystemPlacement = true

    func present() {
        presentCount += 1
    }

    func updatePortal(_ portal: Portal) {
        updateCount += 1
        updatedPortals.append(portal)
    }

    func applySystemPlacement(frame: NSRect) -> Bool {
        guard acceptsSystemPlacement else { return false }
        systemFrames.append(frame)
        return true
    }

    func close() {
        closeCount += 1
    }

    func simulateUserPlacementCommit(_ frame: NSRect) {
        onUserPlacementCommit?(frame)
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
