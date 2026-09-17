import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

extension PortalCoordinatorTests {
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
            minimumGap: PortalAppearancePreferences.defaults.spacing.points
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

}
