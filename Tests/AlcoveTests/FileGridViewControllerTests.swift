import AlcoveCore
import AppKit
import Carbon
import XCTest
@testable import Alcove

final class FileGridViewControllerTests: XCTestCase {
    @MainActor
    func testGridRetainsOrderedDomainItems() {
        let controller = FileGridViewController()
        controller.loadView()
        let items = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/Folder"),
                name: "Folder",
                isDirectory: true,
                isHidden: false
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/file.txt"),
                name: "file.txt",
                isDirectory: false,
                isHidden: false
            ),
        ]

        controller.setItems(items)

        XCTAssertEqual(controller.itemCount, 2)
        XCTAssertEqual(controller.item(at: 0), items[0])
        XCTAssertEqual(controller.item(at: 1), items[1])
        let scrollView = controller.view as? NSScrollView
        XCTAssertNotNil(scrollView)
        XCTAssertEqual(scrollView?.scrollerStyle, .overlay)
    }

    @MainActor
    func testFinderStyleClickAndKeyboardSelection() {
        let controller = FileGridViewController()
        controller.loadView()
        let items = makeItems(count: 8)
        controller.setItems(items)

        controller.handleClick(index: 1, modifiers: [])
        XCTAssertEqual(controller.selectionState.selectedIDs, [items[1].id])

        controller.handleClick(index: 3, modifiers: .command)
        XCTAssertEqual(controller.selectionState.selectedIDs, [items[1].id, items[3].id])

        controller.handleClick(index: 6, modifiers: .shift)
        XCTAssertEqual(
            controller.selectionState.selectedIDs,
            Set(items[3...6].map(\.id))
        )

        controller.handleKeyCommand(.selectAll)
        XCTAssertEqual(controller.selectionState.selectedIDs, Set(items.map(\.id)))

        controller.handleClick(index: 0, modifiers: [])
        controller.handleKeyCommand(.moveRight(extending: false))
        XCTAssertEqual(controller.selectionState.selectedIDs, [items[1].id])
        XCTAssertEqual(controller.lastKeyboardScrollPosition, .nearestHorizontalEdge)
        controller.handleKeyCommand(.moveDown(extending: true))
        let columnCount = GridCapacity.minimum.columns
        XCTAssertTrue(controller.selectionState.selectedIDs.contains(items[1 + columnCount].id))
        XCTAssertEqual(controller.lastKeyboardScrollPosition, .nearestVerticalEdge)

        let stateBeforeReturn = controller.selectionState.selectedIDs
        controller.handleKeyCommand(.noOperation)
        XCTAssertEqual(controller.selectionState.selectedIDs, stateBeforeReturn)
    }

    @MainActor
    func testDoubleClickAndOpenSelectionUseWorkspaceBoundary() {
        let opener = WorkspaceOpenerSpy(failingNames: ["file-2"])
        let failurePresenter = WorkspaceOpenFailurePresenterSpy()
        let controller = FileGridViewController(
            workspaceOpener: opener,
            openFailurePresenter: failurePresenter
        )
        controller.loadView()
        let items = makeItems(count: 3)
        controller.setItems(items)

        controller.handleClick(index: 0, modifiers: [], clickCount: 2)
        XCTAssertEqual(opener.openedURLs, [items[0].url])

        controller.handleKeyCommand(.selectAll)
        controller.handleKeyCommand(.openSelection)
        XCTAssertEqual(
            opener.openedURLs,
            [items[0].url, items[0].url, items[1].url, items[2].url]
        )
        XCTAssertEqual(controller.failedOpenURLs, [items[2].url])
        XCTAssertEqual(failurePresenter.failedURLs, [items[2].url])
    }

    @MainActor
    func testOnlyOrdinaryDirectoriesNavigateInsideThePanel() {
        let opener = WorkspaceOpenerSpy()
        let controller = FileGridViewController(workspaceOpener: opener)
        controller.loadView()
        let folder = FileItem(
            url: URL(fileURLWithPath: "/tmp/Folder"),
            name: "Folder",
            isDirectory: true,
            isHidden: false
        )
        let package = FileItem(
            url: URL(fileURLWithPath: "/tmp/App.app"),
            name: "App.app",
            isDirectory: true,
            isPackage: true,
            isHidden: false
        )
        let symlink = FileItem(
            url: URL(fileURLWithPath: "/tmp/Link"),
            name: "Link",
            isDirectory: true,
            isSymbolicLink: true,
            isHidden: false
        )
        var navigated: [URL] = []
        controller.onNavigateDirectory = { navigated.append($0.url) }
        controller.setItems([folder, package, symlink])

        controller.handleClick(index: 0, modifiers: [], clickCount: 2)
        controller.handleClick(index: 1, modifiers: [], clickCount: 2)
        controller.handleClick(index: 2, modifiers: [], clickCount: 2)

        XCTAssertEqual(navigated, [folder.url])
        XCTAssertEqual(opener.openedURLs, [package.url, symlink.url])
    }

    @MainActor
    func testRuntimeSelectionCanBeCapturedAndRestoredForATab() {
        let items = makeItems(count: 4)
        let firstController = FileGridViewController()
        firstController.loadView()
        firstController.setItems(items)
        firstController.handleClick(index: 1, modifiers: [])
        firstController.handleClick(index: 3, modifiers: .command)
        let state = firstController.captureRuntimeState()

        let restoredController = FileGridViewController()
        restoredController.loadView()
        restoredController.setItems(items)
        restoredController.restoreRuntimeState(state)

        XCTAssertEqual(restoredController.selectionState, state.selection)
    }

    @MainActor
    func testQuickLookRequestUsesSelectedItemsInGridOrderAndIgnoresEmptySelection() {
        let items = makeItems(count: 3)
        let controller = FileGridViewController()
        controller.loadView()
        controller.setItems(items)
        var requests: [[URL]] = []
        controller.onQuickLookRequested = { requests.append($0) }

        controller.handleKeyCommand(.toggleQuickLook)
        XCTAssertTrue(requests.isEmpty)

        controller.handleClick(index: 2, modifiers: [])
        controller.handleClick(index: 0, modifiers: .command)
        controller.handleKeyCommand(.toggleQuickLook)

        XCTAssertEqual(requests, [[items[0].url, items[2].url]])
    }

    @MainActor
    func testKeyCodesMapToFinderCommands() {
        XCTAssertEqual(FileCollectionView.command(keyCode: 0, modifiers: .command), .selectAll)
        XCTAssertEqual(FileCollectionView.command(keyCode: 31, modifiers: .command), .openSelection)
        XCTAssertEqual(FileCollectionView.command(keyCode: 125, modifiers: .command), .openSelection)
        XCTAssertEqual(FileCollectionView.command(keyCode: 123, modifiers: .shift), .moveLeft(extending: true))
        XCTAssertEqual(FileCollectionView.command(keyCode: 36, modifiers: []), .renameSelection)
        XCTAssertEqual(FileCollectionView.command(keyCode: 49, modifiers: []), .toggleQuickLook)
        XCTAssertEqual(FileCollectionView.command(keyCode: 51, modifiers: .command), .trashSelection)
        XCTAssertEqual(FileCollectionView.command(keyCode: 117, modifiers: .command), .trashSelection)
        XCTAssertNil(FileCollectionView.command(keyCode: 51, modifiers: []))
    }

    @MainActor
    func testMarqueeSelectionUsesTheExistingSelectionModel() throws {
        let controller = FileGridViewController()
        controller.loadView()
        let items = makeItems(count: 4)
        controller.setItems(items)
        controller.handleClick(index: 0, modifiers: [])
        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        let collectionView = try XCTUnwrap(scrollView.documentView as? FileCollectionView)

        collectionView.onMarqueeSelection?([1, 3])

        XCTAssertEqual(controller.selectionState.selectedIDs, [items[1].id, items[3].id])
        XCTAssertEqual(collectionView.selectionIndexPaths, [
            IndexPath(item: 1, section: 0),
            IndexPath(item: 3, section: 0),
        ])
    }

    @MainActor
    func testCollectionViewPublishesFileURLsForNativeDragOut() throws {
        let controller = FileGridViewController()
        controller.loadView()
        let item = makeItems(count: 1)[0]
        controller.setItems([item])
        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        let collectionView = try XCTUnwrap(scrollView.documentView as? NSCollectionView)

        let writer = try XCTUnwrap(controller.collectionView(
            collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        ) as? NSURL)

        XCTAssertEqual(writer as URL, item.url)
    }

    @MainActor
    func testNativeItemInteractionKeepsDraggedMultiSelectionAndSynchronizesCommandToggle() throws {
        let controller = FileGridViewController()
        controller.loadView()
        let items = makeItems(count: 3)
        controller.setItems(items)
        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        let collectionView = try XCTUnwrap(scrollView.documentView as? FileCollectionView)

        collectionView.onNativeItemInteraction?([0, 2], 2, [], 1)

        XCTAssertEqual(controller.selectionState.selectedIDs, [items[0].id, items[2].id])
        XCTAssertEqual(controller.selectionState.anchorID, items[2].id)
        XCTAssertEqual(controller.selectionState.focusID, items[2].id)

        collectionView.onNativeItemInteraction?([0], 2, .command, 1)

        XCTAssertEqual(controller.selectionState.selectedIDs, [items[0].id])
        XCTAssertEqual(controller.selectionState.anchorID, items[0].id)
        XCTAssertEqual(controller.selectionState.focusID, items[0].id)
    }

    @MainActor
    func testCommandDeleteFreezesSelectionInvalidatesQuickLookAndRecycles() {
        let recycler = FileRecyclerSpy()
        let failurePresenter = FileOperationFailurePresenterSpy()
        let controller = FileGridViewController(
            fileRecycler: recycler,
            fileOperationFailurePresenter: failurePresenter
        )
        controller.loadView()
        let items = makeItems(count: 3)
        controller.setItems(items)
        controller.handleClick(index: 2, modifiers: [])
        controller.handleClick(index: 0, modifiers: .command)
        var selections: [[URL]] = []
        controller.onSelectionChanged = { selections.append($0) }

        controller.handleKeyCommand(.trashSelection)

        XCTAssertEqual(recycler.recycledURLs, [[items[0].url, items[2].url]])
        XCTAssertTrue(controller.selectionState.selectedIDs.isEmpty)
        XCTAssertEqual(selections, [[]])
        XCTAssertTrue(failurePresenter.errors.isEmpty)
    }

    @MainActor
    func testContextMenuUsesFinderSelectionSemanticsAndExpectedActions() throws {
        let actions = FileContextActionPerformerSpy()
        let controller = FileGridViewController(contextActionPerformer: actions)
        controller.loadView()
        let items = makeItems(count: 3)
        controller.setItems(items)
        controller.handleClick(index: 0, modifiers: [])
        controller.handleClick(index: 2, modifiers: .command)

        let selectedMenu = try XCTUnwrap(controller.contextMenu(forItemAt: 2))
        XCTAssertEqual(controller.selectionState.selectedIDs, [items[0].id, items[2].id])
        XCTAssertEqual(
            selectedMenu.items.map(\.title),
            [
                localized("portal.files.open"),
                localized("portal.files.quick_look"),
                localized("portal.files.show_in_finder"),
                localized("portal.files.get_info"),
                "",
                localized("portal.files.rename"),
                localized("portal.files.compress"),
                localized("portal.files.duplicate"),
                localized("portal.files.move_to_trash"),
                "",
                localized("portal.files.airdrop"),
                localized("portal.files.copy_path"),
                localized("portal.files.open_in_terminal"),
            ]
        )

        XCTAssertNotNil(controller.contextMenu(forItemAt: 1))
        XCTAssertEqual(controller.selectionState.selectedIDs, [items[1].id])
        XCTAssertNil(controller.contextMenu(forItemAt: 99))
        XCTAssertEqual(controller.selectionState.selectedIDs, [items[1].id])
    }

    @MainActor
    func testContextMenuRoutesActionsUsingStableGridOrder() throws {
        let opener = WorkspaceOpenerSpy()
        let recycler = FileRecyclerSpy()
        let actions = FileContextActionPerformerSpy()
        let controller = FileGridViewController(
            workspaceOpener: opener,
            fileRecycler: recycler,
            contextActionPerformer: actions
        )
        controller.loadView()
        let items = makeItems(count: 3)
        controller.setItems(items)
        controller.handleClick(index: 2, modifiers: [])
        controller.handleClick(index: 0, modifiers: .command)
        let menu = try XCTUnwrap(controller.contextMenu(forItemAt: 2))
        var quickLookRequests: [[URL]] = []
        controller.onQuickLookRequested = { quickLookRequests.append($0) }

        performMenuItem(titled: localized("portal.files.open"), in: menu)
        performMenuItem(titled: localized("portal.files.quick_look"), in: menu)
        performMenuItem(titled: localized("portal.files.show_in_finder"), in: menu)
        performMenuItem(titled: localized("portal.files.airdrop"), in: menu)
        performMenuItem(titled: localized("portal.files.copy_path"), in: menu)
        performMenuItem(titled: localized("portal.files.open_in_terminal"), in: menu)

        let urls = [items[0].url, items[2].url]
        XCTAssertEqual(opener.openedURLs, urls)
        XCTAssertEqual(quickLookRequests, [urls])
        XCTAssertEqual(actions.revealedURLs, [urls])
        XCTAssertEqual(actions.airDroppedURLs, [urls])
        XCTAssertEqual(actions.copiedURLs, [urls])
        XCTAssertEqual(actions.terminalURLs, [[URL(fileURLWithPath: "/tmp", isDirectory: true)]])

        performMenuItem(titled: localized("portal.files.move_to_trash"), in: menu)
        XCTAssertEqual(recycler.recycledURLs, [urls])
    }

    @MainActor
    func testAirDropMenuValidationUsesTheSelectedURLs() throws {
        let actions = FileContextActionPerformerSpy()
        actions.canAirDrop = false
        let failurePresenter = FileOperationFailurePresenterSpy()
        let controller = FileGridViewController(
            fileOperationFailurePresenter: failurePresenter,
            contextActionPerformer: actions
        )
        controller.loadView()
        let items = makeItems(count: 2)
        controller.setItems(items)
        controller.handleKeyCommand(.selectAll)
        let menu = try XCTUnwrap(controller.contextMenu(forItemAt: 0))
        let airDrop = try XCTUnwrap(menu.item(withTitle: localized("portal.files.airdrop")))

        XCTAssertFalse(controller.validateMenuItem(airDrop))
        XCTAssertEqual(actions.airDropValidationURLs, [[items[0].url, items[1].url]])
        performMenuItem(titled: localized("portal.files.airdrop"), in: menu)
        XCTAssertEqual(
            failurePresenter.errors.first as? FileContextActionError,
            .airDropUnavailable
        )
    }

    @MainActor
    func testIconSizeUpdatesLayoutAndCellAccessibility() throws {
        let opener = WorkspaceOpenerSpy()
        let controller = FileGridViewController(workspaceOpener: opener, iconSize: .small)
        controller.loadView()
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/Folder"),
            name: "Folder",
            isDirectory: true,
            isHidden: false
        )
        controller.setItems([item])
        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        let collectionView = try XCTUnwrap(scrollView.documentView as? NSCollectionView)
        let layout = try XCTUnwrap(
            collectionView.collectionViewLayout as? PortalGridCollectionViewLayout
        )

        XCTAssertEqual(layout.metrics.itemSize, GridMetrics(iconSize: .small).itemSize)
        controller.updateIconSize(.large)
        XCTAssertEqual(layout.metrics.itemSize, GridMetrics(iconSize: .large).itemSize)

        let cell = try XCTUnwrap(
            controller.collectionView(collectionView, itemForRepresentedObjectAt: IndexPath(item: 0, section: 0))
                as? FileItemCell
        )
        XCTAssertEqual(cell.view.accessibilityRole(), .button)
        XCTAssertEqual(cell.view.accessibilityLabel(), "Folder")
        XCTAssertEqual(
            cell.view.accessibilityValue() as? String,
            String(
                format: NSLocalizedString("%1$@, item %2$d of %3$d", comment: ""),
                NSLocalizedString("Not selected", comment: ""),
                1,
                1
            )
        )
        XCTAssertEqual(
            cell.view.accessibilityHelp(),
            NSLocalizedString("Folder. Double-click to open in Finder.", comment: "")
        )
        XCTAssertEqual(
            cell.view.accessibilityCustomActions()?.map(\.name),
            [NSLocalizedString("Open", comment: "")]
        )
        XCTAssertTrue(cell.performAccessibilityOpen())
        XCTAssertEqual(opener.openedURLs, [item.url])

        controller.handleClick(index: 0, modifiers: [])
        controller.updateIconSize(.medium)
        XCTAssertEqual(collectionView.selectionIndexPaths, [IndexPath(item: 0, section: 0)])
    }

    @MainActor
    func testRenderedLayoutUsesTheSameFixedFramesAsCoreGridLayout() throws {
        let controller = FileGridViewController(iconSize: .medium)
        controller.loadView()
        controller.setItems(makeItems(count: 5))
        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        let collectionView = try XCTUnwrap(scrollView.documentView as? NSCollectionView)
        collectionView.frame.size.width = 500
        let layout = try XCTUnwrap(
            collectionView.collectionViewLayout as? PortalGridCollectionViewLayout
        )

        layout.prepare()

        let expected = GridLayout(metrics: layout.metrics).layout(
            itemCount: 5,
            visibleColumns: GridCapacity.minimum.columns,
            availableWidth: collectionView.bounds.width
        )
        XCTAssertEqual(layout.collectionViewContentSize, expected.contentSize)
        for index in 0..<5 {
            XCTAssertEqual(
                layout.layoutAttributesForItem(
                    at: IndexPath(item: index, section: 0)
                )?.frame,
                expected.itemFrames[index]
            )
        }
    }

    @MainActor
    func testOverlayScrollerPreservesThreeColumnBoundaryWithScrollableContent() throws {
        let controller = FileGridViewController(iconSize: .medium)
        controller.loadView()
        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 344, height: 180)
        controller.setItems(makeItems(count: 20))
        let collectionView = try XCTUnwrap(scrollView.documentView as? NSCollectionView)
        collectionView.frame.size.width = scrollView.contentSize.width
        let layout = try XCTUnwrap(
            collectionView.collectionViewLayout as? PortalGridCollectionViewLayout
        )

        layout.prepare()

        let first = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        )
        let third = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 2, section: 0))
        )
        let fourth = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))
        )
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertEqual(scrollView.verticalScroller?.controlSize, .mini)
        XCTAssertEqual(first.frame.minY, third.frame.minY)
        XCTAssertGreaterThan(fourth.frame.minY, first.frame.minY)
    }

    @MainActor
    func testViewportResizeReflowsItemsFromThreeToFourColumnsAndBack() throws {
        let controller = FileGridViewController(iconSize: .medium)
        controller.loadView()
        controller.setItems(makeItems(count: 8))
        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        let collectionView = try XCTUnwrap(scrollView.documentView as? NSCollectionView)
        let layout = try XCTUnwrap(
            collectionView.collectionViewLayout as? PortalGridCollectionViewLayout
        )

        scrollView.frame = NSRect(x: 0, y: 0, width: 344, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        layout.prepare()
        let threeColumnFirst = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        )
        let threeColumnFourth = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))
        )
        XCTAssertGreaterThan(threeColumnFourth.frame.minY, threeColumnFirst.frame.minY)

        scrollView.frame.size.width = 452
        scrollView.layoutSubtreeIfNeeded()
        controller.updateGridCapacity(try GridCapacity(columns: 4, rows: 2))
        controller.viewDidLayout()
        layout.prepare()
        let fourColumnFirst = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        )
        let fourColumnFourth = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))
        )
        XCTAssertEqual(fourColumnFourth.frame.minY, fourColumnFirst.frame.minY)
        XCTAssertGreaterThan(fourColumnFourth.frame.minX, fourColumnFirst.frame.minX)

        scrollView.frame.size.width = 344
        scrollView.layoutSubtreeIfNeeded()
        controller.updateGridCapacity(try GridCapacity(columns: 3, rows: 2))
        controller.viewDidLayout()
        layout.prepare()
        let narrowedFirst = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        )
        let narrowedFourth = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))
        )
        XCTAssertGreaterThan(narrowedFourth.frame.minY, narrowedFirst.frame.minY)
        XCTAssertEqual(collectionView.bounds.width, scrollView.contentView.bounds.width)
    }

    @MainActor
    func testFourColumnCapacityDoesNotFallBackToThreeForNarrowerContentRect() throws {
        let capacity = try GridCapacity(columns: 4, rows: 2)
        let controller = FileGridViewController(
            iconSize: .medium,
            gridCapacity: capacity
        )
        controller.loadView()
        controller.setItems(makeItems(count: 8))
        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 450, height: 292)
        scrollView.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        let collectionView = try XCTUnwrap(scrollView.documentView as? NSCollectionView)
        let layout = try XCTUnwrap(
            collectionView.collectionViewLayout as? PortalGridCollectionViewLayout
        )
        layout.prepare()

        let first = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        )
        let fourth = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))
        )
        let fifth = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 4, section: 0))
        )
        let eighth = try XCTUnwrap(
            layout.layoutAttributesForItem(at: IndexPath(item: 7, section: 0))
        )
        XCTAssertEqual(layout.visibleColumns, 4)
        XCTAssertEqual(fourth.frame.minY, first.frame.minY)
        XCTAssertGreaterThan(fifth.frame.minY, first.frame.minY)
        XCTAssertEqual(eighth.frame.minY, fifth.frame.minY)
    }

    @MainActor
    func testCellUsesSeparateSelectionRegionsAndTwoLineCharacterWrapping() throws {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/Sunrise_会员维护模型业务规则_v1.2.md"),
            name: "Sunrise_会员维护模型业务规则_v1.2.md",
            isDirectory: false,
            isHidden: false
        )
        let metrics = GridMetrics(iconSize: .medium, labelFontSize: 12)
        let cell = FileItemCell()
        cell.loadView()
        cell.configure(
            with: item,
            metrics: metrics,
            position: 1,
            itemCount: 1,
            onOpen: { true }
        )
        cell.view.frame = NSRect(origin: .zero, size: metrics.itemSize)
        cell.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(cell.nameLabel.lineBreakMode, .byCharWrapping)
        XCTAssertEqual(cell.nameLabel.maximumNumberOfLines, 2)
        XCTAssertEqual(cell.nameLabel.font?.pointSize, 12)
        XCTAssertEqual(cell.iconView.frame.size, NSSize(width: 64, height: 64))
        XCTAssertEqual(cell.iconSelectionView.frame.size, NSSize(width: 72, height: 72))
        XCTAssertGreaterThan(cell.nameLabel.frame.height, 12)
        XCTAssertEqual(cell.view.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertEqual(cell.view.layer?.cornerRadius, 12)
        XCTAssertEqual(cell.view.layer?.borderWidth, 1)
        XCTAssertGreaterThan(cell.view.layer?.borderColor?.alpha ?? 0, 0)

        cell.isSelected = true

        XCTAssertGreaterThan(cell.iconSelectionView.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertGreaterThan(cell.labelSelectionView.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertEqual(cell.nameLabel.textColor, .white)
        XCTAssertEqual(cell.view.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertEqual(cell.view.accessibilityLabel(), item.name)
    }

    func makeItems(count: Int) -> [FileItem] {
        (0..<count).map { index in
            FileItem(
                url: URL(fileURLWithPath: "/tmp/file-\(index)"),
                name: "file-\(index)",
                isDirectory: false,
                isHidden: false
            )
        }
    }

    func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "Test localization lookup")
    }

    func zipPayloadEntries(at archiveURL: URL) throws -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archiveURL.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FileOperationError.compressionFailed(process.terminationStatus)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("__MACOSX/") && !$0.hasSuffix("/") }
            .sorted()
    }

    @MainActor
    func performMenuItem(titled title: String, in menu: NSMenu) {
        guard let item = menu.item(withTitle: title), let action = item.action else {
            XCTFail("Missing context menu item: \(title)")
            return
        }
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
    }
}

