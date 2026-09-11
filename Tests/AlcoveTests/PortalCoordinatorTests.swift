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
    func testCreatePersistsBeforePresenting() async throws {
        try await withPortalDirectory { folder in
            let store = PortalStoreSpy(portals: [])
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(store: store, windowFactory: factory)
            let frame = NSRect(x: 30, y: 40, width: 320, height: 240)

            try await coordinator.createPortal(for: folder, frame: frame)

            let saves = await store.savedSnapshots()
            XCTAssertEqual(saves.count, 1)
            XCTAssertEqual(saves[0], coordinator.portalStates)
            XCTAssertEqual(coordinator.portalStates.first?.frame, frame)
            XCTAssertEqual(factory.windows.first?.presentCount, 1)
        }
    }

    @MainActor
    func testWindowFrameChangesPersistUpdatedState() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(store: store, windowFactory: factory)
        try await coordinator.restorePortals()
        let updatedFrame = NSRect(x: 90, y: 100, width: 480, height: 360)

        factory.windows[0].simulateFrameChange(updatedFrame)
        await coordinator.waitForPersistenceForTesting()

        XCTAssertEqual(coordinator.portalStates[0].frame, updatedFrame)
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves.last?.first?.frame, updatedFrame)
        XCTAssertNil(coordinator.persistenceError)
    }

    @MainActor
    func testSaveFailureDoesNotCreatePartialPortal() async throws {
        try await withPortalDirectory { folder in
            let store = PortalStoreSpy(portals: [], saveError: .rejected)
            let factory = PortalWindowFactorySpy()
            let coordinator = PortalCoordinator(store: store, windowFactory: factory)

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
            frame: CGRect(x: x, y: 20, width: 320, height: 240)
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
    var onFrameChange: ((NSRect) -> Void)?
    var onSelectTab: ((FolderTabID) -> Void)?
    var onAddTab: (() -> Void)?
    var onCloseTab: ((FolderTabID) -> Void)?
    private(set) var presentCount = 0
    private(set) var updateCount = 0
    private(set) var closeCount = 0
    private(set) var updatedPortals: [Portal] = []

    func present() {
        presentCount += 1
    }

    func updatePortal(_ portal: Portal) {
        updateCount += 1
        updatedPortals.append(portal)
    }

    func close() {
        closeCount += 1
    }

    func simulateFrameChange(_ frame: NSRect) {
        onFrameChange?(frame)
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
