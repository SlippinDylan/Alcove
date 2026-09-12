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

    @MainActor
    func testPortalSubmenusPreserveOrderAndDispatchTypedActions() throws {
        let firstID = PortalID()
        let secondID = PortalID()
        var shownIDs: [PortalID] = []
        var removedIDs: [PortalID] = []
        var sizeRequests: [(PortalID, IconSize)] = []
        var followRequests: [PortalID] = []
        let controller = StatusMenuController(
            onNewPortal: {},
            onShowPortal: { shownIDs.append($0) },
            onRemovePortal: { removedIDs.append($0) },
            onSetIconSize: { sizeRequests.append(($0, $1)) },
            onFollowDesktopIconSettings: { followRequests.append($0) }
        )
        controller.updatePortals([
            PortalMenuEntry(id: firstID, title: "First", iconLayout: .fixed(.small)),
            PortalMenuEntry(
                id: secondID,
                title: "Second",
                iconLayout: .followDesktop(
                    try XCTUnwrap(DesktopIconSettings(iconSize: .large, textSize: 14))
                )
            ),
        ])

        let menu = controller.makeMenu()

        XCTAssertEqual(menu.items.map(\.title), ["New Portal", "", "First", "Second", "", "Quit Alcove"])
        let firstMenu = try XCTUnwrap(menu.items[2].submenu)
        XCTAssertEqual(firstMenu.items.map(\.title), ["Show", "Icon Size", "", "Remove Portal"])
        firstMenu.performActionForItem(at: 0)
        firstMenu.performActionForItem(at: 3)
        let iconMenu = try XCTUnwrap(firstMenu.items[1].submenu)
        XCTAssertEqual(
            iconMenu.items.map(\.title),
            ["Follow Desktop", "", "Small", "Medium", "Large"]
        )
        XCTAssertEqual(iconMenu.items.map(\.state), [.off, .off, .on, .off, .off])
        iconMenu.performActionForItem(at: 4)
        let secondIconMenu = try XCTUnwrap(menu.items[3].submenu?.items[1].submenu)
        XCTAssertEqual(secondIconMenu.items[0].state, .on)
        secondIconMenu.performActionForItem(at: 0)

        XCTAssertEqual(shownIDs, [firstID])
        XCTAssertEqual(removedIDs, [firstID])
        XCTAssertEqual(sizeRequests.count, 1)
        XCTAssertEqual(sizeRequests[0].0, firstID)
        XCTAssertEqual(sizeRequests[0].1, .large)
        XCTAssertEqual(followRequests, [secondID])
    }

    @MainActor
    func testUpdatingPortalsRebuildsInstalledMenu() {
        let controller = StatusMenuController(onNewPortal: {})
        controller.start()

        controller.updatePortals([
            PortalMenuEntry(
                id: PortalID(),
                title: "Documents",
                iconLayout: .fixed(.medium)
            ),
        ])

        XCTAssertEqual(controller.statusItem?.menu?.items.map(\.title), [
            "New Portal", "", "Documents", "", "Quit Alcove",
        ])
        controller.stop()
    }
}
