import AppKit
import AlcoveCore
import XCTest
@testable import Alcove

final class StatusMenuControllerTests: XCTestCase {
    @MainActor
    func testMenuContainsNewPortalUpdateSettingsAndQuitActions() {
        var requestCount = 0
        var settingsRequestCount = 0
        var updateRequestCount = 0
        let controller = StatusMenuController(
            onNewPortal: { requestCount += 1 },
            onOpenSettings: { settingsRequestCount += 1 },
            canCheckForUpdates: { true },
            onCheckForUpdates: { updateRequestCount += 1 }
        )
        let menu = controller.makeMenu()

        XCTAssertEqual(menu.items.count, 5)
        XCTAssertEqual(menu.items[0].title, NSLocalizedString("menu.new_portal", comment: ""))
        XCTAssertTrue(menu.items[0].isEnabled)
        XCTAssertNotNil(menu.items[0].image)
        XCTAssertTrue(menu.items[0].image?.isTemplate == true)
        menu.performActionForItem(at: 0)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(
            menu.items[2].title,
            NSLocalizedString("menu.check_for_updates", comment: "")
        )
        XCTAssertTrue(menu.items[2].isEnabled)
        XCTAssertNotNil(menu.items[2].image)
        XCTAssertTrue(menu.items[2].image?.isTemplate == true)
        menu.performActionForItem(at: 2)
        XCTAssertEqual(updateRequestCount, 1)
        XCTAssertEqual(menu.items[3].title, NSLocalizedString("menu.settings", comment: ""))
        XCTAssertTrue(menu.items[3].isEnabled)
        XCTAssertNotNil(menu.items[3].image)
        XCTAssertTrue(menu.items[3].image?.isTemplate == true)
        menu.performActionForItem(at: 3)
        XCTAssertEqual(settingsRequestCount, 1)
        XCTAssertEqual(menu.items[4].title, NSLocalizedString("menu.quit", comment: ""))
        XCTAssertNotNil(menu.items[4].image)
        XCTAssertTrue(menu.items[4].image?.isTemplate == true)
        XCTAssertEqual(menu.items[4].action, #selector(NSApplication.terminate(_:)))
        XCTAssertTrue(menu.items[4].target === NSApplication.shared)
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
    func testUpdateMenuValidationTracksUpdaterReadiness() throws {
        var canCheckForUpdates = false
        let controller = StatusMenuController(
            onNewPortal: {},
            canCheckForUpdates: { canCheckForUpdates }
        )
        let item = try XCTUnwrap(controller.makeMenu().items.first {
            $0.title == NSLocalizedString("menu.check_for_updates", comment: "")
        })

        XCTAssertFalse(controller.validateMenuItem(item))
        canCheckForUpdates = true
        XCTAssertTrue(controller.validateMenuItem(item))
    }

    @MainActor
    func testPortalSubmenusPreserveOrderAndDispatchTypedActions() throws {
        let firstID = PortalID()
        let secondID = PortalID()
        var shownIDs: [PortalID] = []
        var hiddenIDs: [PortalID] = []
        var pinnedRequests: [(PortalID, Bool)] = []
        var settingsIDs: [PortalID] = []
        var removedIDs: [PortalID] = []
        let controller = StatusMenuController(
            onNewPortal: {},
            onShowPortal: { shownIDs.append($0) },
            onHidePortal: { hiddenIDs.append($0) },
            onSetPortalPinned: { pinnedRequests.append(($0, $1)) },
            onOpenPortalSettings: { settingsIDs.append($0) },
            onRequestPortalRemoval: { removedIDs.append($0) }
        )
        controller.updatePortals([
            PortalMenuEntry(id: firstID, title: "First", isPinned: true),
            PortalMenuEntry(id: secondID, title: "Second"),
        ])

        let menu = controller.makeMenu()

        XCTAssertEqual(menu.items.map(\.title), [
            NSLocalizedString("menu.new_portal", comment: ""),
            "",
            "First",
            "Second",
            "",
            NSLocalizedString("menu.check_for_updates", comment: ""),
            NSLocalizedString("menu.settings", comment: ""),
            NSLocalizedString("menu.quit", comment: ""),
        ])
        let firstMenu = try XCTUnwrap(menu.items[2].submenu)
        XCTAssertEqual(firstMenu.items.map(\.title), [
            NSLocalizedString("menu.show", comment: ""),
            NSLocalizedString("menu.hide", comment: ""),
            "",
            NSLocalizedString("portal.pin.unpin", comment: ""),
            NSLocalizedString("portal.settings.open", comment: ""),
            "",
            NSLocalizedString("portal.remove.menu", comment: ""),
        ])
        XCTAssertEqual(firstMenu.items.filter(\.isSeparatorItem).count, 2)
        XCTAssertTrue(firstMenu.items.filter { !$0.isSeparatorItem }.allSatisfy {
            $0.image != nil && $0.image?.isTemplate == true
        })
        firstMenu.performActionForItem(at: 0)
        firstMenu.performActionForItem(at: 1)
        firstMenu.performActionForItem(at: 3)
        firstMenu.performActionForItem(at: 4)
        firstMenu.performActionForItem(at: 6)

        XCTAssertEqual(shownIDs, [firstID])
        XCTAssertEqual(hiddenIDs, [firstID])
        XCTAssertEqual(pinnedRequests.count, 1)
        XCTAssertEqual(pinnedRequests[0].0, firstID)
        XCTAssertFalse(pinnedRequests[0].1)
        XCTAssertEqual(settingsIDs, [firstID])
        XCTAssertEqual(removedIDs, [firstID])
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
            NSLocalizedString("menu.check_for_updates", comment: ""),
            NSLocalizedString("menu.settings", comment: ""),
            NSLocalizedString("menu.quit", comment: ""),
        ])
        controller.stop()
    }
}
