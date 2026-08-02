// AppDelegate.swift
// Alcove Spike 0.4A — Material Compatibility Boundary Bootstrap

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var controller: MaterialWindowController?
    private(set) var preference: MaterialPreference = .automatic
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
            preference: preference,
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

    func setMaterialPreference(_ newPreference: MaterialPreference) {
        preference = newPreference
        controller?.setPreference(newPreference)
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

        let materialItem = NSMenuItem()
        materialItem.submenu = buildMaterialMenu()
        mainMenu.addItem(materialItem)

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

    private func buildMaterialMenu() -> NSMenu {
        let menu = NSMenu(title: "Material")
        for preference in MaterialPreference.allCases {
            let item = NSMenuItem(
                title: preference.description,
                action: #selector(switchMaterial(_:)),
                keyEquivalent: preference.menuKeyEquivalent
            )
            item.target = self
            item.representedObject = preference.rawValue
            menu.addItem(item)
        }
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

    @objc private func switchMaterial(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let preference = MaterialPreference(rawValue: rawValue)
        else { return }
        setMaterialPreference(preference)
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
