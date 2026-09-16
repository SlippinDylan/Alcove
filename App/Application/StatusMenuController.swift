import AppKit
import AlcoveCore

struct PortalMenuEntry: Equatable {
    let id: PortalID
    let title: String
    let isPinned: Bool

    init(id: PortalID, title: String, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.isPinned = isPinned
    }
}

@MainActor
final class StatusMenuController: StatusMenuControlling {
    private let statusBar: NSStatusBar
    private let onNewPortal: () -> Void
    private let onOpenSettings: () -> Void
    private let onShowPortal: (PortalID) -> Void
    private let onHidePortal: (PortalID) -> Void
    private let onSetPortalPinned: (PortalID, Bool) -> Void
    private let onOpenPortalSettings: (PortalID) -> Void
    private let onRequestPortalRemoval: (PortalID) -> Void
    private var portalEntries: [PortalMenuEntry] = []
    private var actionTargets: [PortalMenuActionTarget] = []
    private(set) var statusItem: NSStatusItem?

    init(
        statusBar: NSStatusBar = .system,
        onNewPortal: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onShowPortal: @escaping (PortalID) -> Void = { _ in },
        onHidePortal: @escaping (PortalID) -> Void = { _ in },
        onSetPortalPinned: @escaping (PortalID, Bool) -> Void = { _, _ in },
        onOpenPortalSettings: @escaping (PortalID) -> Void = { _ in },
        onRequestPortalRemoval: @escaping (PortalID) -> Void = { _ in }
    ) {
        self.statusBar = statusBar
        self.onNewPortal = onNewPortal
        self.onOpenSettings = onOpenSettings
        self.onShowPortal = onShowPortal
        self.onHidePortal = onHidePortal
        self.onSetPortalPinned = onSetPortalPinned
        self.onOpenPortalSettings = onOpenPortalSettings
        self.onRequestPortalRemoval = onRequestPortalRemoval
    }

    func start() {
        guard statusItem == nil else { return }

        let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(
                systemSymbolName: "tray.full",
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
            title: NSLocalizedString("menu.new_portal", comment: "Create a new portal"),
            action: #selector(requestNewPortal(_:)),
            keyEquivalent: ""
        )
        newPortalItem.target = self
        newPortalItem.image = menuImage(
            symbolName: "rectangle.badge.plus",
            accessibilityDescription: newPortalItem.title
        )
        menu.addItem(newPortalItem)
        menu.addItem(.separator())

        for entry in portalEntries {
            let portalItem = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            portalItem.submenu = makePortalMenu(for: entry)
            menu.addItem(portalItem)
        }

        if !portalEntries.isEmpty { menu.addItem(.separator()) }

        let settingsItem = NSMenuItem(
            title: NSLocalizedString("menu.settings", comment: "Open application settings"),
            action: #selector(requestSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = menuImage(
            symbolName: "gearshape",
            accessibilityDescription: settingsItem.title
        )
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: NSLocalizedString("menu.quit", comment: "Quit Alcove"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        quitItem.image = menuImage(
            symbolName: "power",
            accessibilityDescription: quitItem.title
        )
        menu.addItem(quitItem)

        return menu
    }

    private func menuImage(
        symbolName: String,
        accessibilityDescription: String
    ) -> NSImage? {
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
        image?.isTemplate = true
        return image
    }

    @objc
    private func requestNewPortal(_ sender: NSMenuItem) {
        onNewPortal()
    }

    @objc
    private func requestSettings(_ sender: NSMenuItem) {
        onOpenSettings()
    }

    private func makePortalMenu(for entry: PortalMenuEntry) -> NSMenu {
        let menu = NSMenu(title: entry.title)
        menu.addItem(makeActionItem(
            title: NSLocalizedString("menu.show", comment: "Show a portal"),
            symbolName: "eye",
            action: .show(entry.id)
        ))
        menu.addItem(makeActionItem(
            title: NSLocalizedString("menu.hide", comment: "Hide a portal"),
            symbolName: "eye.slash",
            action: .hide(entry.id)
        ))
        menu.addItem(.separator())
        menu.addItem(makeActionItem(
            title: entry.isPinned
                ? NSLocalizedString("portal.pin.unpin", comment: "Unpin a portal")
                : NSLocalizedString("portal.pin.pin", comment: "Pin a portal"),
            symbolName: entry.isPinned ? "pin.slash" : "pin",
            action: .setPinned(entry.id, !entry.isPinned)
        ))
        menu.addItem(makeActionItem(
            title: NSLocalizedString("portal.settings.open", comment: "Open panel settings"),
            symbolName: "gearshape",
            action: .settings(entry.id)
        ))
        menu.addItem(.separator())
        menu.addItem(makeActionItem(
            title: NSLocalizedString("portal.remove.menu", comment: "Remove portal menu item"),
            symbolName: "trash",
            action: .remove(entry.id)
        ))
        return menu
    }

    private func makeActionItem(
        title: String,
        symbolName: String,
        action: PortalMenuAction
    ) -> NSMenuItem {
        let target = PortalMenuActionTarget(action: action, owner: self)
        actionTargets.append(target)
        let item = NSMenuItem(
            title: title,
            action: #selector(PortalMenuActionTarget.performAction(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.image = menuImage(symbolName: symbolName, accessibilityDescription: title)
        return item
    }

    fileprivate func perform(_ action: PortalMenuAction) {
        switch action {
        case .show(let id): onShowPortal(id)
        case .hide(let id): onHidePortal(id)
        case .setPinned(let id, let isPinned): onSetPortalPinned(id, isPinned)
        case .settings(let id): onOpenPortalSettings(id)
        case .remove(let id): onRequestPortalRemoval(id)
        }
    }
}

private enum PortalMenuAction {
    case show(PortalID)
    case hide(PortalID)
    case setPinned(PortalID, Bool)
    case settings(PortalID)
    case remove(PortalID)
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
