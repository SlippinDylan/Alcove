import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

extension PortalCoordinatorTests {
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

        await coordinator.removePortal(portal.id)
        XCTAssertEqual(coordinator.portalStates, [portal])
        XCTAssertEqual(factory.windows[0].closeCount, 0)
        XCTAssertEqual(coordinator.persistenceError as? PortalStoreFixtureError, .rejected)
        XCTAssertEqual(persistenceErrors.errors.count, 1)
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
            XCTAssertEqual(updated.backgroundStyle, .lowTransparency)
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

}
