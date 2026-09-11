import AppKit

@MainActor
final class StatusMenuController: StatusMenuControlling {
    private let statusBar: NSStatusBar
    private(set) var statusItem: NSStatusItem?

    init(statusBar: NSStatusBar = .system) {
        self.statusBar = statusBar
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
        item.menu = Self.makeMenu()
        statusItem = item
    }

    func stop() {
        guard let statusItem else { return }
        statusBar.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    static func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let newPortalItem = NSMenuItem(
            title: "New Portal",
            action: nil,
            keyEquivalent: ""
        )
        newPortalItem.isEnabled = false
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
}
