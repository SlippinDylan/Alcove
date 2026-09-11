import AppKit
import XCTest
@testable import Alcove

final class StatusMenuControllerTests: XCTestCase {
    @MainActor
    func testMenuContainsDisabledNewPortalSeparatorAndQuit() {
        let menu = StatusMenuController.makeMenu()

        XCTAssertEqual(menu.items.count, 3)
        XCTAssertEqual(menu.items[0].title, "New Portal")
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].title, "Quit Alcove")
        XCTAssertEqual(menu.items[2].action, #selector(NSApplication.terminate(_:)))
        XCTAssertTrue(menu.items[2].target === NSApplication.shared)
    }

    @MainActor
    func testStartAndStopOwnExactlyOneStatusItem() {
        let controller = StatusMenuController()

        controller.start()
        let firstItem = controller.statusItem
        controller.start()

        XCTAssertNotNil(firstItem)
        XCTAssertTrue(controller.statusItem === firstItem)

        controller.stop()
        XCTAssertNil(controller.statusItem)
        controller.stop()
        XCTAssertNil(controller.statusItem)
    }
}
