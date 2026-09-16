import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

final class TabBarViewTests: XCTestCase {
    func testRemovalConfirmationCentersInThePortalScreensVisibleFrame() {
        let visibleFrame = NSRect(x: 1440, y: 38, width: 1920, height: 1042)
        let windowSize = NSSize(width: 520, height: 278)

        let origin = PortalRemovalConfirmationGeometry.centeredOrigin(
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )
        let alertFrame = NSRect(origin: origin, size: windowSize)

        XCTAssertEqual(alertFrame.midX, visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(alertFrame.midY, visibleFrame.midY, accuracy: 0.5)
    }

    @MainActor
    func testConfigureDisplaysTabsInCreationOrderAndMarksSelectedTab() throws {
        let tabs = [
            makeTab(name: "First"),
            makeTab(name: "Second"),
            makeTab(name: "Third"),
        ]
        let portal = try makePortal(tabs: tabs, selected: tabs[1].id)
        let tabBar = TabBarView(frame: .zero)
        tabBar.appearance = NSAppearance(named: .aqua)

        tabBar.configure(with: portal)

        XCTAssertEqual(tabBar.tabOrder, tabs.map(\.id))
        XCTAssertEqual(tabBar.selectedTabID, tabs[1].id)
        XCTAssertEqual(tabBar.tabButtons[tabs[0].id]?.title, "First")
        XCTAssertEqual(tabBar.tabButtons[tabs[1].id]?.isTabSelected, true)
        XCTAssertEqual(tabBar.tabButtons[tabs[2].id]?.isTabSelected, false)
        XCTAssertEqual(tabBar.tabButtons[tabs[1].id]?.accessibilityRole(), .radioButton)
        XCTAssertEqual(
            (tabBar.tabButtons[tabs[1].id]?.accessibilityValue() as? NSNumber)?.boolValue,
            true
        )
        XCTAssertEqual(
            (tabBar.tabButtons[tabs[2].id]?.accessibilityValue() as? NSNumber)?.boolValue,
            false
        )
        let selectedButton = try XCTUnwrap(tabBar.tabButtons[tabs[1].id])
        XCTAssertFalse(selectedButton.isBordered)
        XCTAssertTrue(selectedButton.usesSelectedAppearance)
        XCTAssertNotNil(selectedButton.layer?.backgroundColor)
        let selectedTitleColor = try XCTUnwrap(
            selectedButton.attributedTitle.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertEqual(selectedTitleColor, .black)
        XCTAssertEqual(selectedButton.layer?.borderWidth, 0.75)
        XCTAssertEqual(selectedButton.layer?.shadowOpacity, 0)
    }

    @MainActor
    func testTabCapsulesAreEqualAndScaleWithGlobalContentSize() throws {
        let tabs = [makeTab(name: "A"), makeTab(name: "Much Longer Folder")]
        var portal = try makePortal(tabs: tabs, selected: tabs[0].id)
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 40))

        tabBar.configure(with: portal)
        let mediumSizes = tabs.compactMap { tabBar.tabButtons[$0.id]?.intrinsicContentSize }

        XCTAssertEqual(mediumSizes, [
            NSSize(width: 64, height: 28),
            NSSize(width: 64, height: 28),
        ])
        XCTAssertEqual(tabBar.backButton.intrinsicContentSize.height, 28)
        XCTAssertTrue(tabBar.backButton.imageHugsTitle)
        XCTAssertFalse(tabBar.backButton.isBordered)
        XCTAssertEqual(tabBar.backButton.layer?.shadowOpacity, 0)

        portal.updateIconSize(.large)
        tabBar.update(with: portal)
        let largeSizes = tabs.compactMap { tabBar.tabButtons[$0.id]?.intrinsicContentSize }

        XCTAssertEqual(largeSizes, [
            NSSize(width: 72, height: 30),
            NSSize(width: 72, height: 30),
        ])
        XCTAssertEqual(tabBar.backButton.intrinsicContentSize.height, 30)

        portal.updateIconSize(.small)
        tabBar.update(with: portal)
        let smallSizes = tabs.compactMap { tabBar.tabButtons[$0.id]?.intrinsicContentSize }

        XCTAssertEqual(smallSizes, [
            NSSize(width: 56, height: 26),
            NSSize(width: 56, height: 26),
        ])
        XCTAssertEqual(tabBar.backButton.intrinsicContentSize.height, 26)
    }

