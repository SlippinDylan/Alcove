// AppDelegate.swift
// Alcove Spike 0.1 — Desktop Window Experiment
// Disposable harness; not production architecture.

import AppKit

/// Application delegate for the Spike 0.1 harness.
///
/// Owns the experiment window controller (strong reference). Closing the window
/// nils the reference so the controller and window are deallocated cleanly;
/// "Recreate" creates a fresh instance. This avoids dangling/deallocated
/// controller problems.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var currentStrategy: WindowStrategy = .desktopCandidate
    private var controller: ExperimentWindowController?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        createAndShowWindow(strategy: currentStrategy)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            if controller == nil {
                createAndShowWindow(strategy: currentStrategy)
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

        // Strategy menu
        let strategyMenu = NSMenu(title: "Strategy")
        let strategyMenuItem = NSMenuItem()
        strategyMenuItem.submenu = strategyMenu
        mainMenu.addItem(strategyMenuItem)

        let normalItem = NSMenuItem(
            title: "Normal Baseline",
            action: #selector(switchToNormalBaseline),
            keyEquivalent: "1")
        normalItem.target = self
        normalItem.keyEquivalentModifierMask = .command
        strategyMenu.addItem(normalItem)

        let desktopItem = NSMenuItem(
            title: "Desktop Candidate",
            action: #selector(switchToDesktopCandidate),
            keyEquivalent: "2")
        desktopItem.target = self
        desktopItem.keyEquivalentModifierMask = .command
        strategyMenu.addItem(desktopItem)

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

    private func createAndShowWindow(strategy: WindowStrategy) {
        let ctrl = ExperimentWindowController(strategy: strategy)
        controller = ctrl
        ctrl.showAndActivate()
    }

    // MARK: - Menu Actions

    @objc private func switchToNormalBaseline() {
        switchStrategy(.normalBaseline)
    }

    @objc private func switchToDesktopCandidate() {
        switchStrategy(.desktopCandidate)
    }

    private func switchStrategy(_ newStrategy: WindowStrategy) {
        guard newStrategy != currentStrategy else { return }
        currentStrategy = newStrategy

        // Tear down old window, create new one with the new strategy.
        controller?.close()
        controller = nil
        createAndShowWindow(strategy: currentStrategy)
    }

    @objc private func activateApp() {
        if controller == nil {
            createAndShowWindow(strategy: currentStrategy)
        } else {
            controller?.showAndActivate()
        }
    }

    @objc private func closeWindow() {
        controller?.close()
        // controller reference remains until explicitly nilled;
        // windowWillClose fires but does not deallocate us.
        // Nil it now so recreate creates fresh.
        controller = nil
    }

    @objc private func recreateWindow() {
        if controller != nil {
            controller?.close()
            controller = nil
        }
        createAndShowWindow(strategy: currentStrategy)
    }
}
