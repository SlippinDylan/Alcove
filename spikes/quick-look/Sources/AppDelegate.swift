// AppDelegate.swift
// Alcove Spike 0.3A — Quick Look Responder Bootstrap
// Disposable harness; not production architecture.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: SpikeWindow?
    private var quickLookResponder: QuickLookResponder?
    private var collectionViewController: CollectionViewController?
    private var fixtureStore: PreviewFixtureStore?
    private var windowCloseDelegate: WindowCloseDelegate?
    private var windowStrategy = PreviewWindowLevelStrategy.normal

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate()
        createAndShowWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardown()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            if window == nil {
                createAndShowWindow()
            } else {
                NSApp.activate()
                window?.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    private func setupMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let quitItem = NSMenuItem(
            title: "Quit Alcove QL Spike",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        appMenu.addItem(quitItem)

        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        addWindowMenuItem(to: windowMenu, title: "Close Window", action: #selector(closeWindow), key: "w")
        addWindowMenuItem(to: windowMenu, title: "Recreate Window", action: #selector(recreateWindow), key: "n")
        windowMenu.addItem(.separator())
        addWindowMenuItem(to: windowMenu, title: "Normal Level", action: #selector(useNormalLevel), key: "1")
        addWindowMenuItem(to: windowMenu, title: "Desktop Candidate Level", action: #selector(useDesktopCandidateLevel), key: "2")
        NSApp.mainMenu = mainMenu
    }

    private func addWindowMenuItem(to menu: NSMenu, title: String, action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = .command
        menu.addItem(item)
    }

    private func createAndShowWindow() {
        guard window == nil else { return }

        let store: PreviewFixtureStore
        do {
            store = try PreviewFixtureStore.create([
                ("sample.txt", "Alcove Quick Look Spike — Phase 0.3A\n\nRead-only text fixture.\n"),
                ("readme.md", "# Alcove QL Spike\n\nRead-only Markdown fixture.\n"),
                ("notes.rtf", "{\\rtf1\\ansi{\\fonttbl\\f0 Helvetica;}\\f0\\fs24 Alcove Spike 0.3A}"),
            ])
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
            return
        }
        fixtureStore = store

        let responder = QuickLookResponder()
        responder.setFixtures(store.fixtures)
        quickLookResponder = responder

        let contentController = CollectionViewController(quickLookResponder: responder)
        collectionViewController = contentController

        let spikeWindow = SpikeWindow(
            contentRect: NSRect(x: 200, y: 200, width: 520, height: 420),
            styleMask: [.resizable, .titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        spikeWindow.title = "Alcove QL Spike — Phase 0.3A"
        spikeWindow.titlebarAppearsTransparent = true
        spikeWindow.titleVisibility = .hidden
        spikeWindow.isMovableByWindowBackground = true
        spikeWindow.contentViewController = contentController
        spikeWindow.installQuickLookResponder(responder)
        applyWindowStrategy(to: spikeWindow)

        let closeDelegate = WindowCloseDelegate { [weak self, weak spikeWindow] in
            guard let self, self.window === spikeWindow else { return }
            self.teardown()
        }
        windowCloseDelegate = closeDelegate
        spikeWindow.delegate = closeDelegate
        window = spikeWindow

        NSApp.activate()
        spikeWindow.makeKeyAndOrderFront(nil)
        contentController.focusCollection(in: spikeWindow)
    }

    private func teardown() {
        window?.uninstallQuickLookResponder()
        quickLookResponder?.teardownPanelState()

        if let fixtureStore {
            do {
                try fixtureStore.cleanup()
            } catch {
                NSApp.presentError(error)
            }
        }

        fixtureStore = nil
        quickLookResponder = nil
        collectionViewController = nil
        windowCloseDelegate = nil
        window = nil
    }

    private func applyWindowStrategy(to window: SpikeWindow) {
        window.level = windowStrategy.level
        collectionViewController?.updateWindowStrategy(windowStrategy)
    }

    @objc private func closeWindow() {
        window?.close()
    }

    @objc private func recreateWindow() {
        window?.close()
        createAndShowWindow()
    }

    @objc private func useNormalLevel() {
        windowStrategy = .normal
        if let window { applyWindowStrategy(to: window) }
    }

    @objc private func useDesktopCandidateLevel() {
        windowStrategy = .desktopCandidate
        if let window { applyWindowStrategy(to: window) }
    }
}

@MainActor
private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