    @MainActor
    func testSingleTabShowsOnlyOneCapsuleAndFixedManagementButton() throws {
        let tab = makeTab(name: "Only")
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))

        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))
        tabBar.layoutSubtreeIfNeeded()

        XCTAssertEqual(tabBar.tabButtons.count, 1)
        XCTAssertNotNil(tabBar.scrollView.documentView)
        XCTAssertFalse(tabBar.scrollView.hasHorizontalScroller)
        XCTAssertEqual(tabBar.scrollView.frame.height, 32, accuracy: 0.5)
        XCTAssertEqual(tabBar.scrollView.frame.midY, tabBar.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(tabBar.tabButtons[tab.id]?.title, "Only")
        XCTAssertTrue(tabBar.bounds.contains(managementButtonFrame(in: tabBar)))
        let tabButton = try XCTUnwrap(tabBar.tabButtons[tab.id])
        let tabFrame = tabButton.convert(tabButton.bounds, to: tabBar)
        XCTAssertGreaterThan(tabButton.bounds.width, 0)
        XCTAssertGreaterThan(tabButton.bounds.height, 0)
        XCTAssertTrue(tabButton.isDescendant(of: tabBar.scrollView))
        XCTAssertTrue(tabButton.isDescendant(of: tabBar))
        XCTAssertFalse(tabBar.scrollView.drawsBackground)
        XCTAssertFalse(tabBar.scrollView.contentView.drawsBackground)
        XCTAssertEqual(tabBar.scrollView.backgroundColor, .clear)
        XCTAssertEqual(tabBar.scrollView.contentView.backgroundColor, .clear)
        XCTAssertTrue(
            tabBar.bounds.contains(tabFrame),
            "Expected visible tab frame; tab=\(tabFrame)"
        )
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
        defer { tabBar.closeSettingsWindow() }
        try selectCategory(.folders, in: tabBar)

        tabBar.tabButtons[second.id]?.performClick(nil)
        try folderActionButton(
            labeled: NSLocalizedString("portal.settings.remove_folder_action", comment: ""),
            for: "First",
            in: tabBar
        ).performClick(nil)

        XCTAssertEqual(selectedID, second.id)
        XCTAssertEqual(closedID, first.id)
        XCTAssertEqual(tabBar.selectedTabID, first.id)

        tabBar.update(with: try makePortal(tabs: [first, second], selected: second.id))
        XCTAssertEqual(tabBar.selectedTabID, second.id)
        XCTAssertNotNil(try? folderActionButton(
            labeled: NSLocalizedString("portal.settings.remove_folder_action", comment: ""),
            for: "Second",
            in: tabBar
        ))
    }

    @MainActor
    func testManagementMenuExposesPinSortSettingsAndConfirmedDelete() throws {
        let tab = makeTab(name: "First")
        var portal = try makePortal(tabs: [tab], selected: tab.id)
        portal.updateSortOrder(.modificationDate)
        let tabBar = TabBarView(frame: .zero)
        var pinnedStates: [Bool] = []
        var sortOrders: [PortalSortOrder] = []
        var removeCount = 0
        tabBar.onSetPinned = { pinnedStates.append($0) }
        tabBar.onSetSortOrder = { sortOrders.append($0) }
        tabBar.onRemovePortal = { removeCount += 1 }
        tabBar.configure(with: portal)

        let menu = tabBar.makeManagementMenu()
        XCTAssertEqual(menu.items.count, 5)
        XCTAssertEqual(menu.items[0].title, NSLocalizedString("portal.pin.pin", comment: ""))
        XCTAssertNotNil(menu.items[0].image)
        let sortMenu = try XCTUnwrap(menu.items[1].submenu)
        XCTAssertEqual(sortMenu.items.count, 3)
        XCTAssertEqual(sortMenu.items.map(\.state), [.off, .on, .off])
        XCTAssertNotNil(menu.items[1].image)
        XCTAssertEqual(menu.items[2].title, NSLocalizedString("portal.settings.open", comment: ""))
        XCTAssertNotNil(menu.items[2].image)
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(menu.items[4].title, NSLocalizedString("portal.remove.menu", comment: ""))

        menu.performActionForItem(at: 0)
        sortMenu.performActionForItem(at: 2)
        tabBar.removalConfirmationPresenter = { _, completion in completion(false) }
        menu.performActionForItem(at: 4)
        tabBar.removalConfirmationPresenter = { _, completion in completion(true) }
        menu.performActionForItem(at: 4)

        XCTAssertEqual(pinnedStates, [true])
        XCTAssertEqual(sortOrders, [.creationDate])
        XCTAssertEqual(removeCount, 1)
    }

    @MainActor
    func testRepeatedConfigureDoesNotDuplicateControlsOrReorderTabs() throws {
        let first = makeTab(name: "First")
        let second = makeTab(name: "Second")
        let portal = try makePortal(tabs: [first, second], selected: second.id)
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 360, height: 40))

        tabBar.configure(with: portal)
        tabBar.update(with: portal)
        tabBar.layoutSubtreeIfNeeded()

        XCTAssertEqual(tabBar.tabOrder, [first.id, second.id])
        XCTAssertEqual(tabBar.tabButtons.count, 2)
        XCTAssertNotNil(tabBar.scrollView.documentView)
        XCTAssertFalse(tabBar.scrollView.hasHorizontalScroller)
    }

    @MainActor
    func testFourTabsCompressEquallyWithoutHorizontalScrolling() throws {
        let tabs = (0..<Portal.maximumTabCount).map { makeTab(name: "Folder-\($0)") }
        let portal = try makePortal(tabs: tabs, selected: tabs[0].id)
        let tabBar = TabBarView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 240,
                height: PortalViewController.tabBarHeight
            )
        )
        tabBar.configure(with: portal)
        tabBar.layoutSubtreeIfNeeded()

        XCTAssertFalse(tabBar.scrollView.hasHorizontalScroller)
        let documentView = try XCTUnwrap(tabBar.scrollView.documentView)
        XCTAssertEqual(documentView.frame.width, tabBar.scrollView.contentSize.width, accuracy: 0.5)
        let widths = tabs.compactMap { tabBar.tabButtons[$0.id]?.frame.width }
        XCTAssertEqual(widths.count, Portal.maximumTabCount)
        XCTAssertTrue(widths.allSatisfy { abs($0 - (widths.first ?? 0)) < 0.5 })
        XCTAssertLessThan(try XCTUnwrap(widths.first), 64)
        for tab in tabs {
            let button = try XCTUnwrap(tabBar.tabButtons[tab.id])
            XCTAssertEqual((button.cell as? NSButtonCell)?.lineBreakMode, .byTruncatingTail)
            XCTAssertEqual(button.toolTip, button.title)
            let frame = button.convert(button.bounds, to: tabBar.scrollView.contentView)
            XCTAssertTrue(tabBar.scrollView.contentView.bounds.contains(frame))
        }
        XCTAssertTrue(tabBar.bounds.contains(managementButtonFrame(in: tabBar)))
        XCTAssertEqual(tabBar.scrollView.frame.midX, tabBar.bounds.midX, accuracy: 0.5)

        let groupFrameWithoutBack = tabBar.scrollView.frame
        tabBar.updateNavigation(canGoBack: true)
        tabBar.layoutSubtreeIfNeeded()
        XCTAssertEqual(tabBar.scrollView.frame, groupFrameWithoutBack)
    }

    @MainActor
    func testTabStripUsesOneFlatOuterCapsule() throws {
        let tab = makeTab(name: "Only")
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))

        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))

        XCTAssertTrue(
            tabBar.subviews.compactMap { $0 as? PortalChromeMaterialView }.isEmpty
        )
        let group = try XCTUnwrap(tabBar.scrollView.documentView)
        XCTAssertFalse(group.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(group.layer?.shadowOpacity, 0)
        XCTAssertEqual(group.layer?.borderWidth, 0.5)
        XCTAssertGreaterThan(group.layer?.backgroundColor?.alpha ?? 0, 0)
        let tabButton = try XCTUnwrap(tabBar.tabButtons[tab.id])
        XCTAssertFalse(tabButton.isBordered)
        XCTAssertEqual(tabButton.layer?.shadowOpacity, 0)
        XCTAssertGreaterThan(tabButton.layer?.backgroundColor?.alpha ?? 0, 0)
    }

    @MainActor
    func testTabAndMenuLabelsStayFullyVisibleInANonKeyWindow() throws {
        let tab = makeTab(name: "Selected")
        let otherTab = makeTab(name: "Other")
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        tabBar.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = tabBar

        tabBar.configure(with: try makePortal(tabs: [tab, otherTab], selected: tab.id))
        tabBar.updateNavigation(canGoBack: true)
        tabBar.layoutSubtreeIfNeeded()

        XCTAssertFalse(window.isKeyWindow)
        let tabButton = try XCTUnwrap(tabBar.tabButtons[tab.id])
        let menuColor = try XCTUnwrap(tabBar.managementButton.contentTintColor)
        XCTAssertEqual(menuColor.alphaComponent, 1, accuracy: 0.01)
        let tabColor = try XCTUnwrap(
            tabButton.attributedTitle.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertFalse(tabButton.isBordered)
        XCTAssertEqual(tabColor, .black)
        XCTAssertEqual(tabButton.layer?.borderWidth, 0.75)
        XCTAssertGreaterThan(tabButton.layer?.backgroundColor?.alpha ?? 0, 0)
        let otherButton = try XCTUnwrap(tabBar.tabButtons[otherTab.id])
        let otherTitleColor = try XCTUnwrap(
            otherButton.attributedTitle.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        )
        let backTitleColor = try XCTUnwrap(
            tabBar.backButton.attributedTitle.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertEqual(otherTitleColor, .black)
        XCTAssertEqual(tabBar.backButton.contentTintColor, .black)
        XCTAssertEqual(backTitleColor, .black)
    }

    @MainActor
    func managementButtonFrame(in tabBar: TabBarView) -> NSRect {
        tabBar.managementButton.convert(tabBar.managementButton.bounds, to: tabBar)
    }

    @MainActor
    func settingsController(
        in tabBar: TabBarView
    ) throws -> PortalSettingsWindowController {
        if tabBar.settingsWindowController == nil {
            tabBar.showSettingsWindow()
        }
        return try XCTUnwrap(tabBar.settingsWindowController)
    }

    @MainActor
    func settingsRoot(in tabBar: TabBarView) throws -> NSView {
        try settingsController(in: tabBar).settingsViewController.view
    }

    @MainActor
    func settingsButton(titled title: String, in tabBar: TabBarView) throws -> NSButton {
        try XCTUnwrap(
            descendants(of: try settingsRoot(in: tabBar))
                .compactMap { $0 as? NSButton }
                .first { $0.title == title }
        )
    }

    @MainActor
    func selectCategory(
        _ category: PortalSettingsViewController.Category,
        in tabBar: TabBarView
    ) throws {
        try settingsController(in: tabBar).selectCategory(category)
    }

    @MainActor
    func slider(identifier: String, in tabBar: TabBarView) throws -> NSSlider {
        try XCTUnwrap(
            descendants(of: try settingsRoot(in: tabBar))
                .compactMap { $0 as? NSSlider }
                .first { $0.identifier?.rawValue == identifier }
        )
    }

    @MainActor
    func folderActionButton(
        labeled label: String,
        for folderName: String,
        in tabBar: TabBarView
    ) throws -> NSButton {
        let pathLabel = try XCTUnwrap(
            descendants(of: try settingsRoot(in: tabBar)).compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "/tmp/\(folderName)" }
        )
        var container = pathLabel.superview
        while let view = container {
            if let button = descendants(of: view).compactMap({ $0 as? NSButton }).first(where: {
                $0.accessibilityLabel() == label
            }) {
                return button
            }
            container = view.superview
        }
        throw TestError.missingFolderAction
    }

    @MainActor
    func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }

    func makeTab(name: String) -> FolderTab {
        FolderTab(folderURL: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    func makePortal(tabs: [FolderTab], selected: FolderTabID) throws -> Portal {
        try Portal(
            tabs: tabs,
            selectedTabID: selected,
            placement: try PlacementRecord(
                frame: NSRect(x: 0, y: 0, width: 300, height: 200),
                display: DisplayDescriptor(
                    identity: DisplayIdentity(rawValue: "test-display"),
                    visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
                )
            )
        )
    }

    private enum TestError: Error {
        case missingFolderAction
    }
}
