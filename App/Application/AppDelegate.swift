import AppKit

@MainActor
protocol ApplicationRelaunching: AnyObject {
    func requestRelaunch()
    func relaunchIfRequested()
}

@MainActor
final class DisabledApplicationRelauncher: ApplicationRelaunching {
    func requestRelaunch() {}
    func relaunchIfRequested() {}
}

@MainActor
final class ApplicationRelaunchController: ApplicationRelaunching {
    typealias LaunchHandler = @MainActor (URL, NSWorkspace.OpenConfiguration) -> Void

    private let applicationURL: URL
    private let launchHandler: LaunchHandler
    private let terminateHandler: @MainActor () -> Void
    private var relaunchRequested = false

    init(
        applicationURL: URL = Bundle.main.bundleURL,
        launchHandler: @escaping LaunchHandler = { applicationURL, configuration in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { _, error in
                guard let error else { return }
                FileHandle.standardError.write(
                    Data("Unable to relaunch Alcove: \(error)\n".utf8)
                )
            }
        },
        terminateHandler: @escaping @MainActor () -> Void = {
            NSApplication.shared.terminate(nil)
        }
    ) {
        self.applicationURL = applicationURL
        self.launchHandler = launchHandler
        self.terminateHandler = terminateHandler
    }

    func requestRelaunch() {
        relaunchRequested = true
        terminateHandler()
    }

    func relaunchIfRequested() {
        guard relaunchRequested else { return }
        relaunchRequested = false
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        launchHandler(applicationURL, configuration)
    }
}

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
        alert.messageText = NSLocalizedString(
            "Unable to restore Alcove",
            comment: "Alert title shown when saved portals cannot be restored"
        )
        let informativeTextFormat = NSLocalizedString(
            "startup.restore.detail",
            comment: "Details shown when saved portals cannot be restored"
        )
        alert.informativeText = String(
            format: informativeTextFormat,
            PortalStore.defaultURL.path
        )
        alert.addButton(withTitle: NSLocalizedString("Retry", comment: "Retry button"))
        alert.addButton(
            withTitle: NSLocalizedString("Quit Alcove", comment: "Button to quit Alcove")
        )
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
    private let applicationRelauncher: any ApplicationRelaunching
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
        applicationRelauncher: any ApplicationRelaunching = DisabledApplicationRelauncher(),
        stopAfterStartupFailure: @escaping @MainActor () -> Void = {
            NSApplication.shared.terminate(nil)
        }
    ) {
        self.statusMenuController = statusMenuController
        self.portalCoordinator = portalCoordinator
        self.startupFolderURL = startupFolderURL
        self.startupErrorPresenter = startupErrorPresenter
        self.applicationRelauncher = applicationRelauncher
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
        applicationRelauncher.relaunchIfRequested()
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
                    try await portalCoordinator.createPortal(
                        for: startupFolderURL,
                        frame: nil,
                        gridCapacity: .minimum,
                        iconLayout: .fixed(.medium)
                    )
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
