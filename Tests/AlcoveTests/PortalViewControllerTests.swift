import AlcoveCore
import XCTest
@testable import Alcove

final class PortalViewControllerTests: XCTestCase {
    @MainActor
    func testPortalMaterialOwnsTheFullViewSurface() throws {
        let controller = PortalViewController(
            portal: try Portal(
                folderURL: URL(fileURLWithPath: "/tmp/portal"),
                frame: CGRect(x: 0, y: 0, width: 420, height: 360),
                display: testDisplay
            ),
            loadingCoordinator: FolderLoadingCoordinator()
        )

        controller.loadView()

        let material = try XCTUnwrap(controller.view as? PortalChromeMaterialView)
        XCTAssertNotNil(material.materialView)
        XCTAssertTrue(material.materialView?.subviews.isEmpty == false)
    }

    @MainActor
    func testFolderCapsulesAreVisibleOnTheFirstPortalWindowLayout() throws {
        var portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: CGRect(x: 0, y: 0, width: 500, height: 360),
            display: testDisplay
        )
        _ = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator()
        )
        let window = PortalWindow(
            contentRect: portal.frame,
            strategy: .developmentDefault,
            contentViewController: controller
        )

        window.contentView?.layoutSubtreeIfNeeded()

        let buttons = descendants(of: try XCTUnwrap(window.contentView))
            .compactMap { $0 as? PortalTabButton }
        XCTAssertEqual(buttons.count, 2)
        for button in buttons {
            let frame = button.convert(button.bounds, to: window.contentView)
            XCTAssertTrue(
                try XCTUnwrap(window.contentView).bounds.contains(frame),
                "Expected visible folder capsule, got \(frame)"
            )
        }
    }

    @MainActor
    func testMinimumContentSizeTracksTwoByTwoGridAndTabBar() {
        let metrics = GridMetrics(iconSize: .large)
        let actual = PortalViewController.minimumContentSize(for: .large)
        let expected = NSSize(
            width: metrics.minimumPortalSize.width,
            height: metrics.minimumPortalSize.height + PortalViewController.tabBarHeight
        )

        XCTAssertEqual(actual, expected)
    }

    @MainActor
    func testContentSizeSnapsToGridIncrementsAndMinimum() {
        let metrics = GridMetrics(iconSize: .medium)
        let minimum = PortalViewController.minimumContentSize(for: .medium)

        XCTAssertEqual(
            PortalViewController.snappedContentSize(
                NSSize(width: minimum.width - 20, height: minimum.height - 20),
                for: .medium
            ),
            minimum
        )
        XCTAssertEqual(
            PortalViewController.snappedContentSize(
                NSSize(
                    width: minimum.width + metrics.itemSize.width + metrics.horizontalSpacing + 3,
                    height: minimum.height + metrics.itemSize.height + metrics.verticalSpacing + 3
                ),
                for: .medium
            ),
            NSSize(
                width: minimum.width + metrics.itemSize.width + metrics.horizontalSpacing,
                height: minimum.height + metrics.itemSize.height + metrics.verticalSpacing
            )
        )
    }

    @MainActor
    func testReloadAppliesAcceptedFolderContents() async throws {
        let root = URL(fileURLWithPath: "/tmp/portal")
        let item = FileItem(
            url: root.appendingPathComponent("file.txt"),
            name: "file.txt",
            isDirectory: false,
            isHidden: false
        )
        let coordinator = FolderLoadingCoordinator(
            enumerator: FixedFolderEnumerator(root: root, items: [item])
        )
        let portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: coordinator
        )
        controller.loadView()

        await controller.reload()

        XCTAssertEqual(controller.presentationState, .items(1))
    }

    @MainActor
    func testReloadShowsEmptyState() async throws {
        let root = URL(fileURLWithPath: "/tmp/empty-portal")
        let coordinator = FolderLoadingCoordinator(
            enumerator: FixedFolderEnumerator(root: root, items: [])
        )
        let portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: coordinator
        )
        controller.loadView()

        await controller.reload()

        XCTAssertEqual(controller.presentationState, .message("This folder is empty"))
    }

    @MainActor
    func testMissingFolderOffersLocateAndDispatchesSelectedTabIdentity() async throws {
        let root = URL(fileURLWithPath: "/tmp/missing-portal")
        let metadata = FolderErrorMetadata(
            error: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        )
        let coordinator = FolderLoadingCoordinator(
            enumerator: FailingFolderEnumerator(
                error: .folderNotFound(url: root, metadata: metadata)
            )
        )
        let portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            display: testDisplay
        )
        let controller = PortalViewController(portal: portal, loadingCoordinator: coordinator)
        controller.loadView()
        var locatedTabID: FolderTabID?
        controller.onLocateFolderRequested = { locatedTabID = $0 }

        await controller.reload()

        XCTAssertEqual(
            controller.presentationState,
            .error(
                PortalErrorPresentation(
                    message: "Folder not found",
                    detail: root.path,
                    action: .locateFolder
                )
            )
        )
        XCTAssertEqual(controller.recoveryAction, .locateFolder)
        controller.performRecoveryAction()
        XCTAssertEqual(locatedTabID, portal.selectedTabID)
    }

    @MainActor
    func testErrorPresentationMapsRecoveryActionsAndPermissionGuidance() {
        let url = URL(fileURLWithPath: "/tmp/Documents")
        let permission = FolderErrorMetadata(
            error: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        )
        let read = FolderErrorMetadata(
            error: NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
        )

        let permissionPresentation = PortalViewController.errorPresentation(
            for: .permissionDenied(url: url, metadata: permission)
        )
        let readPresentation = PortalViewController.errorPresentation(
            for: .readFailed(url: url, metadata: read)
        )

        XCTAssertEqual(permissionPresentation.action, .retry)
        XCTAssertTrue(permissionPresentation.detail.contains("Privacy & Security"))
        XCTAssertEqual(readPresentation.action, .retry)
        XCTAssertEqual(readPresentation.detail, url.path)
    }

    @MainActor
    func testTabSwitchHidesOldGridBeforeAsyncObservationStarts() async throws {
        let root = URL(fileURLWithPath: "/tmp/first")
        let item = FileItem(
            url: root.appendingPathComponent("old.txt"),
            name: "old.txt",
            isDirectory: false,
            isHidden: false
        )
        var portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(
                enumerator: FixedFolderEnumerator(root: root, items: [item])
            )
        )
        controller.loadView()
        await controller.reload()
        XCTAssertEqual(controller.presentationState, .items(1))

        let secondID = try portal.appendTab(
            folderURL: URL(fileURLWithPath: "/tmp/second")
        )
        try portal.selectTab(secondID)

        controller.updatePortal(portal)

        XCTAssertEqual(controller.presentationState, .loading)
        controller.stopObservation()
    }

    @MainActor
    func testTabRuntimeStateIsConsumedOnceAndDoesNotRollbackLaterRefresh() async throws {
        let root = URL(fileURLWithPath: "/tmp/first")
        let items = [
            FileItem(url: root.appendingPathComponent("one"), name: "one", isDirectory: false, isHidden: false),
            FileItem(url: root.appendingPathComponent("two"), name: "two", isDirectory: false, isHidden: false),
        ]
        var portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let firstTabID = portal.selectedTabID
        let secondTabID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let grid = FileGridViewController()
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(
                enumerator: FixedFolderEnumerator(root: root, items: items)
            ),
            gridViewController: grid
        )
        controller.loadView()
        await controller.reload()
        grid.handleClick(index: 1, modifiers: [])

        try portal.selectTab(secondTabID)
        controller.updatePortal(portal)
        controller.stopObservation()
        await controller.reload()
        try portal.selectTab(firstTabID)
        controller.updatePortal(portal)
        controller.stopObservation()
        await controller.reload()
        XCTAssertEqual(grid.selectionState.selectedIDs, [items[1].id])

        grid.handleClick(index: 0, modifiers: [])
        portal.updateIconSize(.large)
        controller.updatePortal(portal)
        await controller.reload(showLoadingIndicator: false)

        XCTAssertEqual(grid.selectionState.selectedIDs, [items[0].id])
    }

    @MainActor
    func testRapidTabSwitchDoesNotSaveHiddenGridStateForPendingTab() async throws {
        let firstRoot = URL(fileURLWithPath: "/tmp/first")
        let secondRoot = URL(fileURLWithPath: "/tmp/second")
        let firstItem = FileItem(
            url: firstRoot.appendingPathComponent("first"),
            name: "first",
            isDirectory: false,
            isHidden: false
        )
        let secondItem = FileItem(
            url: secondRoot.appendingPathComponent("second"),
            name: "second",
            isDirectory: false,
            isHidden: false
        )
        var portal = try Portal(
            folderURL: firstRoot,
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let firstTabID = portal.selectedTabID
        let secondTabID = try portal.appendTab(folderURL: secondRoot)
        let grid = FileGridViewController()
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(
                enumerator: FolderMapEnumerator(
                    itemsByRoot: [firstRoot: [firstItem], secondRoot: [secondItem]]
                )
            ),
            gridViewController: grid
        )
        controller.loadView()
        await controller.reload()

        try portal.selectTab(secondTabID)
        controller.updatePortal(portal)
        controller.stopObservation()
        await controller.reload()
        grid.handleClick(index: 0, modifiers: [])

        try portal.selectTab(firstTabID)
        controller.updatePortal(portal)
        controller.stopObservation()
        await controller.reload()
        try portal.selectTab(secondTabID)
        controller.updatePortal(portal)
        try portal.selectTab(firstTabID)
        controller.updatePortal(portal)
        controller.stopObservation()
        await controller.reload()

        try portal.selectTab(secondTabID)
        controller.updatePortal(portal)
        controller.stopObservation()
        await controller.reload()

        XCTAssertEqual(grid.selectionState.selectedIDs, [secondItem.id])
    }

    @MainActor
    func testEmptyFolderConsumesOldTabSelectionBeforeSameNameReappears() async throws {
        let firstRoot = URL(fileURLWithPath: "/tmp/first")
        let secondRoot = URL(fileURLWithPath: "/tmp/second")
        let firstItem = FileItem(
            url: firstRoot.appendingPathComponent("same-name"),
            name: "same-name",
            isDirectory: false,
            isHidden: false
        )
        let enumerator = MutableFolderEnumerator(
            itemsByRoot: [firstRoot: [firstItem], secondRoot: []]
        )
        var portal = try Portal(
            folderURL: firstRoot,
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let firstTabID = portal.selectedTabID
        let secondTabID = try portal.appendTab(folderURL: secondRoot)
        let grid = FileGridViewController()
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(enumerator: enumerator),
            gridViewController: grid
        )
        controller.loadView()
        await controller.reload()
        grid.handleClick(index: 0, modifiers: [])

        try portal.selectTab(secondTabID)
        controller.updatePortal(portal)
        controller.stopObservation()
        await enumerator.setItems([], for: firstRoot)
        try portal.selectTab(firstTabID)
        controller.updatePortal(portal)
        controller.stopObservation()
        await controller.reload()
        XCTAssertEqual(controller.presentationState, .message("This folder is empty"))

        await enumerator.setItems([firstItem], for: firstRoot)
        await controller.reload(showLoadingIndicator: false)

        XCTAssertTrue(grid.selectionState.selectedIDs.isEmpty)
    }

    @MainActor
    func testNewTabForSameFolderDoesNotInheritPreviousTabSelection() async throws {
        let root = URL(fileURLWithPath: "/tmp/shared")
        let item = FileItem(
            url: root.appendingPathComponent("shared"),
            name: "shared",
            isDirectory: false,
            isHidden: false
        )
        var portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let grid = FileGridViewController()
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(
                enumerator: FixedFolderEnumerator(root: root, items: [item])
            ),
            gridViewController: grid
        )
        controller.loadView()
        await controller.reload()
        grid.handleClick(index: 0, modifiers: [])

        let secondTabID = try portal.appendTab(folderURL: root)
        try portal.selectTab(secondTabID)
        controller.updatePortal(portal)
        controller.stopObservation()
        await controller.reload()

        XCTAssertTrue(grid.selectionState.selectedIDs.isEmpty)
    }

    @MainActor
    func testBackgroundRefreshKeepsExistingGridVisible() async throws {
        let root = URL(fileURLWithPath: "/tmp/portal")
        let item = FileItem(
            url: root.appendingPathComponent("one"),
            name: "one",
            isDirectory: false,
            isHidden: false
        )
        let controller = PortalViewController(
            portal: try Portal(
                folderURL: root,
                frame: CGRect(x: 0, y: 0, width: 420, height: 360),
                display: testDisplay
            ),
            loadingCoordinator: FolderLoadingCoordinator(
                enumerator: DelayedFixedFolderEnumerator(root: root, items: [item])
            )
        )
        controller.loadView()
        await controller.reload()
        XCTAssertEqual(controller.presentationState, .items(1))

        let refresh = Task { await controller.reload(showLoadingIndicator: false) }
        await Task.yield()

        XCTAssertEqual(controller.presentationState, .items(1))
        await refresh.value
    }

    @MainActor
    func testRealFolderChangeRefreshesVisiblePortalGrid() async throws {
        try await withObservedPortalDirectory { root in
            let portal = try Portal(
                folderURL: root,
                frame: CGRect(x: 0, y: 0, width: 320, height: 240),
                display: testDisplay
            )
            let controller = PortalViewController(
                portal: portal,
                loadingCoordinator: FolderLoadingCoordinator()
            )
            controller.loadView()
            controller.viewDidAppear()
            defer { controller.stopObservation() }
            try await waitUntilPresentation(
                controller,
                equals: .message("This folder is empty")
            )

            try Data("visible".utf8).write(to: root.appendingPathComponent("visible.txt"))
            try await waitUntilPresentation(controller, equals: .items(1))
        }
    }

    @MainActor
    private func waitUntilPresentation(
        _ controller: PortalViewController,
        equals expected: PortalPresentationState
    ) async throws {
        for _ in 0..<150 {
            if controller.presentationState == expected { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(expected); got \(controller.presentationState)")
    }
}

@MainActor
private func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
}

