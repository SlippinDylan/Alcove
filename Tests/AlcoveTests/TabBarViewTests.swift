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
        XCTAssertTrue(addButton.isEnabled)
        XCTAssertTrue(settingsViewController.addFolderButton === addButton)
        XCTAssertNotNil(descendants(of: settingsRoot).first {
            $0.identifier?.rawValue == "portal-settings.folder-limit"
        })
        XCTAssertEqual(
            addButton.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil)
                as? NSColor,
            .alternateSelectedControlTextColor
        )
        XCTAssertEqual(addButton.bezelStyle, .glass)
        XCTAssertEqual(addButton.tintProminence, .primary)
        XCTAssertEqual(addButton.borderShape, .capsule)
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
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        let portal = try Portal(
            frame: NSRect(x: 0, y: 0, width: 300, height: 200),
            display: DisplayDescriptor(
                identity: DisplayIdentity(rawValue: "test-display"),
                visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
            )
        )
        tabBar.configure(with: portal)
        tabBar.layoutSubtreeIfNeeded()
        defer { tabBar.closeSettingsWindow() }

        let settings = try settingsController(in: tabBar).settingsViewController
        settings.selectCategory(.folders)
        let emptyRow = try XCTUnwrap(
            descendants(of: settings.view)
                .compactMap { $0 as? PortalSettingsEmptyFolderRowView }
                .first
        )

        XCTAssertNil(settings.folderListView)
        XCTAssertTrue(tabBar.scrollView.isHidden)
        XCTAssertEqual(emptyRow.frame.height, 44, accuracy: 0.5)
        XCTAssertEqual(
            emptyRow.accessibilityLabel(),
            NSLocalizedString("portal.settings.folders.empty", comment: "")
        )
    }

    @MainActor
    func testFolderSettingsDisableAddingAtFourFolders() throws {
        let tabs = (0..<Portal.maximumTabCount).map { makeTab(name: "Folder-\($0)") }
        let tabBar = TabBarView(frame: .zero)
        tabBar.configure(with: try makePortal(tabs: tabs, selected: tabs[0].id))
        var addCount = 0
        tabBar.onAdd = { addCount += 1 }
        defer { tabBar.closeSettingsWindow() }

        let settings = try settingsController(in: tabBar).settingsViewController
        settings.selectCategory(.folders)
        let addButton = try XCTUnwrap(settings.addFolderButton)

        XCTAssertFalse(addButton.isEnabled)
        XCTAssertEqual(
            addButton.toolTip,
            String(
                format: NSLocalizedString("portal.settings.folder_limit", comment: ""),
                Portal.maximumTabCount
            )
        )
        addButton.performClick(nil)
        XCTAssertEqual(addCount, 0)
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
        XCTAssertTrue(identifiers.contains("portal-settings.tint.default"))
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
        XCTAssertEqual(settings.sortOptionButtons.count, 3)
        XCTAssertEqual(settings.sortOptionButtons.map(\.state), [.off, .off, .on])
        XCTAssertTrue(settings.sortOptionButtons.allSatisfy {
            $0.accessibilityRole() == .radioButton
        })
        settings.sortOptionButtons[0].performClick(nil)

        settings.selectCategory(.style)
        settings.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(settings.tintOptionButtons.count, PortalTint.allCases.count)
        XCTAssertTrue(settings.tintOptionButtons.allSatisfy {
            $0.title.isEmpty && $0.attributedTitle.string.isEmpty
        })
        XCTAssertEqual(settings.tintOptionButtons.map(\.isOptionSelected), [
            false, false, false, false, true, false, false, false,
        ])
        XCTAssertTrue(settings.tintOptionButtons.allSatisfy { button in
            button.hitTest(NSPoint(x: button.frame.midX, y: button.frame.midY)) === button
        })
        let defaultSwatchColor = try XCTUnwrap(
            NSColor(cgColor: try XCTUnwrap(
                settings.tintOptionButtons[0].swatchView.layer?.backgroundColor
            ))?.usingColorSpace(.sRGB)
        )
        let isDarkAppearance = settings.view.effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua
        let expectedDefault = PortalTint.default.resolvedColor(
            forDarkAppearance: isDarkAppearance
        )
        XCTAssertEqual(defaultSwatchColor.redComponent, expectedDefault.red, accuracy: 0.001)
        XCTAssertEqual(defaultSwatchColor.greenComponent, expectedDefault.green, accuracy: 0.001)
        XCTAssertEqual(defaultSwatchColor.blueComponent, expectedDefault.blue, accuracy: 0.001)
        let selectedTint = settings.tintOptionButtons[4]
        selectedTint.layoutSubtreeIfNeeded()
        selectedTint.displayIfNeeded()
        XCTAssertEqual(selectedTint.accessibilityRole(), .radioButton)
        XCTAssertEqual(selectedTint.swatchView.frame.size, NSSize(width: 28, height: 28))
        XCTAssertEqual(selectedTint.swatchView.layer?.cornerRadius, 14)
        XCTAssertNotNil(selectedTint.swatchView.layer?.backgroundColor)
        XCTAssertNotNil(selectedTint.checkmarkView.image)
        settings.tintOptionButtons[5].performClick(nil)

        XCTAssertEqual(sortOrders, [.name])
        XCTAssertEqual(tints, [.blue])
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
