import AppKit

@MainActor
protocol StatusMenuControlling: AnyObject {
    func start()
    func stop()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusMenuController: any StatusMenuControlling

    init(statusMenuController: any StatusMenuControlling = StatusMenuController()) {
        self.statusMenuController = statusMenuController
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusMenuController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusMenuController.stop()
    }
}
