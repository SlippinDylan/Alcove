import Foundation
import XCTest
@testable import AlcoveCore

final class PortalTests: XCTestCase {
    private let frame = CGRect(x: 20, y: 40, width: 320, height: 240)

    func testOneTabCreationUsesStandardizedFolderURLAndFreshIdentities() throws {
        let portal = try Portal(folderURL: URL(fileURLWithPath: "/tmp/alcove/../folder"), frame: frame)

        XCTAssertEqual(portal.tabs.count, 1)
        XCTAssertEqual(portal.tabs[0].folderURL.path, "/tmp/folder")
        XCTAssertEqual(portal.selectedTabID, portal.tabs[0].id)
        XCTAssertNotEqual(portal.id.rawValue, portal.tabs[0].id.rawValue)
    }

    func testFolderTabStandardizesURLWithoutReadingTheFilesystem() {
        let tab = FolderTab(folderURL: URL(fileURLWithPath: "/path/that/does/not/exist/../folder"))

        XCTAssertEqual(tab.folderURL.path, "/path/that/does/not/folder")
    }

    func testRestoreRejectsEmptyTabsDuplicateTabIDsAndUnknownSelection() {
        let firstID = FolderTabID(rawValue: UUID())
        let firstTab = FolderTab(id: firstID, folderURL: URL(fileURLWithPath: "/tmp/first"))
        let unknownID = FolderTabID(rawValue: UUID())

        XCTAssertThrowsError(
            try Portal(tabs: [], selectedTabID: firstID, frame: frame)
        ) { error in
            XCTAssertEqual(error as? PortalError, .emptyTabs)
        }
        XCTAssertThrowsError(
            try Portal(tabs: [firstTab, firstTab], selectedTabID: firstID, frame: frame)
        ) { error in
            XCTAssertEqual(error as? PortalError, .duplicateTabID(firstID))
        }
        XCTAssertThrowsError(
            try Portal(tabs: [firstTab], selectedTabID: unknownID, frame: frame)
        ) { error in
            XCTAssertEqual(error as? PortalError, .selectedTabNotFound(unknownID))
        }
    }

    func testRestoreRejectsNonFiniteAndNonPositiveFrames() {
        let tab = FolderTab(folderURL: URL(fileURLWithPath: "/tmp/folder"))

        XCTAssertThrowsError(
            try Portal(
                tabs: [tab],
                selectedTabID: tab.id,
                frame: CGRect(x: CGFloat.infinity, y: 0, width: 320, height: 240)
            )
        ) { error in
            XCTAssertEqual(error as? PortalError, .nonFiniteFrame)
        }
        XCTAssertThrowsError(
            try Portal(
                tabs: [tab],
                selectedTabID: tab.id,
                frame: CGRect(x: 0, y: 0, width: 0, height: 240)
            )
        ) { error in
            XCTAssertEqual(error as? PortalError, .nonPositiveFrameSize)
        }
    }

    func testTabsRemainInCreationOrderAndSelectionCanChange() throws {
        var portal = try Portal(folderURL: URL(fileURLWithPath: "/tmp/first"), frame: frame)
        let secondID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let thirdID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/third"))

        try portal.selectTab(thirdID)

        XCTAssertEqual(portal.tabs.map(\.folderURL.path), ["/tmp/first", "/tmp/second", "/tmp/third"])
        XCTAssertEqual(portal.selectedTabID, thirdID)
        XCTAssertNotEqual(secondID, thirdID)
    }

    func testRemovingSelectedTabSelectsItsSuccessorOrPredecessor() throws {
        var portal = try Portal(folderURL: URL(fileURLWithPath: "/tmp/first"), frame: frame)
        let secondID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let thirdID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/third"))

        try portal.selectTab(secondID)
        try portal.removeTab(secondID)
        XCTAssertEqual(portal.selectedTabID, thirdID)

        try portal.removeTab(thirdID)
        XCTAssertEqual(portal.selectedTabID, portal.tabs[0].id)
    }

    func testTabOperationsRejectInvalidTargetsAndPreserveTheLastTab() throws {
        var portal = try Portal(folderURL: URL(fileURLWithPath: "/tmp/first"), frame: frame)
        let unknownID = FolderTabID(rawValue: UUID())

        XCTAssertThrowsError(try portal.selectTab(unknownID)) { error in
            XCTAssertEqual(error as? PortalError, .tabNotFound(unknownID))
        }
        XCTAssertThrowsError(try portal.removeTab(unknownID)) { error in
            XCTAssertEqual(error as? PortalError, .tabNotFound(unknownID))
        }
        XCTAssertThrowsError(try portal.removeTab(portal.tabs[0].id)) { error in
            XCTAssertEqual(error as? PortalError, .cannotRemoveLastTab)
        }
    }

    func testFrameAndIconSizeUpdatesPreserveValidatedState() throws {
        var portal = try Portal(folderURL: URL(fileURLWithPath: "/tmp/folder"), frame: frame)
        let updatedFrame = CGRect(x: -10, y: 5, width: 640, height: 480)

        try portal.updateFrame(updatedFrame)
        portal.updateIconSize(.large)

        XCTAssertEqual(portal.frame, updatedFrame)
        XCTAssertEqual(portal.iconSize, .large)
    }
}
