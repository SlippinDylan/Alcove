import AppKit
import XCTest
@testable import Alcove

final class StatusMenuControllerTests: XCTestCase {
    @MainActor
    func testMenuContainsEnabledNewPortalSeparatorAndQuit() {
        var requestCount = 0
        let controller = StatusMenuController {
            requestCount += 1
        }
        let menu = controller.makeMenu()

        XCTAssertEqual(menu.items.count, 3)
        XCTAssertEqual(menu.items[0].title, "New Portal")
        XCTAssertTrue(menu.items[0].isEnabled)
        menu.performActionForItem(at: 0)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].title, "Quit Alcove")
        XCTAssertEqual(menu.items[2].action, #selector(NSApplication.terminate(_:)))
        XCTAssertTrue(menu.items[2].target === NSApplication.shared)
    }

    @MainActor
    func testStartAndStopOwnExactlyOneStatusItem() {
        let controller = StatusMenuController(onNewPortal: {})

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
