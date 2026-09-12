import AppKit
import AlcoveCore
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

        XCTAssertEqual(menu.items.count, 4)
        XCTAssertEqual(menu.items[0].title, NSLocalizedString("menu.new_portal", comment: ""))
        XCTAssertTrue(menu.items[0].isEnabled)
        menu.performActionForItem(at: 0)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].title, NSLocalizedString("menu.settings", comment: ""))
        XCTAssertFalse(menu.items[2].isEnabled)
        XCTAssertEqual(menu.items[3].title, NSLocalizedString("menu.quit", comment: ""))
        XCTAssertEqual(menu.items[3].action, #selector(NSApplication.terminate(_:)))
        XCTAssertTrue(menu.items[3].target === NSApplication.shared)
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

    @MainActor
    func testPortalSubmenusPreserveOrderAndDispatchTypedActions() throws {
        let firstID = PortalID()
        let secondID = PortalID()
        var shownIDs: [PortalID] = []
        var hiddenIDs: [PortalID] = []
        let controller = StatusMenuController(
            onNewPortal: {},
            onShowPortal: { shownIDs.append($0) },
            onHidePortal: { hiddenIDs.append($0) }
        )
        controller.updatePortals([
            PortalMenuEntry(id: firstID, title: "First"),
            PortalMenuEntry(id: secondID, title: "Second"),
        ])

        let menu = controller.makeMenu()

        XCTAssertEqual(menu.items.map(\.title), [
            NSLocalizedString("menu.new_portal", comment: ""),
            "",
            "First",
            "Second",
            "",
            NSLocalizedString("menu.settings", comment: ""),
            NSLocalizedString("menu.quit", comment: ""),
        ])
        let firstMenu = try XCTUnwrap(menu.items[2].submenu)
        XCTAssertEqual(firstMenu.items.map(\.title), [
            NSLocalizedString("menu.show", comment: ""),
            NSLocalizedString("menu.hide", comment: ""),
        ])
        firstMenu.performActionForItem(at: 0)
        firstMenu.performActionForItem(at: 1)

        XCTAssertEqual(shownIDs, [firstID])
        XCTAssertEqual(hiddenIDs, [firstID])
    }

    @MainActor
    func testUpdatingPortalsRebuildsInstalledMenu() {
        let controller = StatusMenuController(onNewPortal: {})
        controller.start()

        controller.updatePortals([
            PortalMenuEntry(
                id: PortalID(),
                title: "Documents"
            ),
        ])

        XCTAssertEqual(controller.statusItem?.menu?.items.map(\.title), [
            NSLocalizedString("menu.new_portal", comment: ""),
            "",
            "Documents",
            "",
            NSLocalizedString("menu.settings", comment: ""),
            NSLocalizedString("menu.quit", comment: ""),
        ])
        controller.stop()
    }
}
