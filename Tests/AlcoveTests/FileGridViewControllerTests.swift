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
        XCTAssertTrue(controller.view is NSScrollView)
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
        controller.handleKeyCommand(.moveDown(extending: true))
        XCTAssertTrue(controller.selectionState.selectedIDs.contains(items[7].id))

        let stateBeforeReturn = controller.selectionState.selectedIDs
        controller.handleKeyCommand(.noOperation)
        XCTAssertEqual(controller.selectionState.selectedIDs, stateBeforeReturn)
    }

    @MainActor
    func testDoubleClickAndOpenSelectionUseWorkspaceBoundary() {
        let opener = WorkspaceOpenerSpy(failingNames: ["file-2"])
        let controller = FileGridViewController(workspaceOpener: opener)
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
