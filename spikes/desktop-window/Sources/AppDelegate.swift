// AppDelegate.swift
// Alcove Spike 0.1B — Desktop Window Strategy Model
// Disposable harness; not production architecture.

import AppKit

/// Application delegate for the Spike 0.1 harness.
///
/// Owns the experiment window controller (strong reference). Closing the window
/// nils the reference so the controller and window are deallocated cleanly;
/// "Recreate" creates a fresh instance. This avoids dangling/deallocated
/// controller problems.
///
/// Phase 0.1B: all preset menu actions dispatch through a single `switchToPreset`
/// method. The selected preset is preserved across close/recreate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var currentPreset: StrategyPreset = .desktopCandidate
    private var controller: ExperimentWindowController?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        createAndShowWindow(preset: currentPreset)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            if controller == nil {
                createAndShowWindow(preset: currentPreset)
            } else {
                controller?.showAndActivate()
            }
        }
        return true
    }

    // MARK: - Menu Setup

    private func setupMenu() {
        let mainMenu = NSMenu()

        // Application menu (first item)
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let quitItem = NSMenuItem(
            title: "Quit Alcove Spike",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        appMenu.addItem(quitItem)

        // Strategy menu — one entry per preset
        let strategyMenu = NSMenu(title: "Strategy")
        let strategyMenuItem = NSMenuItem()
        strategyMenuItem.submenu = strategyMenu
        mainMenu.addItem(strategyMenuItem)

        for preset in StrategyPreset.allCases {
            let item = NSMenuItem(
                title: preset.description,
                action: #selector(switchPresetFromMenu(_:)),
                keyEquivalent: preset.menuKeyEquivalent
            )
            item.target = self
            item.keyEquivalentModifierMask = .command
            item.representedObject = preset
            strategyMenu.addItem(item)
        }

        strategyMenu.addItem(NSMenuItem.separator())

        let activateItem = NSMenuItem(
            title: "Activate / Make Key",
            action: #selector(activateApp),
            keyEquivalent: "a")
        activateItem.target = self
        activateItem.keyEquivalentModifierMask = .command
        strategyMenu.addItem(activateItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        let closeItem = NSMenuItem(
            title: "Close Window",
            action: #selector(closeWindow),
            keyEquivalent: "w")
        closeItem.target = self
        closeItem.keyEquivalentModifierMask = .command
        windowMenu.addItem(closeItem)

        let recreateItem = NSMenuItem(
            title: "Recreate Window",
            action: #selector(recreateWindow),
            keyEquivalent: "n")
        recreateItem.target = self
        recreateItem.keyEquivalentModifierMask = .command
        windowMenu.addItem(recreateItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Window Management

    private func createAndShowWindow(preset: StrategyPreset) {
        let ctrl = ExperimentWindowController(preset: preset)
        ctrl.onWindowWillClose = { [weak self, weak ctrl] in
            guard let self, self.controller === ctrl else { return }
            self.controller = nil
        }
        controller = ctrl
        ctrl.showAndActivate()
    }

    // MARK: - Menu Actions

    @objc private func switchPresetFromMenu(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? StrategyPreset else { return }
        switchToPreset(preset)
    }

    private func switchToPreset(_ newPreset: StrategyPreset) {
        guard newPreset != currentPreset else { return }
        currentPreset = newPreset

        // Tear down old window, create new one with the new preset.
        controller?.close()
        controller = nil
        createAndShowWindow(preset: currentPreset)
    }

    @objc private func activateApp() {
        if controller == nil {
            createAndShowWindow(preset: currentPreset)
        } else {
            controller?.showAndActivate()
        }
    }

    @objc private func closeWindow() {
        controller?.close()
        controller = nil
    }

    @objc private func recreateWindow() {
        if controller != nil {
            controller?.close()
            controller = nil
        }
        createAndShowWindow(preset: currentPreset)
    }
}