@MainActor
final class WorkspaceOpenerSpy: WorkspaceOpening {
    private let failingNames: Set<String>
    private(set) var openedURLs: [URL] = []

    init(failingNames: Set<String> = []) {
        self.failingNames = failingNames
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return !failingNames.contains(url.lastPathComponent)
    }
}

@MainActor
final class WorkspaceOpenFailurePresenterSpy: WorkspaceOpenFailurePresenting {
    private(set) var failedURLs: [URL] = []

    func presentFailure(for url: URL) {
        failedURLs.append(url)
    }
}

@MainActor
final class FileRecyclerSpy: FileRecycling {
    private(set) var recycledURLs: [[URL]] = []

    func recycle(
        _ urls: [URL],
        completion: @escaping @MainActor @Sendable (Error?) -> Void
    ) {
        recycledURLs.append(urls)
        completion(nil)
    }
}

@MainActor
final class FileDuplicatorSpy: FileDuplicating {
    private(set) var requests: [[URL]] = []

    func duplicate(
        _ urls: [URL],
        completion: @escaping @MainActor @Sendable ([URL], Error?) -> Void
    ) {
        requests.append(urls)
        completion(
            urls.map { $0.deletingPathExtension().appendingPathExtension("copy") },
            nil
        )
    }
}

@MainActor
final class FinderInfoOpenerSpy: FinderInfoOpening {
    private let error: FinderInfoError?
    private(set) var openedURLs: [URL] = []
    var onOpen: (() -> Void)?

