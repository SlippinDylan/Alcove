import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

final class TabBarViewTests: XCTestCase {
    @MainActor
    func testConfigureDisplaysTabsInCreationOrderAndMarksSelectedTab() throws {
        let tabs = [
            makeTab(name: "First"),
            makeTab(name: "Second"),
            makeTab(name: "Third"),
        ]
        let portal = try makePortal(tabs: tabs, selected: tabs[1].id)
        let tabBar = TabBarView(frame: .zero)

        tabBar.configure(with: portal)

        XCTAssertEqual(tabBar.tabOrder, tabs.map(\.id))
        XCTAssertEqual(tabBar.selectedTabID, tabs[1].id)
        XCTAssertEqual(tabBar.tabButtons[tabs[0].id]?.title, "First")
        XCTAssertEqual(tabBar.tabButtons[tabs[1].id]?.state, .on)
        XCTAssertEqual(tabBar.tabButtons[tabs[2].id]?.state, .off)
    }

    @MainActor
    func testSelectingAndClosingTabPassesTheFullFolderTabIDToCallbacks() throws {
        let first = makeTab(name: "First")
        let second = makeTab(name: "Second")
        let portal = try makePortal(tabs: [first, second], selected: first.id)
        let tabBar = TabBarView(frame: .zero)
        var selectedID: FolderTabID?
        var closedID: FolderTabID?
        tabBar.onSelect = { selectedID = $0 }
        tabBar.onClose = { closedID = $0 }
        tabBar.configure(with: portal)

        tabBar.tabButtons[second.id]?.performClick(nil)
        tabBar.closeButtons[first.id]?.performClick(nil)

        XCTAssertEqual(selectedID, second.id)
        XCTAssertEqual(closedID, first.id)
        XCTAssertEqual(tabBar.selectedTabID, first.id)

        tabBar.update(with: try makePortal(tabs: [first, second], selected: second.id))
        XCTAssertEqual(tabBar.selectedTabID, second.id)
    }

    @MainActor
    func testAddButtonInvokesCallbackAndExposesAccessibilityLabel() throws {
        let tabBar = TabBarView(frame: .zero)
        let tab = makeTab(name: "First")
        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))
        var addCount = 0
        tabBar.onAdd = { addCount += 1 }

        tabBar.addButton?.performClick(nil)

        XCTAssertEqual(addCount, 1)
        XCTAssertEqual(tabBar.addButton?.accessibilityLabel(), "Add tab")
    }

    @MainActor
    func testRepeatedConfigureDoesNotDuplicateControlsOrReorderTabs() throws {
        let first = makeTab(name: "First")
        let second = makeTab(name: "Second")
        let portal = try makePortal(tabs: [first, second], selected: second.id)
        let tabBar = TabBarView(frame: .zero)

        tabBar.configure(with: portal)
        tabBar.update(with: portal)

        XCTAssertEqual(tabBar.tabOrder, [first.id, second.id])
        XCTAssertEqual(tabBar.tabButtons.count, 2)
        XCTAssertEqual(tabBar.closeButtons.count, 2)
        XCTAssertEqual(tabBar.subviews.first?.subviews.count, 3)
    }

    private func makeTab(name: String) -> FolderTab {
        FolderTab(folderURL: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    private func makePortal(tabs: [FolderTab], selected: FolderTabID) throws -> Portal {
        try Portal(
            tabs: tabs,
            selectedTabID: selected,
            frame: NSRect(x: 0, y: 0, width: 300, height: 200)
        )
    }
}
