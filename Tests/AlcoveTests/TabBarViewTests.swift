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
        XCTAssertFalse(try XCTUnwrap(tabBar.tabButtons[tabs[1].id]).isBordered)
        XCTAssertNotNil(tabBar.tabButtons[tabs[1].id]?.layer?.backgroundColor)
    }

    @MainActor
    func testSingleTabShowsOnlyOneCapsuleAndFixedManagementButton() throws {
        let tab = makeTab(name: "Only")
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))

        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))
        tabBar.layoutSubtreeIfNeeded()

        XCTAssertEqual(tabBar.tabButtons.count, 1)
        XCTAssertEqual(tabBar.scrollView.documentView?.subviews.count, 1)
        XCTAssertEqual(tabBar.tabButtons[tab.id]?.title, "Only")
        XCTAssertTrue(tabBar.bounds.contains(managementButtonFrame(in: tabBar)))
        let tabButton = try XCTUnwrap(tabBar.tabButtons[tab.id])
        let tabFrame = tabButton.convert(tabButton.bounds, to: tabBar)
        XCTAssertGreaterThan(tabButton.bounds.width, 0)
        XCTAssertGreaterThan(tabButton.bounds.height, 0)
        XCTAssertTrue(tabButton.isDescendant(of: tabBar.scrollView))
        XCTAssertEqual(tabBar.scrollView.frame.midX, tabBar.bounds.midX, accuracy: 0.5)
        XCTAssertTrue(
            tabBar.bounds.contains(tabFrame),
            "Expected visible tab frame; strip=\(tabBar.scrollView.frame), tab=\(tabFrame)"
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
    func testFolderSettingsExposeIndependentNavigationAndForwardFolderActions() throws {
        let tabBar = TabBarView(frame: .zero)
        let first = makeTab(name: "First")
        let second = makeTab(name: "Second")
        let third = makeTab(name: "Third")
        tabBar.configure(with: try makePortal(
            tabs: [first, second, third],
            selected: first.id
        ))
        var addCount = 0
        var closedIDs: [FolderTabID] = []
        var moveRequests: [(FolderTabID, Int)] = []
        tabBar.onAdd = { addCount += 1 }
        tabBar.onClose = { closedIDs.append($0) }
        tabBar.onMoveTab = { moveRequests.append(($0, $1)) }
        defer { tabBar.closeSettingsWindow() }

        let settingsController = try settingsController(in: tabBar)
        let settingsViewController = settingsController.settingsViewController
        let settingsRoot = settingsViewController.view
        settingsRoot.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            Set(settingsController.categoryItems.keys),
            [.general, .folders, .style]
        )
        XCTAssertEqual(settingsViewController.selectedCategory, .general)
        XCTAssertEqual(
            settingsController.window?.toolbar?.selectedItemIdentifier,
            PortalSettingsViewController.Category.general.toolbarItemIdentifier
        )

        settingsController.selectCategory(.folders)

        let addButton = try settingsButton(
            titled: NSLocalizedString("portal.settings.add_folder", comment: ""),
            in: tabBar
        )
        XCTAssertTrue(addButton.isBordered)
        XCTAssertEqual(addButton.bezelColor, .controlAccentColor)
        XCTAssertEqual(addButton.controlSize, .regular)
        XCTAssertTrue(addButton.imageHugsTitle)
        XCTAssertEqual(
            addButton.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil)
                as? NSColor,
            .alternateSelectedControlTextColor
        )
        if #available(macOS 26.0, *) {
            XCTAssertEqual(addButton.bezelStyle, .glass)
            XCTAssertEqual(addButton.tintProminence, .primary)
            XCTAssertEqual(addButton.borderShape, .capsule)
        }
        addButton.performClick(nil)
        settingsViewController.reorderFolder(first.id, to: 2)
        try folderActionButton(
            labeled: NSLocalizedString("portal.settings.remove_folder_action", comment: ""),
            for: "Third",
            in: tabBar
        ).performClick(nil)
        XCTAssertEqual(addCount, 1)
        XCTAssertEqual(closedIDs, [third.id])
        XCTAssertEqual(moveRequests.count, 1)
        XCTAssertEqual(moveRequests[0].0, first.id)
        XCTAssertEqual(moveRequests[0].1, 2)
        XCTAssertEqual(
            tabBar.managementButton.accessibilityLabel(),
            NSLocalizedString("portal.settings.label", comment: "")
        )
        XCTAssertNotNil(tabBar.managementButton.image)
        let settingsWindow = try XCTUnwrap(settingsController.window)
        XCTAssertEqual(settingsWindow.contentView?.bounds.size, NSSize(width: 400, height: 450))
        XCTAssertEqual(settingsWindow.toolbarStyle, .preference)
        XCTAssertEqual(settingsWindow.toolbar?.displayMode, .iconAndLabel)
        XCTAssertNotNil(settingsWindow.toolbar)
        XCTAssertEqual(settingsWindow.titleVisibility, .visible)
        XCTAssertEqual(settingsWindow.title, "")
        XCTAssertEqual(settingsWindow.titlebarSeparatorStyle, .none)
        XCTAssertTrue(settingsViewController.contentSeparator.superview === settingsRoot)
        XCTAssertEqual(settingsViewController.contentSeparator.boxType, .separator)
        XCTAssertTrue(settingsWindow.titlebarAppearsTransparent)
        XCTAssertTrue(settingsWindow.styleMask.contains(.titled))
        XCTAssertTrue(settingsWindow.styleMask.contains(.closable))
        if let visibleFrame = settingsWindow.screen?.visibleFrame {
            XCTAssertEqual(settingsWindow.frame.midX, visibleFrame.midX, accuracy: 0.5)
            XCTAssertEqual(settingsWindow.frame.midY, visibleFrame.midY, accuracy: 0.5)
        }
        XCTAssertFalse(
            try XCTUnwrap(settingsWindow.standardWindowButton(.closeButton)).isHidden
        )
        XCTAssertTrue(
            try XCTUnwrap(settingsWindow.standardWindowButton(.miniaturizeButton)).isHidden
        )
        XCTAssertTrue(
            try XCTUnwrap(settingsWindow.standardWindowButton(.zoomButton)).isHidden
        )

        settingsRoot.layoutSubtreeIfNeeded()
        XCTAssertEqual(settingsViewController.contentStack.frame.minX, 20, accuracy: 0.5)
        XCTAssertEqual(
            settingsViewController.contentStack.frame.width,
            settingsViewController.scrollView.contentSize.width - 40,
            accuracy: 0.5
        )
        let cards = settingsViewController.contentStack.arrangedSubviews.enumerated()
            .compactMap { index, view in index.isMultiple(of: 2) ? nil : view }
        for card in cards {
            XCTAssertEqual(
                card.frame.width,
                settingsViewController.contentStack.frame.width,
                accuracy: 0.5
            )
            card.updateLayer()
            XCTAssertEqual(
                card.layer?.backgroundColor,
                NSColor.quaternarySystemFill.cgColor
            )
        }
        let folderList = try XCTUnwrap(settingsViewController.folderListView)
        XCTAssertEqual(folderList.tableView.numberOfRows, 3)
        XCTAssertEqual(folderList.tableView.draggingDestinationFeedbackStyle, .gap)
        XCTAssertEqual(folderList.tableView.gridStyleMask, [])
        XCTAssertNotNil(folderList.tableView.dataSource?.tableView?(
            folderList.tableView,
            pasteboardWriterForRow: 0
        ))
        let firstFolderRow = try XCTUnwrap(
            folderList.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true)
        )
        XCTAssertEqual(folderList.tableView.effectiveStyle, .plain)
        XCTAssertEqual(folderList.tableView.frame.height, folderList.contentView.bounds.height)
        XCTAssertEqual(firstFolderRow.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(firstFolderRow.frame.width, folderList.tableView.bounds.width, accuracy: 0.5)
        XCTAssertNotNil(descendants(of: firstFolderRow).first {
            $0.identifier?.rawValue == "portal-settings.folder-row-separator"
        })
        let lastFolderRow = try XCTUnwrap(
            folderList.tableView.view(atColumn: 0, row: 2, makeIfNecessary: true)
        )
        XCTAssertNil(descendants(of: lastFolderRow).first {
            $0.identifier?.rawValue == "portal-settings.folder-row-separator"
        })
        let firstFolderCard = try XCTUnwrap(cards.first)
        let folderListFrame = folderList.convert(folderList.bounds, to: firstFolderCard)
        XCTAssertEqual(folderListFrame.minX, 10, accuracy: 0.5)
        XCTAssertEqual(folderListFrame.maxX, firstFolderCard.bounds.maxX - 10, accuracy: 0.5)
        XCTAssertTrue(
            descendants(of: firstFolderRow).compactMap { $0 as? NSTextField }
                .contains { $0.stringValue == "/tmp/First" }
        )
        let dragHandle = try XCTUnwrap(
            descendants(of: firstFolderRow).first {
                $0.accessibilityLabel() == NSLocalizedString(
                    "portal.settings.reorder_folder",
                    comment: ""
                )
            }
        )
        let removeFolder = try folderActionButton(
            labeled: NSLocalizedString("portal.settings.remove_folder_action", comment: ""),
            for: "First",
            in: tabBar
        )
        let dragFrame = dragHandle.convert(dragHandle.bounds, to: firstFolderRow)
        let removeFrame = removeFolder.convert(removeFolder.bounds, to: firstFolderRow)
        XCTAssertLessThanOrEqual(dragFrame.maxX, removeFrame.minX)
        XCTAssertEqual(removeFrame.maxX, firstFolderRow.bounds.maxX, accuracy: 0.5)
        XCTAssertFalse(removeFolder.isBordered)
        XCTAssertNil(
            descendants(of: settingsRoot).compactMap { $0 as? NSTextField }.first {
                $0.stringValue == NSLocalizedString(
                    "portal.settings.remove_portal_detail",
                    comment: ""
                )
            }
        )
    }

    @MainActor
    func testFolderSettingsShowGuidanceRowForAnEmptyPortal() throws {
        let tabBar = TabBarView(frame: .zero)
        let portal = try Portal(
            frame: NSRect(x: 0, y: 0, width: 300, height: 200),
            display: DisplayDescriptor(
                identity: DisplayIdentity(rawValue: "test-display"),
                visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
            )
        )
        tabBar.configure(with: portal)
        defer { tabBar.closeSettingsWindow() }

        let settings = try settingsController(in: tabBar).settingsViewController
        settings.selectCategory(.folders)
        let emptyRow = try XCTUnwrap(
            descendants(of: settings.view)
                .compactMap { $0 as? PortalSettingsEmptyFolderRowView }
                .first
        )

        XCTAssertNil(settings.folderListView)
        XCTAssertEqual(emptyRow.frame.height, 44, accuracy: 0.5)
        XCTAssertEqual(
            emptyRow.accessibilityLabel(),
            NSLocalizedString("portal.settings.folders.empty", comment: "")
        )
    }

    @MainActor
    func testStyleCategoryDoesNotExposeGlobalContentOrTransparencyControls() throws {
        let tab = makeTab(name: "First")
        var portal = try makePortal(tabs: [tab], selected: tab.id)
        portal.updateBackgroundStyle(.lowTransparency)
        let tabBar = TabBarView(frame: .zero)
        defer { tabBar.closeSettingsWindow() }

        tabBar.configure(with: portal)

        try selectCategory(.style, in: tabBar)
        let settingsViewController = try settingsController(in: tabBar).settingsViewController
        settingsViewController.view.layoutSubtreeIfNeeded()
        let identifiers = descendants(of: settingsViewController.view)
            .compactMap(\.identifier?.rawValue)
        XCTAssertFalse(identifiers.contains("portal-settings.background"))
        XCTAssertFalse(identifiers.contains("portal-settings.icon-size"))
        XCTAssertTrue(identifiers.contains("portal-settings.tint"))
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
        let sortMenu = try XCTUnwrap(menu.items[1].submenu)
        XCTAssertEqual(sortMenu.items.count, 3)
        XCTAssertEqual(sortMenu.items.map(\.state), [.off, .on, .off])
        XCTAssertEqual(menu.items[2].title, NSLocalizedString("portal.settings.open", comment: ""))
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
    func testGeneralAndStyleSettingsForwardPortalPreferences() throws {
        let tab = makeTab(name: "First")
        var portal = try makePortal(tabs: [tab], selected: tab.id)
        portal.updateSortOrder(.creationDate)
        portal.updateTint(.green)
        let tabBar = TabBarView(frame: .zero)
        var sortOrders: [PortalSortOrder] = []
        var tints: [PortalTint] = []
        tabBar.onSetSortOrder = { sortOrders.append($0) }
        tabBar.onSetTint = { tints.append($0) }
        tabBar.configure(with: portal)
        defer { tabBar.closeSettingsWindow() }

        let settings = try settingsController(in: tabBar).settingsViewController
        let sortPopUp = try XCTUnwrap(settings.sortPopUpButton)
        XCTAssertEqual(sortPopUp.indexOfSelectedItem, 2)
        sortPopUp.selectItem(at: 0)
        NSApp.sendAction(try XCTUnwrap(sortPopUp.action), to: sortPopUp.target, from: sortPopUp)

        settings.selectCategory(.style)
        let tintPopUp = try XCTUnwrap(settings.tintPopUpButton)
        XCTAssertEqual(tintPopUp.indexOfSelectedItem, 4)
        tintPopUp.selectItem(at: 5)
        NSApp.sendAction(try XCTUnwrap(tintPopUp.action), to: tintPopUp.target, from: tintPopUp)

        XCTAssertEqual(sortOrders, [.name])
        XCTAssertEqual(tints, [.blue])
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
        XCTAssertEqual(tabBar.scrollView.documentView?.subviews.count, 2)
    }

    @MainActor
    func testManyTabsRemainReachableThroughHorizontalScrolling() throws {
        let tabs = (0..<12).map { makeTab(name: "Folder-\($0)") }
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

        let documentView = try XCTUnwrap(tabBar.scrollView.documentView)
        XCTAssertTrue(tabBar.scrollView.hasHorizontalScroller)
        XCTAssertGreaterThan(documentView.frame.width, tabBar.scrollView.contentSize.width)
        let maximumOriginX = documentView.frame.width - tabBar.scrollView.contentSize.width
        tabBar.scrollView.contentView.scroll(to: NSPoint(x: maximumOriginX, y: 0))
        tabBar.scrollView.reflectScrolledClipView(tabBar.scrollView.contentView)
        let lastButton = try XCTUnwrap(tabBar.tabButtons[tabs[11].id])
        let lastFrame = lastButton.convert(lastButton.bounds, to: tabBar.scrollView.contentView)
        XCTAssertTrue(tabBar.scrollView.contentView.bounds.contains(lastFrame))
        XCTAssertTrue(tabBar.bounds.contains(managementButtonFrame(in: tabBar)))
        XCTAssertEqual(tabBar.scrollView.frame.midX, tabBar.bounds.midX, accuracy: 0.5)
    }

    @MainActor
    func testTabStripHasNoOuterMaterialCapsule() throws {
        let tab = makeTab(name: "Only")
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))

        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))

        XCTAssertTrue(
            tabBar.subviews.compactMap { $0 as? PortalChromeMaterialView }.isEmpty
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(tabBar.tabButtons[tab.id]).layer?.backgroundColor?.alpha ?? 0,
            0
        )
    }

    @MainActor
    func testTabAndMenuLabelsStayFullyVisibleInANonKeyWindow() throws {
        let tab = makeTab(name: "Only")
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = tabBar

        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))
        tabBar.layoutSubtreeIfNeeded()

        XCTAssertFalse(window.isKeyWindow)
        let tabButton = try XCTUnwrap(tabBar.tabButtons[tab.id])
        let tabColor = try XCTUnwrap(
            tabButton.attributedTitle.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        )
        let menuColor = try XCTUnwrap(tabBar.managementButton.contentTintColor)
        XCTAssertEqual(tabColor.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(menuColor.alphaComponent, 1, accuracy: 0.01)
        XCTAssertGreaterThan(tabButton.layer?.backgroundColor?.alpha ?? 0, 0)
    }

    @MainActor
    private func managementButtonFrame(in tabBar: TabBarView) -> NSRect {
        tabBar.managementButton.convert(tabBar.managementButton.bounds, to: tabBar)
    }

    @MainActor
    private func settingsController(
        in tabBar: TabBarView
    ) throws -> PortalSettingsWindowController {
        if tabBar.settingsWindowController == nil {
            tabBar.showSettingsWindow()
        }
        return try XCTUnwrap(tabBar.settingsWindowController)
    }

    @MainActor
    private func settingsRoot(in tabBar: TabBarView) throws -> NSView {
        try settingsController(in: tabBar).settingsViewController.view
    }

    @MainActor
    private func settingsButton(titled title: String, in tabBar: TabBarView) throws -> NSButton {
        try XCTUnwrap(
            descendants(of: try settingsRoot(in: tabBar))
                .compactMap { $0 as? NSButton }
                .first { $0.title == title }
        )
    }

    @MainActor
    private func selectCategory(
        _ category: PortalSettingsViewController.Category,
        in tabBar: TabBarView
    ) throws {
        try settingsController(in: tabBar).selectCategory(category)
    }

    @MainActor
    private func slider(identifier: String, in tabBar: TabBarView) throws -> NSSlider {
        try XCTUnwrap(
            descendants(of: try settingsRoot(in: tabBar))
                .compactMap { $0 as? NSSlider }
                .first { $0.identifier?.rawValue == identifier }
        )
    }

    @MainActor
    private func folderActionButton(
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
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }

    private func makeTab(name: String) -> FolderTab {
        FolderTab(folderURL: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    private func makePortal(tabs: [FolderTab], selected: FolderTabID) throws -> Portal {
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
