import AlcoveCore
import XCTest
@testable import Alcove

extension PortalViewControllerTests {
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
        let grid = FileGridViewController()
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: coordinator,
            gridViewController: grid
        )
        controller.loadView()

        await controller.reload()

        XCTAssertEqual(
            controller.presentationState,
            .message(NSLocalizedString("portal.empty", comment: ""))
        )
        XCTAssertFalse(grid.view.isHidden)
        XCTAssertEqual(grid.dropDestinationURL, root)
    }

    @MainActor
    func testChangingSortOrderReloadsTheCurrentFolderWithTheNewOrder() async throws {
        let root = URL(fileURLWithPath: "/tmp/sorted-portal")
        let enumerator = MutableFolderEnumerator(itemsByRoot: [root: []])
        var portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(enumerator: enumerator)
        )
        controller.loadView()
        await controller.reload()

        portal.updateSortOrder(.creationDate)
        controller.updatePortal(portal)
        for _ in 0..<100 {
            if await enumerator.requestedSortOrders().count >= 2 { break }
            await Task.yield()
        }

        let requestedSortOrders = await enumerator.requestedSortOrders()
        XCTAssertEqual(requestedSortOrders, [.name, .creationDate])
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
                    message: NSLocalizedString("portal.error.folder_not_found", comment: ""),
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
        XCTAssertTrue(permissionPresentation.detail.contains(url.lastPathComponent))
        XCTAssertEqual(readPresentation.action, .retry)
        XCTAssertEqual(readPresentation.detail, url.path)
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
                equals: .message(NSLocalizedString("portal.empty", comment: ""))
            )

            try Data("visible".utf8).write(to: root.appendingPathComponent("visible.txt"))
            try await waitUntilPresentation(controller, equals: .items(1))
        }
    }

}