    init(error: FinderInfoError? = nil) {
        self.error = error
    }

    func openInfo(for url: URL) async throws {
        openedURLs.append(url)
        onOpen?()
        if let error {
            throw error
        }
    }
}

actor FileCompressorSpy: FileCompressing {
    func compress(_ sourceURLs: [URL]) -> URL {
        URL(fileURLWithPath: "/tmp/Archive.zip")
    }
}

@MainActor
final class FileOperationFailurePresenterSpy: FileOperationFailurePresenting {
    private(set) var errors: [Error] = []
    var onPresent: (() -> Void)?

    func present(_ error: Error) {
        errors.append(error)
        onPresent?()
    }
}

@MainActor
final class FileContextActionPerformerSpy: FileContextActionPerforming {
    var canAirDrop = true
    private(set) var revealedURLs: [[URL]] = []
    private(set) var copiedURLs: [[URL]] = []
    private(set) var airDropValidationURLs: [[URL]] = []
    private(set) var airDroppedURLs: [[URL]] = []
    private(set) var terminalURLs: [[URL]] = []

    func revealInFinder(_ urls: [URL]) {
        revealedURLs.append(urls)
    }

    func copyPaths(_ urls: [URL]) {
        copiedURLs.append(urls)
    }

    func canSendViaAirDrop(_ urls: [URL]) -> Bool {
        airDropValidationURLs.append(urls)
        return canAirDrop
    }

    func sendViaAirDrop(_ urls: [URL]) -> Bool {
        if canAirDrop {
            airDroppedURLs.append(urls)
        }
        return canAirDrop
    }

    func openInTerminal(
        _ urls: [URL],
        completion: @escaping @MainActor @Sendable (FileContextActionError?) -> Void
    ) {
        terminalURLs.append(urls)
        completion(nil)
    }
}
