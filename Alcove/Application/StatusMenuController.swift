import AppKit

@MainActor
final class StatusMenuController: StatusMenuControlling {
    private let statusBar: NSStatusBar
    private let onNewPortal: () -> Void
    private(set) var statusItem: NSStatusItem?

    init(statusBar: NSStatusBar = .system, onNewPortal: @escaping () -> Void) {
        self.statusBar = statusBar
        self.onNewPortal = onNewPortal
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

    func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let newPortalItem = NSMenuItem(
            title: "New Portal",
            action: #selector(requestNewPortal(_:)),
            keyEquivalent: ""
        )
        newPortalItem.target = self
        menu.addItem(newPortalItem)
        menu.addItem(.separator())

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
}
