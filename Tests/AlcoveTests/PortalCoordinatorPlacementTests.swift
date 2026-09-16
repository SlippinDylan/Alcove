import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

extension PortalCoordinatorTests {
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

}
