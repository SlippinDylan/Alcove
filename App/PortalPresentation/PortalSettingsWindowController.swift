import AlcoveCore
import AppKit

@MainActor
final class PortalSettingsWindowController: NSWindowController {
    private(set) var settingsViewController: PortalSettingsViewController
    private(set) var categoryItems: [PortalSettingsViewController.Category: NSToolbarItem] = [:]
    private let settingsToolbar = NSToolbar(identifier: "portal-settings")
    private var portal: Portal

    init(
        portal: Portal,
        onAddFolder: @escaping () -> Void,
        onCloseFolder: @escaping (FolderTabID) -> Void,
        onMoveFolder: @escaping (FolderTabID, Int) -> Void,
        onSetSortOrder: @escaping (PortalSortOrder) -> Void,
        onSetTint: @escaping (PortalTint) -> Void
    ) {
        self.portal = portal
        let settingsViewController = PortalSettingsViewController(
            portal: portal,
            onAddFolder: onAddFolder,
            onCloseFolder: onCloseFolder,
            onMoveFolder: onMoveFolder,
            onSetSortOrder: onSetSortOrder,
            onSetTint: onSetTint
        )
        self.settingsViewController = settingsViewController
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = settingsViewController
        window.setContentSize(NSSize(width: 400, height: 450))
        window.title = ""
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        shouldCascadeWindows = false
        configureToolbar(for: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(_ portal: Portal) {
        guard self.portal != portal else { return }
        self.portal = portal
        settingsViewController.update(portal)
    }

    func selectCategory(_ category: PortalSettingsViewController.Category) {
        settingsToolbar.selectedItemIdentifier = category.toolbarItemIdentifier
        settingsViewController.selectCategory(category)
    }

    func present(on screen: NSScreen?) {
        guard let window else { return }
        if !window.isVisible {
            let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
            if let visibleFrame {
                window.setFrameOrigin(
                    NSPoint(
                        x: visibleFrame.midX - window.frame.width / 2,
                        y: visibleFrame.midY - window.frame.height / 2
                    )
                )
            } else {
                window.center()
            }
        }
        NSApplication.shared.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureToolbar(for window: NSWindow) {
        settingsToolbar.delegate = self
        settingsToolbar.displayMode = .iconAndLabel
        settingsToolbar.allowsUserCustomization = false
        settingsToolbar.autosavesConfiguration = false
        window.toolbarStyle = .preference
        window.toolbar = settingsToolbar
        window.titlebarSeparatorStyle = .none
        settingsToolbar.selectedItemIdentifier = PortalSettingsViewController.Category.general
            .toolbarItemIdentifier
    }

}

extension PortalSettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PortalSettingsViewController.Category.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let category = PortalSettingsViewController.Category(
            toolbarItemIdentifier: itemIdentifier
        ) else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = category.title
        item.paletteLabel = category.title
        item.toolTip = category.title
        item.image = NSImage(
            systemSymbolName: category.symbol,
            accessibilityDescription: category.title
        )?.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        item.target = self
        item.action = #selector(selectToolbarCategory(_:))
        item.tag = category.rawValue
        item.isBordered = false
        categoryItems[category] = item
        return item
    }

    @objc private func selectToolbarCategory(_ sender: NSToolbarItem) {
        guard let category = PortalSettingsViewController.Category(rawValue: sender.tag) else {
            return
        }
        selectCategory(category)
    }
}
