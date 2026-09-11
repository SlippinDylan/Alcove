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
}
