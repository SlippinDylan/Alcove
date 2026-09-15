import AlcoveCore
import XCTest
@testable import Alcove

final class PortalViewControllerTests: XCTestCase {
    @MainActor
    func testEmptyPortalShowsFolderChoiceInsideThePortal() throws {
        let controller = PortalViewController(
            portal: try Portal(
                frame: CGRect(x: 0, y: 0, width: 344, height: 180),
                display: testDisplay
            ),
            loadingCoordinator: FolderLoadingCoordinator()
        )
        var addRequestCount = 0
        controller.onAddTab = { addRequestCount += 1 }

        controller.loadView()

        XCTAssertEqual(controller.presentationState, .emptyPortal)
        let chooseButton = try XCTUnwrap(
            descendants(of: controller.view)
                .compactMap { $0 as? NSButton }
                .first {
                    $0.accessibilityLabel()
                        == NSLocalizedString("portal.choose.help", comment: "")
                }
        )
        XCTAssertFalse(chooseButton.isHidden)
        let pathBar = try XCTUnwrap(
            descendants(of: controller.view).compactMap { $0 as? FolderPathBarView }.first
        )
        XCTAssertNil(pathBar.displayedPath)
        chooseButton.performClick(nil)
        XCTAssertEqual(addRequestCount, 1)
    }

    @MainActor
    func testPortalUsesOneBackgroundMaterialAndTwoSectionSeparators() throws {
        let controller = PortalViewController(
            portal: try Portal(
                folderURL: URL(fileURLWithPath: "/tmp/portal"),
                frame: CGRect(x: 0, y: 0, width: 420, height: 360),
                display: testDisplay
            ),
            loadingCoordinator: FolderLoadingCoordinator()
        )

        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 420, height: 360)
        controller.view.layoutSubtreeIfNeeded()

        let materials = descendants(of: controller.view)
            .compactMap { $0 as? PortalChromeMaterialView }
        let surface = try XCTUnwrap(materials.first)
        XCTAssertNotNil(surface.materialView)
        XCTAssertEqual(materials.count, 1)
        XCTAssertEqual(controller.topSeparator.boxType, .separator)
        XCTAssertEqual(controller.bottomSeparator.boxType, .separator)
        XCTAssertEqual(controller.topSeparator.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(controller.bottomSeparator.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(
            controller.topSeparator.frame.width,
            controller.view.bounds.width,
            accuracy: 0.5
        )
        XCTAssertEqual(
            controller.bottomSeparator.frame.width,
            controller.view.bounds.width,
            accuracy: 0.5
        )
    }

    @MainActor
    func testManagementMenuForwardsTheNextPersistentPinnedState() throws {
        var portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator()
        )
        var requestedStates: [Bool] = []
        controller.onSetPinned = { requestedStates.append($0) }
        controller.loadView()
        let tabBar = try XCTUnwrap(
            descendants(of: controller.view).compactMap { $0 as? TabBarView }.first
        )

        tabBar.makeManagementMenu().performActionForItem(at: 0)
        portal.updatePinned(true)
        controller.updatePortal(portal)
        let pinnedMenu = tabBar.makeManagementMenu()
        pinnedMenu.performActionForItem(at: 0)

        XCTAssertEqual(requestedStates, [true, false])
        XCTAssertEqual(
            pinnedMenu.items[0].title,
            NSLocalizedString("portal.pin.unpin", comment: "")
        )
    }

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
    func testGlobalTransparencyUpdateOnlyChangesStaticSurfaceWithoutInvalidatingSelection() async throws {
        let root = URL(fileURLWithPath: "/tmp/portal")
        let item = FileItem(
            url: root.appendingPathComponent("one"),
            name: "one",
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
        var invalidationCount = 0
        controller.onSelectionInvalidated = { invalidationCount += 1 }
        controller.loadView()
        await controller.reload()
        let surface = try XCTUnwrap(
            descendants(of: controller.view)
                .compactMap { $0 as? PortalChromeMaterialView }
                .first
        )

        portal.updateBackgroundStyle(.lowTransparency)
        controller.updatePortal(portal)

        XCTAssertEqual(surface.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(surface.materialPath, .translucent)
        XCTAssertEqual(
            try XCTUnwrap(surface.materialView?.layer?.backgroundColor).alpha,
            0.82,
            accuracy: 0.001
        )
        XCTAssertEqual(controller.presentationState, .items(1))
        XCTAssertEqual(invalidationCount, 0)
    }

    @MainActor
    func testPortalSettingsDoNotExposeGlobalBackgroundControl() throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator()
        )
        controller.loadView()
        let tabBar = try XCTUnwrap(
            descendants(of: controller.view).compactMap { $0 as? TabBarView }.first
        )
        tabBar.showSettingsWindow()
        let settingsController = try XCTUnwrap(tabBar.settingsWindowController)
        let settingsViewController = settingsController.settingsViewController
        settingsController.selectCategory(.style)
        let settingsRoot = settingsViewController.view
        settingsController.close()
        XCTAssertFalse(descendants(of: settingsRoot).contains {
            $0.identifier?.rawValue == "portal-settings.background"
        })
    }

