import AlcoveCore
import AppKit
import CoreServices

protocol FinderDesktopSettingsReading: Sendable {
    func readDesktopIconSettings(promptIfNeeded: Bool) async throws -> DesktopIconSettings
}

struct FinderAppleScriptFailure: Equatable, Sendable {
    let domain: String
    let code: Int
    let message: String
}

enum FinderDesktopSettingsReaderError: Error, Equatable, Sendable {
    case scriptCreationFailed
    case automationPermissionRequired
    case automationPermissionDenied
    case automationPermissionCheckFailed(Int32)
    case scriptExecutionFailed(FinderAppleScriptFailure)
    case invalidResultFormat(String)
    case invalidIconSize(Double)
    case invalidTextSize(Double)
}

struct FinderDesktopSettingsReader: FinderDesktopSettingsReading {
    typealias ScriptExecutor = @Sendable (
        String,
        Bool
    ) -> Result<String, FinderDesktopSettingsReaderError>

    private static let queue = DispatchQueue(
        label: "com.dylanwang.alcove.finder-desktop-settings",
        qos: .userInitiated
    )

    private let executeScript: ScriptExecutor

    init(executeScript: @escaping ScriptExecutor = Self.executeAppleScript) {
        self.executeScript = executeScript
    }

    func readDesktopIconSettings(promptIfNeeded: Bool) async throws -> DesktopIconSettings {
        let execution = executeScript
        let result = await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(
                    returning: execution(Self.scriptSource, promptIfNeeded)
                )
            }
        }
        return try Self.desktopIconSettings(from: result.get())
    }

    private static let scriptSource = """
    tell application "Finder"
        set desktopOptions to icon view options of desktop window
        return (icon size of desktopOptions as text) & linefeed & (text size of desktopOptions as text)
    end tell
    """

    private static func executeAppleScript(
        _ source: String,
        promptIfNeeded: Bool
    ) -> Result<String, FinderDesktopSettingsReaderError> {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let targetDescriptor = target.aeDesc else {
            return .failure(.automationPermissionCheckFailed(OSStatus(paramErr)))
        }
        let permission = AEDeterminePermissionToAutomateTarget(
            targetDescriptor,
            AEEventClass(kAECoreSuite),
            AEEventID(kAEGetData),
            promptIfNeeded
        )
        if permission == OSStatus(errAEEventWouldRequireUserConsent) {
            return .failure(.automationPermissionRequired)
        }
        if permission == OSStatus(errAEEventNotPermitted) {
            return .failure(.automationPermissionDenied)
        }
        guard permission == noErr else {
            return .failure(.automationPermissionCheckFailed(permission))
        }

        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptCreationFailed)
        }

        var errorInfo: NSDictionary?
        guard script.compileAndReturnError(&errorInfo) else {
            return .failure(.scriptExecutionFailed(scriptFailure(from: errorInfo)))
        }

        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else {
            return .failure(.scriptExecutionFailed(scriptFailure(from: errorInfo)))
        }
        guard let output = result.stringValue else {
            return .failure(.invalidResultFormat("AppleScript returned a non-string result."))
        }
        return .success(output)
    }

    private static func desktopIconSettings(from output: String) throws -> DesktopIconSettings {
        let values = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard values.count == 2,
              let iconSize = Double(values[0]),
              let textSize = Double(values[1])
        else {
            throw FinderDesktopSettingsReaderError.invalidResultFormat(output)
        }
        guard iconSize.isFinite,
              let validatedIconSize = IconSize(rawValue: CGFloat(iconSize))
        else {
            throw FinderDesktopSettingsReaderError.invalidIconSize(iconSize)
        }
        guard textSize.isFinite,
              let settings = DesktopIconSettings(
                  iconSize: validatedIconSize,
                  textSize: CGFloat(textSize)
              )
        else {
            throw FinderDesktopSettingsReaderError.invalidTextSize(textSize)
        }
        return settings
    }

    private static func scriptFailure(from errorInfo: NSDictionary?) -> FinderAppleScriptFailure {
        FinderAppleScriptFailure(
            domain: "NSAppleScriptErrorDomain",
            code: errorInfo?[NSAppleScript.errorNumber] as? Int ?? 0,
            message: errorInfo?[NSAppleScript.errorMessage] as? String
                ?? "Finder did not provide an error message."
        )
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
    private var desktopSettingsRefreshTask: Task<Void, Never>?
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
        desktopSettingsRefreshTask?.cancel()
        portalCoordinator.stop()
        statusMenuController.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard desktopSettingsRefreshTask == nil else { return }
        desktopSettingsRefreshTask = Task { [weak self] in
            guard let self else { return }
            await portalCoordinator.refreshFollowedDesktopIconSettings()
            desktopSettingsRefreshTask = nil
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        startupTask?.cancel()
        desktopSettingsRefreshTask?.cancel()
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

    func waitForDesktopSettingsRefreshForTesting() async {
        await desktopSettingsRefreshTask?.value
    }

    private func restoreStartupState() async {
        while !Task.isCancelled {
            do {
                try await portalCoordinator.restorePortals()
                await portalCoordinator.refreshFollowedDesktopIconSettings()
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
