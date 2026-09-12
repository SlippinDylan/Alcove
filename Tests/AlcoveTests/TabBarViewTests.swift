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
        try settingsButton(titled: "Remove First", in: tabBar).performClick(nil)

        XCTAssertEqual(selectedID, second.id)
        XCTAssertEqual(closedID, first.id)
        XCTAssertEqual(tabBar.selectedTabID, first.id)

        tabBar.update(with: try makePortal(tabs: [first, second], selected: second.id))
        XCTAssertEqual(tabBar.selectedTabID, second.id)
        XCTAssertNotNil(try? settingsButton(titled: "Remove Second", in: tabBar))
    }

    @MainActor
    func testFolderSettingsInvokeCallbacksAndExposeSettingsIcon() throws {
        let tabBar = TabBarView(frame: .zero)
        let tab = makeTab(name: "First")
        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))
        var addCount = 0
        var closedID: FolderTabID?
        tabBar.onAdd = { addCount += 1 }
        tabBar.onClose = { closedID = $0 }
        defer { tabBar.closeSettingsWindow() }

        try settingsButton(titled: "Add Folder…", in: tabBar).performClick(nil)
        try settingsButton(titled: "Remove First", in: tabBar).performClick(nil)

        XCTAssertEqual(addCount, 1)
        XCTAssertEqual(closedID, tab.id)
        XCTAssertEqual(tabBar.managementButton.accessibilityLabel(), "Portal settings")
        XCTAssertNotNil(tabBar.managementButton.image)
        XCTAssertEqual(
            try settingsController(in: tabBar).tabViewController.tabViewItems.map(\.label),
            ["Folders", "Style", "Other"]
        )
        let settingsWindow = try XCTUnwrap(tabBar.settingsWindowController?.window)
        XCTAssertEqual(settingsWindow.frame.size, NSSize(width: 400, height: 572))
        XCTAssertEqual(
            tabBar.settingsWindowController?.tabViewController.tabStyle,
            .toolbar
        )
        XCTAssertNotNil(settingsWindow.toolbar)
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
    }

    @MainActor
    func testStyleCategoryShowsCurrentChoicesAndInvokesCallback() throws {
        let tab = makeTab(name: "First")
        var portal = try makePortal(tabs: [tab], selected: tab.id)
        portal.updateBackgroundStyle(.lowTransparency)
        let tabBar = TabBarView(frame: .zero)
        var requestedStyle: PortalBackgroundStyle?
        tabBar.onSetBackgroundStyle = { requestedStyle = $0 }
        defer { tabBar.closeSettingsWindow() }

        tabBar.configure(with: portal)

        try selectCategory(named: "Style", in: tabBar)
        let background = try popup(
            identifier: "portal-settings.background",
            in: tabBar
        )
        XCTAssertEqual(background.itemTitles, [
            "High Transparency", "Standard", "Low Transparency",
        ])
        XCTAssertEqual(background.titleOfSelectedItem, "Low Transparency")

        background.selectItem(at: 0)
        NSApplication.shared.sendAction(
            try XCTUnwrap(background.action),
            to: background.target,
            from: background
        )
        XCTAssertEqual(requestedStyle, .highTransparency)

        portal.updateBackgroundStyle(.highTransparency)
        tabBar.update(with: portal)
        try selectCategory(named: "Style", in: tabBar)
        XCTAssertEqual(
            try popup(identifier: "portal-settings.background", in: tabBar).titleOfSelectedItem,
            "High Transparency"
        )
    }

    @MainActor
    func testStyleAndOtherCategoriesForwardIconAndPortalActions() throws {
        let tab = makeTab(name: "First")
        let tabBar = TabBarView(frame: .zero)
        var iconSize: IconSize?
        var followCount = 0
        var removeCount = 0
        tabBar.onSetIconSize = { iconSize = $0 }
        tabBar.onFollowDesktopIconSettings = { followCount += 1 }
        tabBar.onRemovePortal = { removeCount += 1 }
        tabBar.configure(with: try makePortal(tabs: [tab], selected: tab.id))
        defer { tabBar.closeSettingsWindow() }

        try selectCategory(named: "Style", in: tabBar)
        let iconPopup = try popup(identifier: "portal-settings.icon-size", in: tabBar)
        iconPopup.selectItem(withTitle: "Small")
        NSApplication.shared.sendAction(
            try XCTUnwrap(iconPopup.action),
            to: iconPopup.target,
            from: iconPopup
        )
        XCTAssertEqual(iconSize, .small)

        iconPopup.selectItem(withTitle: "Follow Desktop")
        NSApplication.shared.sendAction(
            try XCTUnwrap(iconPopup.action),
            to: iconPopup.target,
            from: iconPopup
        )
        XCTAssertEqual(followCount, 1)

        try selectCategory(named: "Other", in: tabBar)
        try settingsButton(titled: "Remove Portal", in: tabBar).performClick(nil)
        XCTAssertEqual(removeCount, 1)
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
        let controller = try settingsController(in: tabBar)
        let index = controller.tabViewController.selectedTabViewItemIndex
        let item = controller.tabViewController.tabViewItems[index]
        return try XCTUnwrap(item.viewController).view
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
    private func selectCategory(named name: String, in tabBar: TabBarView) throws {
        let tabs = try settingsController(in: tabBar).tabViewController
        let index = try XCTUnwrap(tabs.tabViewItems.firstIndex { $0.label == name })
        tabs.selectedTabViewItemIndex = index
    }

    @MainActor
    private func popup(identifier: String, in tabBar: TabBarView) throws -> NSPopUpButton {
        try XCTUnwrap(
            descendants(of: try settingsRoot(in: tabBar))
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.identifier?.rawValue == identifier }
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
