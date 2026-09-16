import AlcoveCore
import XCTest
@testable import Alcove

extension PortalViewControllerTests {
    @MainActor
    func testPathBarTracksTheSelectedFolderAndCopiesDisplayedPath() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let firstURL = home.appendingPathComponent("Repo/First")
        let secondURL = home.appendingPathComponent("Repo/Second")
        var portal = try Portal(
            folderURL: firstURL,
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let secondID = try portal.appendTab(folderURL: secondURL)
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator()
        )
        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 420, height: 360)
        controller.view.layoutSubtreeIfNeeded()
        let pathBar = try XCTUnwrap(
            descendants(of: controller.view).compactMap { $0 as? FolderPathBarView }.first
        )
        XCTAssertEqual(pathBar.displayedPath, "~/Repo/First")
        XCTAssertEqual(pathBar.contentView.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(
            pathBar.contentView.frame.width,
            pathBar.bounds.width,
            accuracy: 0.5
        )

        try portal.selectTab(secondID)
        controller.updatePortal(portal)
        pathBar.copyButton.performClick(nil)

        XCTAssertEqual(pathBar.displayedPath, "~/Repo/Second")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), secondURL.path)
    }

    @MainActor
    func testFolderNavigationUsesRuntimeHistoryAndRestoresRootSelection() async throws {
        let root = URL(fileURLWithPath: "/tmp/root")
        let child = root.appendingPathComponent("Child", isDirectory: true)
        let folder = FileItem(
            url: child,
            name: "Child",
            isDirectory: true,
            isHidden: false
        )
        let childFile = FileItem(
            url: child.appendingPathComponent("file.txt"),
            name: "file.txt",
            isDirectory: false,
            isHidden: false
        )
        let grid = FileGridViewController()
        let controller = PortalViewController(
            portal: try Portal(
                folderURL: root,
                frame: CGRect(x: 0, y: 0, width: 420, height: 360),
                display: testDisplay
            ),
            loadingCoordinator: FolderLoadingCoordinator(
                enumerator: FolderMapEnumerator(itemsByRoot: [root: [folder], child: [childFile]])
            ),
            gridViewController: grid
        )
        controller.loadView()
        await controller.reload()
        XCTAssertEqual(grid.dropDestinationURL, root)

        grid.handleClick(index: 0, modifiers: [], clickCount: 2)
        XCTAssertEqual(grid.dropDestinationURL, child)
        controller.stopObservation()
        await controller.reload()

        let pathBar = try XCTUnwrap(
            descendants(of: controller.view).compactMap { $0 as? FolderPathBarView }.first
        )
        let tabBar = try XCTUnwrap(
            descendants(of: controller.view).compactMap { $0 as? TabBarView }.first
        )
        XCTAssertEqual(pathBar.displayedPath, "/tmp/root/Child")
        XCTAssertFalse(tabBar.backButton.isHidden)
        XCTAssertEqual(grid.item(at: 0), childFile)

        tabBar.backButton.performClick(nil)
        XCTAssertEqual(grid.dropDestinationURL, root)
        controller.stopObservation()
        await controller.reload()

        XCTAssertEqual(pathBar.displayedPath, "/tmp/root")
        XCTAssertTrue(tabBar.backButton.isHidden)
        XCTAssertEqual(grid.selectionState.selectedIDs, [folder.id])
    }

    @MainActor
    func testPathActionsUseCurrentAbsoluteFolderURL() {
        let opener = FolderPathOpenerSpy()
        let failures = FolderPathFailurePresenterSpy()
        let pathBar = FolderPathBarView(pathOpener: opener, failurePresenter: failures)
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Repo")
        pathBar.update(folderURL: url)

        pathBar.openInFinder()
        pathBar.openInTerminal()
        pathBar.copyButton.performClick(nil)

        XCTAssertEqual(opener.finderURLs, [url])
        XCTAssertEqual(opener.terminalURLs, [url])
        XCTAssertTrue(failures.failures.isEmpty)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), url.path)
    }

    @MainActor
    func testPathBarUsesPlainContentWithoutACapsuleOrNestedMaterial() {
        let pathBar = FolderPathBarView(frame: NSRect(x: 0, y: 0, width: 420, height: 38))
        pathBar.update(folderURL: URL(fileURLWithPath: "/Users/example/Folder"))
        pathBar.layoutSubtreeIfNeeded()

        XCTAssertFalse(pathBar.contentView is NSGlassEffectView)
        XCTAssertNil(pathBar.contentView.layer)
        XCTAssertNil(pathBar.contentView.layer?.backgroundColor)
        let terminalFrame = pathBar.terminalButton.convert(
            pathBar.terminalButton.bounds,
            to: pathBar
        )
        let copyFrame = pathBar.copyButton.convert(pathBar.copyButton.bounds, to: pathBar)
        XCTAssertGreaterThan(pathBar.actionSpacer.frame.width, 0)
        XCTAssertLessThan(terminalFrame.maxX, copyFrame.minX)
        XCTAssertEqual(copyFrame.maxX, pathBar.bounds.maxX - 12, accuracy: 0.5)
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
        let firstTabID = try XCTUnwrap(portal.selectedTabID)
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
        let firstTabID = try XCTUnwrap(portal.selectedTabID)
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
        let firstTabID = try XCTUnwrap(portal.selectedTabID)
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
        XCTAssertEqual(
            controller.presentationState,
            .message(NSLocalizedString("portal.empty", comment: ""))
        )

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

}
