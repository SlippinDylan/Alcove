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
        XCTAssertTrue(coordinator.portalStates.allSatisfy { $0.backgroundStyle == .lowTransparency })
        XCTAssertEqual(factory.createdPortalIDs, portals.map(\.id))
        XCTAssertEqual(factory.createdPortals.map(\.backgroundStyle), [
            .lowTransparency,
            .lowTransparency,
        ])
        XCTAssertEqual(factory.windows.map(\.presentCount), [1, 1])
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
        XCTAssertEqual(factory.windows[1].updatedAppearances.last?.spacing, .large)
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
    func testLayoutImportValidatesExistingFoldersBeforeReplacingRuntimeState() async throws {
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
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            try await coordinator.replaceLayout(
                with: try makeLayoutBackup(
                    portalID: PortalID(rawValue: UUID()),
                    folderURLs: [fileURL]
                )
            )
            XCTFail("An imported non-folder path must fail validation")
        } catch let error as FolderAccessError {
            guard case .notDirectory = error else {
                return XCTFail("Expected notDirectory, got \(error)")
            }
        }

        XCTAssertEqual(coordinator.portalStates, [existing])
        XCTAssertEqual(factory.windows.count, 1)
        XCTAssertEqual(factory.windows[0].closeCount, 0)
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
        gridCapacity: GridCapacity = .minimum,
        folderURLs: [URL] = [
            URL(fileURLWithPath: "/missing/one"),
            URL(fileURLWithPath: "/missing/two"),
        ]
    ) throws -> AlcoveLayoutBackup {
        AlcoveLayoutBackup(
            global: AlcoveLayoutBackupGlobal(
                iconSize: .large,
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
                    folderURLs: folderURLs,
                    selectedFolderIndex: folderURLs.isEmpty ? nil : folderURLs.count - 1
                ),
            ]
        )
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

    func makePortal(path: String, x: CGFloat) throws -> Portal {
        try Portal(
            folderURL: URL(fileURLWithPath: path),
            frame: CGRect(x: x, y: 20, width: 320, height: 240),
            display: coordinatorTestDisplay
        )
    }

    func snappedPlacementFrame(_ frame: CGRect) throws -> CGRect {
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

actor PortalStoreSpy: PortalStoring {
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

actor SuspendingPortalStore: PortalStoring {
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

enum PortalStoreFixtureError: Error, Equatable {
    case rejected
    case cancelled
}

@MainActor
final class PortalWindowFactorySpy: PortalWindowBuilding {
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
final class PortalWindowPresenterSpy: PortalWindowPresenting {
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

let coordinatorTestDisplay = DisplayDescriptor(
    identity: DisplayIdentity(rawValue: "test-display"),
    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
)

@MainActor
final class DisplaySnapshotResultBox {
    var result: Result<DisplaySnapshot, DisplaySnapshotError>

    init(_ result: Result<DisplaySnapshot, DisplaySnapshotError>) {
        self.result = result
    }
}

@MainActor
final class TabFolderPickerStub: FolderPicking {
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
final class SuspendedTabFolderPicker: FolderPicking {
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
final class LastTabConfirmerStub: LastTabRemovalConfirming {
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
final class CoordinatorErrorPresenterSpy: PortalCreationErrorPresenting {
    private(set) var errors: [Error] = []

    func present(_ error: Error) {
        errors.append(error)
    }
}

@MainActor
final class PersistenceErrorPresenterSpy: PortalPersistenceErrorPresenting {
    private(set) var errors: [Error] = []

    func present(_ error: Error) {
        errors.append(error)
    }
}

@MainActor
func withPortalDirectory(
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

enum PortalCoordinatorFixtureError: Error {
    case bodyAndCleanup(body: String, cleanup: String)
}
