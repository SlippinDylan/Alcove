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
        XCTAssertEqual(tabBar.groupMaterialView.frame.midX, tabBar.bounds.midX, accuracy: 0.5)
        let tabButton = try XCTUnwrap(tabBar.tabButtons[tab.id])
        let tabFrame = tabButton.convert(tabButton.bounds, to: tabBar)
        let material = try XCTUnwrap(tabBar.groupMaterialView.materialView)
        XCTAssertGreaterThan(tabButton.bounds.width, 0)
        XCTAssertGreaterThan(tabButton.bounds.height, 0)
        XCTAssertGreaterThan(material.frame.width, 0)
        XCTAssertGreaterThan(material.frame.height, 0)
        XCTAssertFalse(tabButton.isDescendant(of: material))
        XCTAssertFalse(tabButton.isDescendant(of: tabBar.groupMaterialView))
        XCTAssertTrue(tabButton.isDescendant(of: tabBar.scrollView))
        tabBar.groupBackdropView.updateLayer()
        XCTAssertGreaterThan(tabBar.groupBackdropView.layer?.backgroundColor?.alpha ?? 0, 0)
        let backdropIndex = try XCTUnwrap(
            tabBar.subviews.firstIndex(of: tabBar.groupBackdropView)
        )
        let materialIndex = try XCTUnwrap(tabBar.subviews.firstIndex(of: tabBar.groupMaterialView))
        let scrollIndex = try XCTUnwrap(
            tabBar.subviews.firstIndex(of: tabBar.scrollView)
        )
        XCTAssertLessThan(materialIndex, backdropIndex)
        XCTAssertLessThan(backdropIndex, scrollIndex)

        tabBar.groupMaterialView.rebuildMaterial()
        let rebuiltScrollIndex = try XCTUnwrap(
            tabBar.subviews.firstIndex(of: tabBar.scrollView)
        )
        XCTAssertLessThan(backdropIndex, rebuiltScrollIndex)
        XCTAssertTrue(tabButton.isDescendant(of: tabBar.scrollView))
        XCTAssertTrue(
            tabBar.bounds.contains(tabFrame),
            "Expected visible tab frame; group=\(tabBar.groupMaterialView.frame), tab=\(tabFrame)"
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
        var moveRequests: [(FolderTabID, PortalTabMoveDirection)] = []
        var removePortalCount = 0
        tabBar.onAdd = { addCount += 1 }
        tabBar.onClose = { closedIDs.append($0) }
        tabBar.onMoveTab = { moveRequests.append(($0, $1)) }
        tabBar.onRemovePortal = { removePortalCount += 1 }
        defer { tabBar.closeSettingsWindow() }

        let settingsController = try settingsController(in: tabBar)
        let settingsViewController = settingsController.settingsViewController
        let settingsRoot = settingsViewController.view
        settingsRoot.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            Set(settingsViewController.categoryButtons.keys),
            [.folders, .style]
        )
        XCTAssertEqual(settingsViewController.selectedCategory, .folders)
        XCTAssertEqual(settingsViewController.categoryButtons[.folders]?.state, .on)
        XCTAssertEqual(settingsViewController.categoryButtons[.style]?.state, .off)
        XCTAssertTrue(settingsViewController.separatorView.superview === settingsRoot)
        XCTAssertEqual(settingsViewController.separatorView.boxType, .separator)
        let navigationFrame = try XCTUnwrap(
            settingsViewController.categoryButtons[.folders]
        ).convert(
            try XCTUnwrap(settingsViewController.categoryButtons[.folders]).bounds,
            to: settingsRoot
        )
        let separatorFrame = settingsViewController.separatorView.convert(
            settingsViewController.separatorView.bounds,
            to: settingsRoot
        )
        XCTAssertGreaterThan(navigationFrame.minY, separatorFrame.maxY)

        try settingsButton(
            titled: NSLocalizedString("portal.settings.add_folder", comment: ""),
            in: tabBar
        ).performClick(nil)
        let firstMoveUp = try folderActionButton(
            labeled: NSLocalizedString("portal.settings.move_up", comment: ""),
            for: "First",
            in: tabBar
        )
        XCTAssertFalse(firstMoveUp.isEnabled)
        try folderActionButton(
            labeled: NSLocalizedString("portal.settings.move_down", comment: ""),
            for: "First",
            in: tabBar
        ).performClick(nil)
        try folderActionButton(
            labeled: NSLocalizedString("portal.settings.move_up", comment: ""),
            for: "Second",
            in: tabBar
        ).performClick(nil)
        try folderActionButton(
            labeled: NSLocalizedString("portal.settings.remove_folder_action", comment: ""),
            for: "Third",
            in: tabBar
        ).performClick(nil)
        try settingsButton(
            titled: NSLocalizedString("portal.settings.remove_portal", comment: ""),
            in: tabBar
        ).performClick(nil)

        XCTAssertEqual(addCount, 1)
        XCTAssertEqual(closedIDs, [third.id])
        XCTAssertEqual(moveRequests.count, 2)
        XCTAssertEqual(moveRequests[0].0, first.id)
        XCTAssertEqual(moveRequests[0].1, .down)
        XCTAssertEqual(moveRequests[1].0, second.id)
        XCTAssertEqual(moveRequests[1].1, .up)
        XCTAssertEqual(removePortalCount, 1)
        XCTAssertEqual(
            tabBar.managementButton.accessibilityLabel(),
            NSLocalizedString("portal.settings.label", comment: "")
        )
        XCTAssertNotNil(tabBar.managementButton.image)
        let settingsWindow = try XCTUnwrap(settingsController.window)
        XCTAssertEqual(settingsWindow.contentView?.bounds.size, NSSize(width: 400, height: 544))
        XCTAssertNil(settingsWindow.toolbar)
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
        }
        let firstFolderRow = try XCTUnwrap(
            descendants(of: settingsRoot)
                .compactMap { $0 as? NSStackView }
                .first { row in
                    row.subviews.compactMap { $0 as? NSTextField }
                        .contains { $0.stringValue == "First" }
                }
        )
        let firstFolderCard = try XCTUnwrap(cards.first)
        let firstFolderRowFrame = firstFolderRow.convert(firstFolderRow.bounds, to: firstFolderCard)
        XCTAssertEqual(firstFolderRowFrame.minX, 16, accuracy: 0.5)
        XCTAssertEqual(firstFolderRowFrame.maxX, firstFolderCard.bounds.maxX - 16, accuracy: 0.5)
    }

    @MainActor
    func testStyleCategoryUsesFiveAndThreeStepSlidersAndInvokesCallbacks() throws {
        let tab = makeTab(name: "First")
        var portal = try makePortal(tabs: [tab], selected: tab.id)
        portal.updateBackgroundStyle(.lowTransparency)
        let tabBar = TabBarView(frame: .zero)
        var requestedStyle: PortalBackgroundStyle?
        var requestedIconSize: IconSize?
        tabBar.onSetBackgroundStyle = { requestedStyle = $0 }
        tabBar.onSetIconSize = { requestedIconSize = $0 }
        defer { tabBar.closeSettingsWindow() }

        tabBar.configure(with: portal)

        try selectCategory(.style, in: tabBar)
        let settingsViewController = try settingsController(in: tabBar).settingsViewController
        settingsViewController.view.layoutSubtreeIfNeeded()
        let styleCards = settingsViewController.contentStack.arrangedSubviews.enumerated()
            .compactMap { index, view in index.isMultiple(of: 2) ? nil : view }
        XCTAssertEqual(styleCards.count, 2)
        for card in styleCards {
            XCTAssertLessThanOrEqual(card.frame.height, 60)
            XCTAssertEqual(
                card.frame.width,
                settingsViewController.contentStack.frame.width,
                accuracy: 0.5
            )
        }
        let background = try slider(
            identifier: "portal-settings.background",
            in: tabBar
        )
        let iconSize = try slider(identifier: "portal-settings.icon-size", in: tabBar)
        XCTAssertEqual(background.minValue, 0)
        XCTAssertEqual(background.maxValue, 4)
        XCTAssertEqual(background.numberOfTickMarks, 5)
        XCTAssertTrue(background.allowsTickMarkValuesOnly)
        XCTAssertEqual(background.doubleValue, 3)
        XCTAssertEqual(iconSize.minValue, 0)
        XCTAssertEqual(iconSize.maxValue, 2)
        XCTAssertEqual(iconSize.numberOfTickMarks, 3)
        XCTAssertTrue(iconSize.allowsTickMarkValuesOnly)
        XCTAssertEqual(iconSize.doubleValue, 1)

        background.doubleValue = 0
        NSApplication.shared.sendAction(
            try XCTUnwrap(background.action),
            to: background.target,
            from: background
        )
        XCTAssertEqual(requestedStyle, .maximumTransparency)
        iconSize.doubleValue = 0
        NSApplication.shared.sendAction(
            try XCTUnwrap(iconSize.action),
            to: iconSize.target,
            from: iconSize
        )
        XCTAssertEqual(requestedIconSize, .small)

        portal.updateBackgroundStyle(.minimumTransparency)
        tabBar.update(with: portal)
        XCTAssertEqual(try slider(identifier: "portal-settings.background", in: tabBar).doubleValue, 4)
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
        XCTAssertEqual(tabBar.groupMaterialView.frame.midX, tabBar.bounds.midX, accuracy: 0.5)
    }

    @MainActor
    func testControlGroupUsesOneOuterCapsuleWithTheResolvedMaterial() throws {
        let tab = makeTab(name: "Only")
        let tabBar = TabBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))

        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))

        let material = try XCTUnwrap(tabBar.groupMaterialView.materialView)
        let expectedPath = PortalChromeMaterialResolver.resolve(
            role: .controlGroup,
            supportsGlass: {
                if #available(macOS 26.0, *) { return true }
                return false
            }(),
            accessibility: PortalAccessibilityOptions.current()
        )
        XCTAssertEqual(tabBar.groupMaterialView.materialPath, expectedPath)
        XCTAssertEqual(tabBar.groupMaterialView.layer?.cornerRadius, 999)
        if let effect = material as? NSVisualEffectView {
            XCTAssertEqual(effect.state, .active)
        }
        XCTAssertFalse(try XCTUnwrap(tabBar.tabButtons[tab.id]).isDescendant(of: material))
        XCTAssertEqual(tabBar.groupMaterialView.layer?.backgroundColor?.alpha ?? 0, 0)
        tabBar.groupBackdropView.updateLayer()
        XCTAssertGreaterThan(tabBar.groupBackdropView.layer?.backgroundColor?.alpha ?? 0, 0)
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
            tabBar.managementButton.performClick(nil)
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
        try XCTUnwrap(
            settingsController(in: tabBar).settingsViewController.categoryButtons[category]
        ).performClick(nil)
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
        let folderRow = try XCTUnwrap(
            descendants(of: try settingsRoot(in: tabBar))
                .compactMap { $0 as? NSStackView }
                .first { row in
                    row.subviews.compactMap { $0 as? NSTextField }
                        .contains { $0.stringValue == folderName }
                }
        )
        return try XCTUnwrap(
            folderRow.subviews.compactMap { $0 as? NSButton }
                .first { $0.accessibilityLabel() == label }
        )
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
}
