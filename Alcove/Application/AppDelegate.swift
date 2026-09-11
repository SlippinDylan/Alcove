import AppKit

@MainActor
protocol StatusMenuControlling: AnyObject {
    func start()
    func stop()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusMenuController: any StatusMenuControlling
    private let portalCoordinator: any PortalCoordinating
    private let startupFolderURL: URL?
    private(set) var startupError: Error?
    private var startupTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?

    init(
        statusMenuController: any StatusMenuControlling,
        portalCoordinator: any PortalCoordinating,
        startupFolderURL: URL? = StartupFolderResolver.resolve(arguments: CommandLine.arguments)
    ) {
        self.statusMenuController = statusMenuController
        self.portalCoordinator = portalCoordinator
        self.startupFolderURL = startupFolderURL
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusMenuController.start()
        if let startupFolderURL {
            startupTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await portalCoordinator.restorePortals()
                    try await portalCoordinator.createPortal(for: startupFolderURL, frame: nil)
                } catch {
                    startupError = error
                }
            }
        } else {
            startupTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await portalCoordinator.restorePortals()
                } catch {
                    startupError = error
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        portalCoordinator.stop()
        statusMenuController.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        startupTask?.cancel()
        terminationTask = Task { [weak self] in
            if let self {
                await portalCoordinator.prepareForTermination()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func waitForStartupForTesting() async {
        await startupTask?.value
    }
}
