// AppDelegate.swift
// Alcove Spike 0.4A — Material Compatibility Boundary Bootstrap

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var controller: MaterialWindowController?
    private(set) var levelCandidate: WindowLevelCandidate = .desktopCandidate

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate()
        createWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.close()
        controller = nil
    }

    func createWindow() {
        controller?.close()
        let newController = MaterialWindowController(
            levelCandidate: levelCandidate
        )
        newController.onClose = { [weak self, weak newController] in
            guard let self, self.controller === newController else { return }
            self.controller = nil
        }
        controller = newController
        newController.showWindow(nil)
        NSApp.activate()
        newController.window?.makeKeyAndOrderFront(nil)
    }

    func setWindowLevel(_ newLevel: WindowLevelCandidate) {
        levelCandidate = newLevel
        controller?.setLevelCandidate(newLevel)
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = buildAppMenu()
        mainMenu.addItem(appItem)

        let levelItem = NSMenuItem()
        levelItem.submenu = buildLevelMenu()
        mainMenu.addItem(levelItem)

        let windowItem = NSMenuItem()
        windowItem.submenu = buildWindowMenu()
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }

    private func buildAppMenu() -> NSMenu {
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Alcove Material Spike",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    private func buildLevelMenu() -> NSMenu {
        let menu = NSMenu(title: "Window Level")
        for level in WindowLevelCandidate.allCases {
            let item = NSMenuItem(
                title: level.description,
                action: #selector(switchLevel(_:)),
                keyEquivalent: level.menuKeyEquivalent
            )
            item.target = self
            item.representedObject = level.rawValue
            menu.addItem(item)
        }
        return menu
    }

    private func buildWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        let recreate = NSMenuItem(
            title: "Recreate Window",
            action: #selector(recreateWindowAction),
            keyEquivalent: "r"
        )
        recreate.target = self
        menu.addItem(recreate)
        let close = NSMenuItem(
            title: "Close Window",
            action: #selector(closeWindowAction),
            keyEquivalent: "w"
        )
        close.target = self
        menu.addItem(close)
        return menu
    }

    @objc private func switchLevel(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let level = WindowLevelCandidate(rawValue: rawValue)
        else { return }
        setWindowLevel(level)
    }

    @objc private func recreateWindowAction() {
        createWindow()
    }

    @objc private func closeWindowAction() {
        controller?.close()
    }
}
