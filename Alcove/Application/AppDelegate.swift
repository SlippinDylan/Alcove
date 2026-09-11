import AppKit

enum StartupFailureResolution {
    case retry
    case stop
}

@MainActor
protocol StartupErrorPresenting: AnyObject {
    func present(_ error: Error) -> StartupFailureResolution
}

@MainActor
final class StartupErrorPresenter: StartupErrorPresenting {
    func present(_ error: Error) -> StartupFailureResolution {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Unable to restore Alcove"
        alert.informativeText = """
        Alcove could not load its saved portals. No saved data was changed.

        \(error.localizedDescription)

        Data file: \(PortalStore.defaultURL.path)
        """
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Quit Alcove")
        return alert.runModal() == .alertFirstButtonReturn ? .retry : .stop
    }
}

@MainActor
protocol StatusMenuControlling: AnyObject {
    func start()
    func stop()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusMenuController: any StatusMenuControlling
    private let portalCoordinator: any PortalCoordinating
    private let startupErrorPresenter: any StartupErrorPresenting
    private let stopAfterStartupFailure: @MainActor () -> Void
    private let startupFolderURL: URL?
    private(set) var startupError: Error?
    private var startupTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?

    init(
        statusMenuController: any StatusMenuControlling,
        portalCoordinator: any PortalCoordinating,
        startupFolderURL: URL? = StartupFolderResolver.resolve(arguments: CommandLine.arguments),
        startupErrorPresenter: any StartupErrorPresenting = StartupErrorPresenter(),
        stopAfterStartupFailure: @escaping @MainActor () -> Void = {
            NSApplication.shared.terminate(nil)
        }
    ) {
        self.statusMenuController = statusMenuController
        self.portalCoordinator = portalCoordinator
        self.startupFolderURL = startupFolderURL
        self.startupErrorPresenter = startupErrorPresenter
        self.stopAfterStartupFailure = stopAfterStartupFailure
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusMenuController.start()
        startupTask = Task { [weak self] in
            guard let self else { return }
            await restoreStartupState()
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

    private func restoreStartupState() async {
        while !Task.isCancelled {
            do {
                try await portalCoordinator.restorePortals()
                if let startupFolderURL {
                    try await portalCoordinator.createPortal(for: startupFolderURL, frame: nil)
                }
                startupError = nil
                return
            } catch is CancellationError {
                return
            } catch {
                startupError = error
                switch startupErrorPresenter.present(error) {
                case .retry:
                    continue
                case .stop:
                    stopAfterStartupFailure()
                    return
                }
            }
        }
    }
}