    @MainActor
    func testSelectedFolderCapsuleIsVisibleOnTheFirstPortalWindowLayout() throws {
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

        let contentView = try XCTUnwrap(window.contentView)
        let buttons = descendants(of: contentView)
            .compactMap { $0 as? PortalTabButton }
        XCTAssertEqual(buttons.count, 2)
        XCTAssertTrue(buttons.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 })
        let selectedButton = try XCTUnwrap(buttons.first { $0.isTabSelected })
        let selectedFrame = selectedButton.convert(selectedButton.bounds, to: contentView)
        XCTAssertTrue(
            contentView.bounds.contains(selectedFrame),
            "Expected selected folder capsule to be visible, got \(selectedFrame)"
        )
    }

    @MainActor
    func testMinimumContentSizeTracksGridAndChromeRows() {
        let metrics = GridMetrics(iconSize: .large)
        let actual = PortalViewController.minimumContentSize(for: .large)
        let expected = NSSize(
            width: metrics.minimumPortalSize.width,
            height: metrics.minimumPortalSize.height + PortalViewController.chromeHeight
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

@MainActor
private final class FolderPathOpenerSpy: FolderPathOpening {
    private(set) var finderURLs: [URL] = []
    private(set) var terminalURLs: [URL] = []

    func openInFinder(_ url: URL) -> Bool {
        finderURLs.append(url)
        return true
    }

    func openInTerminal(
        _ url: URL,
        completion: @escaping @MainActor @Sendable (FolderPathOpenError?) -> Void
    ) {
        terminalURLs.append(url)
        completion(nil)
    }
}

@MainActor
private final class FolderPathFailurePresenterSpy: FolderPathOpenFailurePresenting {
    private(set) var failures: [(FolderPathOpenError, URL)] = []

    func present(_ error: FolderPathOpenError, for url: URL) {
        failures.append((error, url))
    }
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
        sortOrder: PortalSortOrder,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        return FolderEnumerationResult(
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
        sortOrder: PortalSortOrder,
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
        sortOrder: PortalSortOrder,
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
        sortOrder: PortalSortOrder,
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
    private var sortOrders: [PortalSortOrder] = []

    init(itemsByRoot: [URL: [FileItem]]) {
        self.itemsByRoot = itemsByRoot
    }

    func setItems(_ items: [FileItem], for root: URL) {
        itemsByRoot[root] = items
    }

    func requestedSortOrders() -> [PortalSortOrder] {
        sortOrders
    }

    func enumerate(
        root: URL,
        showHidden: Bool,
        sortOrder: PortalSortOrder,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        sortOrders.append(sortOrder)
        return FolderEnumerationResult(
            root: root,
            generation: generation,
            items: itemsByRoot[root] ?? [],
            itemDiagnostics: []
        )
    }
}
