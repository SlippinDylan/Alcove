import AlcoveCore
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
        let columnCount = GridLayout(metrics: GridMetrics(iconSize: .medium))
            .layout(itemCount: items.count, availableWidth: 560)
            .columnCount
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
        XCTAssertEqual(FileCollectionView.command(keyCode: 36, modifiers: []), .noOperation)
        XCTAssertEqual(FileCollectionView.command(keyCode: 49, modifiers: []), .toggleQuickLook)
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
        XCTAssertEqual(cell.view.accessibilityValue() as? String, "Not selected, item 1 of 1")
        XCTAssertEqual(cell.view.accessibilityHelp(), "Folder. Double-click to open in Finder.")
        XCTAssertEqual(cell.view.accessibilityCustomActions()?.map(\.name), ["Open"])
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
        scrollView.frame = NSRect(x: 0, y: 0, width: 392, height: 180)
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
        XCTAssertEqual(first.frame.minY, third.frame.minY)
        XCTAssertGreaterThan(fourth.frame.minY, first.frame.minY)
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

        cell.isSelected = true

        XCTAssertGreaterThan(cell.iconSelectionView.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertGreaterThan(cell.labelSelectionView.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertEqual(cell.view.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertEqual(cell.view.accessibilityLabel(), item.name)
    }

    private func makeItems(count: Int) -> [FileItem] {
        (0..<count).map { index in
            FileItem(
                url: URL(fileURLWithPath: "/tmp/file-\(index)"),
                name: "file-\(index)",
                isDirectory: false,
                isHidden: false
            )
        }
    }
}

@MainActor
private final class WorkspaceOpenerSpy: WorkspaceOpening {
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
private final class WorkspaceOpenFailurePresenterSpy: WorkspaceOpenFailurePresenting {
    private(set) var failedURLs: [URL] = []

    func presentFailure(for url: URL) {
        failedURLs.append(url)
    }
}
