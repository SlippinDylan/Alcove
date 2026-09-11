import AlcoveCore
import XCTest
@testable import Alcove

final class PortalViewControllerTests: XCTestCase {
    @MainActor
    func testReloadAppliesAcceptedFolderContents() async {
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
        let controller = PortalViewController(
            folderURL: root,
            loadingCoordinator: coordinator
        )
        controller.loadView()

        await controller.reload()

        XCTAssertEqual(controller.presentationState, .items(1))
    }

    @MainActor
    func testReloadShowsEmptyState() async {
        let root = URL(fileURLWithPath: "/tmp/empty-portal")
        let coordinator = FolderLoadingCoordinator(
            enumerator: FixedFolderEnumerator(root: root, items: [])
        )
        let controller = PortalViewController(
            folderURL: root,
            loadingCoordinator: coordinator
        )
        controller.loadView()

        await controller.reload()

        XCTAssertEqual(controller.presentationState, .message("This folder is empty"))
    }
}

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
