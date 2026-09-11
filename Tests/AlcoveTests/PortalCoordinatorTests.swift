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
    private(set) var presentCount = 0

    func present() {
        presentCount += 1
    }

    func simulateFrameChange(_ frame: NSRect) {
        onFrameChange?(frame)
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