@MainActor
private func withObservedPortalDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("alcove-portal-observation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    do {
        try await body(directory)
    } catch {
        let bodyError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw PortalViewObservationTestError.bodyAndCleanup(
                body: String(describing: bodyError),
                cleanup: String(describing: error)
            )
        }
        throw bodyError
    }
    try FileManager.default.removeItem(at: directory)
}

private enum PortalViewObservationTestError: Error {
    case bodyAndCleanup(body: String, cleanup: String)
}

private let testDisplay = DisplayDescriptor(
    identity: DisplayIdentity(rawValue: "test-display"),
    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
)

private struct FixedFolderEnumerator: FolderEnumerating {
    let root: URL
    let items: [FileItem]

    func enumerate(
        root: URL,
        showHidden: Bool,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        FolderEnumerationResult(
            root: self.root,
            generation: generation,
            items: items,
            itemDiagnostics: []
        )
    }
}

private struct FailingFolderEnumerator: FolderEnumerating {
    let error: FolderAccessError

    func enumerate(
        root: URL,
        showHidden: Bool,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        throw error
    }
}

private struct DelayedFixedFolderEnumerator: FolderEnumerating {
    let root: URL
    let items: [FileItem]

    func enumerate(
        root: URL,
        showHidden: Bool,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        try await Task.sleep(for: .milliseconds(50))
        return FolderEnumerationResult(
            root: self.root,
            generation: generation,
            items: items,
            itemDiagnostics: []
        )
    }
}

private struct FolderMapEnumerator: FolderEnumerating {
    let itemsByRoot: [URL: [FileItem]]

    func enumerate(
        root: URL,
        showHidden: Bool,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        FolderEnumerationResult(
            root: root,
            generation: generation,
            items: itemsByRoot[root] ?? [],
            itemDiagnostics: []
        )
    }
}

private actor MutableFolderEnumerator: FolderEnumerating {
    private var itemsByRoot: [URL: [FileItem]]

    init(itemsByRoot: [URL: [FileItem]]) {
        self.itemsByRoot = itemsByRoot
    }

    func setItems(_ items: [FileItem], for root: URL) {
        itemsByRoot[root] = items
    }

    func enumerate(
        root: URL,
        showHidden: Bool,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        FolderEnumerationResult(
            root: root,
            generation: generation,
            items: itemsByRoot[root] ?? [],
            itemDiagnostics: []
        )
    }
}
