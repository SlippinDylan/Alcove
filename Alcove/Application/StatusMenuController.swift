import AppKit
import AlcoveCore

struct PortalMenuEntry: Equatable {
    let id: PortalID
    let title: String
    let iconSize: IconSize
}

@MainActor
final class StatusMenuController: StatusMenuControlling {
    private let statusBar: NSStatusBar
    private let onNewPortal: () -> Void
    private let onShowPortal: (PortalID) -> Void
    private let onRemovePortal: (PortalID) -> Void
    private let onSetIconSize: (PortalID, IconSize) -> Void
    private var portalEntries: [PortalMenuEntry] = []
    private var actionTargets: [PortalMenuActionTarget] = []
    private(set) var statusItem: NSStatusItem?

    init(
        statusBar: NSStatusBar = .system,
        onNewPortal: @escaping () -> Void,
        onShowPortal: @escaping (PortalID) -> Void = { _ in },
        onRemovePortal: @escaping (PortalID) -> Void = { _ in },
        onSetIconSize: @escaping (PortalID, IconSize) -> Void = { _, _ in }
    ) {
        self.statusBar = statusBar
        self.onNewPortal = onNewPortal
        self.onShowPortal = onShowPortal
        self.onRemovePortal = onRemovePortal
        self.onSetIconSize = onSetIconSize
    }

    func start() {
        guard statusItem == nil else { return }

        let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(
                systemSymbolName: "folder",
                accessibilityDescription: "Alcove"
            ) {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Alcove"
            }
            button.toolTip = "Alcove"
        }
        item.menu = makeMenu()
        statusItem = item
    }

    func stop() {
        guard let statusItem else { return }
        statusBar.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func updatePortals(_ entries: [PortalMenuEntry]) {
        portalEntries = entries
        statusItem?.menu = makeMenu()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        actionTargets.removeAll(keepingCapacity: true)

        let newPortalItem = NSMenuItem(
            title: "New Portal",
            action: #selector(requestNewPortal(_:)),
            keyEquivalent: ""
        )
        newPortalItem.target = self
        menu.addItem(newPortalItem)
        menu.addItem(.separator())

        for entry in portalEntries {
            let portalItem = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            portalItem.submenu = makePortalMenu(for: entry)
            menu.addItem(portalItem)
        }

        if !portalEntries.isEmpty {
            menu.addItem(.separator())
        }

        let quitItem = NSMenuItem(
            title: "Quit Alcove",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)

        return menu
    }

    @objc
    private func requestNewPortal(_ sender: NSMenuItem) {
        onNewPortal()
    }

    private func makePortalMenu(for entry: PortalMenuEntry) -> NSMenu {
        let menu = NSMenu(title: entry.title)
        menu.addItem(makeActionItem(title: "Show", action: .show(entry.id)))

        let iconSizeItem = NSMenuItem(title: "Icon Size", action: nil, keyEquivalent: "")
        let iconSizeMenu = NSMenu(title: "Icon Size")
        for size in [IconSize.small, .medium, .large] {
            let item = makeActionItem(
                title: iconSizeTitle(size),
                action: .setIconSize(entry.id, size)
            )
            item.state = size == entry.iconSize ? .on : .off
            iconSizeMenu.addItem(item)
        }
        iconSizeItem.submenu = iconSizeMenu
        menu.addItem(iconSizeItem)
        menu.addItem(.separator())
        menu.addItem(makeActionItem(title: "Remove Portal", action: .remove(entry.id)))
        return menu
    }

    private func makeActionItem(title: String, action: PortalMenuAction) -> NSMenuItem {
        let target = PortalMenuActionTarget(action: action, owner: self)
        actionTargets.append(target)
        let item = NSMenuItem(
            title: title,
            action: #selector(PortalMenuActionTarget.performAction(_:)),
            keyEquivalent: ""
        )
        item.target = target
        return item
    }

    private func iconSizeTitle(_ size: IconSize) -> String {
        switch size {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        default: "Custom"
        }
    }

    fileprivate func perform(_ action: PortalMenuAction) {
        switch action {
        case .show(let id): onShowPortal(id)
        case .remove(let id): onRemovePortal(id)
        case .setIconSize(let id, let size): onSetIconSize(id, size)
        }
    }
}

private enum PortalMenuAction {
    case show(PortalID)
    case remove(PortalID)
    case setIconSize(PortalID, IconSize)
}

@MainActor
private final class PortalMenuActionTarget: NSObject {
    private let action: PortalMenuAction
    private weak var owner: StatusMenuController?

    init(action: PortalMenuAction, owner: StatusMenuController) {
        self.action = action
        self.owner = owner
    }

    @objc func performAction(_ sender: NSMenuItem) {
        owner?.perform(action)
    }
}
