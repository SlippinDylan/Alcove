import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

extension TabBarViewTests {
    @MainActor
    func testRepeatedPanelSettingsPresentationReusesFloatingWindowWithoutRepositioningIt() throws {
        let tabBar = TabBarView(frame: .zero)
        let tab = makeTab(name: "Folder")
        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))
        defer { tabBar.closeSettingsWindow() }

        tabBar.showSettingsWindow()
        let controller = try XCTUnwrap(tabBar.settingsWindowController)
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(window.isVisible)

        window.setFrameOrigin(NSPoint(x: 160, y: 180))
        let visibleFrame = window.frame
        tabBar.showSettingsWindow()

        XCTAssertTrue(tabBar.settingsWindowController === controller)
        XCTAssertTrue(controller.window === window)
        XCTAssertEqual(window.frame, visibleFrame)
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
        XCTAssertTrue(settingsController.categoryItems.values.allSatisfy { !$0.isBordered })
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

}
