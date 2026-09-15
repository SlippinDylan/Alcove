import Foundation
import XCTest
@testable import AlcoveCore

final class PortalTests: XCTestCase {
    private let frame = CGRect(x: 20, y: 40, width: 320, height: 240)
    private let display = DisplayDescriptor(
        identity: DisplayIdentity(rawValue: "display-a"),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
    )

    func testOneTabCreationUsesStandardizedFolderURLAndFreshIdentities() throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/alcove/../folder"),
            frame: frame,
            display: display
        )

        XCTAssertEqual(portal.tabs.count, 1)
        XCTAssertEqual(portal.tabs[0].folderURL.path, "/tmp/folder")
        XCTAssertEqual(portal.selectedTabID, portal.tabs[0].id)
        XCTAssertNotEqual(portal.id.rawValue, portal.tabs[0].id.rawValue)
    }

    func testFolderTabStandardizesURLWithoutReadingTheFilesystem() {
        let tab = FolderTab(folderURL: URL(fileURLWithPath: "/path/that/does/not/exist/../folder"))

        XCTAssertEqual(tab.folderURL.path, "/path/that/does/not/folder")
    }

    func testEmptyPortalRequiresNoSelectionAndSelectsItsFirstAddedTab() throws {
        var portal = try Portal(
            tabs: [],
            selectedTabID: nil,
            placement: makePlacement()
        )

        XCTAssertTrue(portal.tabs.isEmpty)
        XCTAssertNil(portal.selectedTabID)
        let firstID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/first"))
        XCTAssertEqual(portal.selectedTabID, firstID)
    }

    func testRestoreRejectsInvalidTabAndSelectionCombinations() {
        let firstID = FolderTabID(rawValue: UUID())
        let firstTab = FolderTab(id: firstID, folderURL: URL(fileURLWithPath: "/tmp/first"))
        let unknownID = FolderTabID(rawValue: UUID())

        XCTAssertThrowsError(
            try Portal(tabs: [], selectedTabID: firstID, placement: makePlacement())
        ) { error in
            XCTAssertEqual(error as? PortalError, .selectionWithoutTabs(firstID))
        }
        XCTAssertThrowsError(
            try Portal(tabs: [firstTab], selectedTabID: nil, placement: makePlacement())
        ) { error in
            XCTAssertEqual(error as? PortalError, .missingSelectedTab)
        }
        XCTAssertThrowsError(
            try Portal(
                tabs: [firstTab, firstTab],
                selectedTabID: firstID,
                placement: makePlacement()
            )
        ) { error in
            XCTAssertEqual(error as? PortalError, .duplicateTabID(firstID))
        }
        XCTAssertThrowsError(
            try Portal(
                tabs: [firstTab],
                selectedTabID: unknownID,
                placement: makePlacement()
            )
        ) { error in
            XCTAssertEqual(error as? PortalError, .selectedTabNotFound(unknownID))
        }
    }

    func testPlacementRecordRejectsMissingHomeAndInvalidEntries() throws {
        let identity = display.identity
        let validEntry = try PlacementGeometry.capture(
            windowFrame: frame,
            visibleFrame: display.visibleFrame
        )
        XCTAssertThrowsError(
            try PlacementRecord(framesByDisplay: [identity: validEntry], homeDisplay: .init(rawValue: "missing"))
        ) { error in
            XCTAssertEqual(
                error as? PlacementRecordError,
                .missingHomePlacement(.init(rawValue: "missing"))
            )
        }

        let invalidEntry = DisplayPlacementEntry(
            absoluteFrame: frame,
            referenceVisibleFrame: CGRect(
                x: 0,
                y: 0,
                width: CGFloat.infinity,
                height: 900
            ),
            preferredSize: frame.size,
            normalizedAnchor: .center
        )
        XCTAssertThrowsError(
            try PlacementRecord(framesByDisplay: [identity: invalidEntry], homeDisplay: identity)
        ) { error in
            XCTAssertEqual(
                error as? PlacementRecordError,
                .invalidEntry(identity, .nonFiniteValue("currentVisibleFrame.size"))
            )
        }
    }

    func testPlacementRecordRejectsNonPositiveFrames() {
        XCTAssertThrowsError(
            try PlacementRecord(
                frame: CGRect(x: 0, y: 0, width: 0, height: 240),
                display: display
            )
        ) { error in
            XCTAssertEqual(
                error as? PlacementRecordError,
                .nonPositiveFrameSize(display.identity)
            )
        }
    }

    func testPlacementRecordRejectsNonPositivePreferredSize() throws {
        let identity = display.identity
        let invalidEntry = DisplayPlacementEntry(
            absoluteFrame: frame,
            referenceVisibleFrame: display.visibleFrame,
            preferredSize: CGSize(width: 0, height: frame.height),
            normalizedAnchor: .center
        )

        XCTAssertThrowsError(
            try PlacementRecord(framesByDisplay: [identity: invalidEntry], homeDisplay: identity)
        ) { error in
            XCTAssertEqual(
                error as? PlacementRecordError,
                .nonPositivePreferredSize(identity)
            )
        }
    }

    func testPortalCreationWrapsPlacementGeometryErrors() {
        let invalidDisplay = DisplayDescriptor(
            identity: display.identity,
            visibleFrame: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 900)
        )

        XCTAssertThrowsError(
            try Portal(
                folderURL: URL(fileURLWithPath: "/tmp/folder"),
                frame: frame,
                display: invalidDisplay
            )
        ) { error in
            XCTAssertEqual(
                error as? PortalError,
                .invalidPlacement(
                    .invalidEntry(
                        display.identity,
                        .nonFiniteValue("visibleFrame.size")
                    )
                )
            )
        }
    }

    func testTabsRemainInCreationOrderAndSelectionCanChange() throws {
        var portal = try makePortal(path: "/tmp/first")
        let secondID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let thirdID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/third"))

        try portal.selectTab(thirdID)

        XCTAssertEqual(portal.tabs.map(\.folderURL.path), ["/tmp/first", "/tmp/second", "/tmp/third"])
        XCTAssertEqual(portal.selectedTabID, thirdID)
        XCTAssertNotEqual(secondID, thirdID)
    }

    func testPortalRejectsMoreThanFourTabsAtCreationAndAppendBoundaries() throws {
        var portal = try makePortal(path: "/tmp/first")
        _ = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        _ = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/third"))
        _ = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/fourth"))

        XCTAssertEqual(portal.tabs.count, Portal.maximumTabCount)
        XCTAssertThrowsError(
            try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/fifth"))
        ) { error in
            XCTAssertEqual(
                error as? PortalError,
                .maximumTabCountExceeded(Portal.maximumTabCount)
            )
        }

        let fifthTab = FolderTab(folderURL: URL(fileURLWithPath: "/tmp/fifth"))
        XCTAssertThrowsError(try Portal(
            id: portal.id,
            tabs: portal.tabs + [fifthTab],
            selectedTabID: portal.selectedTabID,
            placement: portal.placement,
            iconLayout: portal.iconLayout,
            backgroundStyle: portal.backgroundStyle,
            gridCapacity: portal.gridCapacity,
            isPinned: portal.isPinned,
            sortOrder: portal.sortOrder,
            tint: portal.tint
        )) { error in
            XCTAssertEqual(
                error as? PortalError,
                .maximumTabCountExceeded(Portal.maximumTabCount)
            )
        }
    }

    func testMovingTabsSwapsAdjacentOrderAndPreservesSelection() throws {
        var portal = try makePortal(path: "/tmp/first")
        let firstID = portal.tabs[0].id
        let secondID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let thirdID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/third"))
        try portal.selectTab(secondID)

        try portal.moveTab(secondID, toward: .up)
        XCTAssertEqual(portal.tabs.map(\.id), [secondID, firstID, thirdID])
        XCTAssertEqual(portal.selectedTabID, secondID)

        try portal.moveTab(secondID, toward: .down)
        XCTAssertEqual(portal.tabs.map(\.id), [firstID, secondID, thirdID])
        XCTAssertEqual(portal.selectedTabID, secondID)
    }

    func testMovingTabsRejectsUnknownIDsAndBoundaryMoves() throws {
        var portal = try makePortal(path: "/tmp/first")
        let secondID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let firstID = portal.tabs[0].id
        let unknownID = FolderTabID(rawValue: UUID())
        let originalTabs = portal.tabs

        XCTAssertThrowsError(try portal.moveTab(unknownID, toward: .up)) { error in
            XCTAssertEqual(error as? PortalError, .tabNotFound(unknownID))
        }
        XCTAssertThrowsError(try portal.moveTab(firstID, toward: .up)) { error in
            XCTAssertEqual(error as? PortalError, .cannotMoveTab(firstID, .up))
        }
        XCTAssertThrowsError(try portal.moveTab(secondID, toward: .down)) { error in
            XCTAssertEqual(error as? PortalError, .cannotMoveTab(secondID, .down))
        }
        XCTAssertEqual(portal.tabs, originalTabs)
    }

    func testRemovingSelectedTabSelectsItsSuccessorOrPredecessor() throws {
        var portal = try makePortal(path: "/tmp/first")
        let secondID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let thirdID = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/third"))

        try portal.selectTab(secondID)
        try portal.removeTab(secondID)
        XCTAssertEqual(portal.selectedTabID, thirdID)

        try portal.removeTab(thirdID)
        XCTAssertEqual(portal.selectedTabID, portal.tabs[0].id)
    }

    func testTabOperationsRejectInvalidTargetsAndPreserveTheLastTab() throws {
        var portal = try makePortal(path: "/tmp/first")
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

    func testUserPlacementChangesHomeAndRetainsPriorDisplayEntry() throws {
        var portal = try makePortal(path: "/tmp/folder")
        let updatedFrame = CGRect(x: -10, y: 5, width: 640, height: 480)
        let secondDisplay = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "display-b"),
            visibleFrame: CGRect(x: -1200, y: 0, width: 1200, height: 800)
        )

        try portal.recordUserPlacement(frame: updatedFrame, display: secondDisplay)
        portal.updateIconSize(.large)

        XCTAssertEqual(portal.frame, updatedFrame)
        XCTAssertEqual(portal.placement.homeDisplay, secondDisplay.identity)
        XCTAssertEqual(Set(portal.placement.framesByDisplay.keys), [display.identity, secondDisplay.identity])
        XCTAssertEqual(
            portal.placement.framesByDisplay[secondDisplay.identity],
            portal.placement.homeEntry
        )
        XCTAssertEqual(portal.iconSize, .large)
    }

    func testBackgroundStyleDefaultsAndUpdatesPerPortal() throws {
        var portal = try makePortal(path: "/tmp/folder")
        XCTAssertEqual(portal.backgroundStyle, .standard)

        portal.updateBackgroundStyle(.highTransparency)

        XCTAssertEqual(portal.backgroundStyle, .highTransparency)
        XCTAssertEqual(
            PortalBackgroundStyle.allCases,
            [
                .maximumTransparency,
                .highTransparency,
                .standard,
                .lowTransparency,
                .minimumTransparency,
            ]
        )
        XCTAssertEqual(
            [
                PortalBackgroundStyle.maximumTransparency.rawValue,
                PortalBackgroundStyle.highTransparency.rawValue,
                PortalBackgroundStyle.standard.rawValue,
                PortalBackgroundStyle.lowTransparency.rawValue,
                PortalBackgroundStyle.minimumTransparency.rawValue,
            ],
            [
                "maximum_transparency",
                "high_transparency",
                "standard",
                "low_transparency",
                "minimum_transparency",
            ]
        )
    }

    func testGlobalBackgroundTypeHasStablePersistenceValues() {
        XCTAssertEqual(
            PortalBackgroundType.allCases.map(\.rawValue),
            ["liquid_glass", "frosted_glass"]
        )
    }

    func testPinnedStateDefaultsAndUpdatesIndependentlyOfPlacement() throws {
        var portal = try makePortal(path: "/tmp/folder")
        let placement = portal.placement

        XCTAssertFalse(portal.isPinned)
        portal.updatePinned(true)

        XCTAssertTrue(portal.isPinned)
        XCTAssertEqual(portal.placement, placement)
    }

    func testSortOrderAndTintDefaultAndUpdatePerPortal() throws {
        var portal = try makePortal(path: "/tmp/folder")

        XCTAssertEqual(portal.sortOrder, .name)
        XCTAssertEqual(portal.tint, .default)
        portal.updateSortOrder(.modificationDate)
        portal.updateTint(.purple)

        XCTAssertEqual(portal.sortOrder, .modificationDate)
        XCTAssertEqual(portal.tint, .purple)
        XCTAssertEqual(
            PortalSortOrder.allCases.map(\.rawValue),
            ["name", "modification_date", "creation_date"]
        )
        XCTAssertEqual(
            PortalTint.allCases.map(\.rawValue),
            ["default", "red", "orange", "yellow", "green", "blue", "indigo", "purple"]
        )
        XCTAssertNil(PortalTint.default.color)
        let lightDefault = PortalTint.default.resolvedColor(forDarkAppearance: false)
        XCTAssertEqual(lightDefault.red, 0.72)
        XCTAssertEqual(lightDefault.green, 0.72)
        XCTAssertEqual(lightDefault.blue, 0.72)
        let darkDefault = PortalTint.default.resolvedColor(forDarkAppearance: true)
        XCTAssertEqual(darkDefault.red, 0.18)
        XCTAssertEqual(darkDefault.green, 0.18)
        XCTAssertEqual(darkDefault.blue, 0.18)
        XCTAssertEqual(PortalTint.blue.color?.red, 0)
        XCTAssertEqual(PortalTint.blue.color?.green, 0.48)
        XCTAssertEqual(PortalTint.blue.color?.blue, 1)
    }

    func testIconLayoutSupportsOnlyAppSelectedSizes() throws {
        var portal = try makePortal(path: "/tmp/folder")

        XCTAssertEqual(portal.iconLayout, .fixed(.medium))
        XCTAssertEqual(portal.iconSize, .medium)
        XCTAssertEqual(portal.textSize, 12)

        portal.updateIconSize(.large)
        XCTAssertEqual(portal.iconLayout, .fixed(.large))
        XCTAssertEqual(portal.iconSize, .large)
        XCTAssertEqual(portal.textSize, 12)
    }

    func testGridCapacityDefaultsAndUpdatesIndependentlyOfPlacement() throws {
        var portal = try makePortal(path: "/tmp/folder")
        let capacity = try GridCapacity(columns: 5, rows: 2)

        XCTAssertEqual(portal.gridCapacity, .minimum)

        portal.updateGridCapacity(capacity)

        XCTAssertEqual(portal.gridCapacity, capacity)
        XCTAssertEqual(portal.frame, frame)
    }

    private func makePlacement() throws -> PlacementRecord {
        try PlacementRecord(frame: frame, display: display)
    }

    private func makePortal(path: String) throws -> Portal {
        try Portal(folderURL: URL(fileURLWithPath: path), frame: frame, display: display)
    }
}
