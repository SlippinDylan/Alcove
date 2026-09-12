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

/// Schedules a repeating refresh while Finder is frontmost. The protocol keeps
/// Finder activation monitoring independent from a concrete run loop in tests.
@MainActor
protocol FinderRefreshTimerScheduling: AnyObject {
    func scheduleRepeating(
        every interval: TimeInterval,
        handler: @escaping @MainActor () -> Void
    ) -> any FinderRefreshTiming
}

@MainActor
protocol FinderRefreshTiming: AnyObject {
    func invalidate()
}

@MainActor
final class RunLoopFinderRefreshTimerScheduler: FinderRefreshTimerScheduling {
    func scheduleRepeating(
        every interval: TimeInterval,
        handler: @escaping @MainActor () -> Void
    ) -> any FinderRefreshTiming {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                handler()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return FinderRefreshTimer(timer: timer)
    }
}

@MainActor
private final class FinderRefreshTimer: FinderRefreshTiming {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func invalidate() {
        timer.invalidate()
    }
}

/// Runs a bounded refresh loop only while Finder is frontmost. It does not
/// perform Apple events itself, so observing Finder never prompts for access.
@MainActor
final class FinderActivationMonitor {
    typealias ApplicationIdentifier = @Sendable (Notification) -> String?
    typealias FrontmostApplicationIdentifier = @MainActor () -> String?

    private static let finderBundleIdentifier = "com.apple.finder"

    var onRefresh: (@MainActor () -> Void)?

    private let notificationCenter: NotificationCenter
    private let timerScheduler: any FinderRefreshTimerScheduling
    private let applicationIdentifier: ApplicationIdentifier
    private let frontmostApplicationIdentifier: FrontmostApplicationIdentifier
    private let refreshInterval: TimeInterval
    private var registration: FinderActivationRegistration?
    private var timer: (any FinderRefreshTiming)?
    private var isFinderActive = false
    private var timerGeneration: UInt64 = 0
    private var monitorGeneration: UInt64 = 0

    var isMonitoring: Bool {
        registration != nil
    }

    var isPolling: Bool {
        timer != nil
    }

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        timerScheduler: any FinderRefreshTimerScheduling = RunLoopFinderRefreshTimerScheduler(),
        refreshInterval: TimeInterval = 1,
        applicationIdentifier: @escaping ApplicationIdentifier = FinderActivationMonitor.bundleIdentifier,
        frontmostApplicationIdentifier: @escaping FrontmostApplicationIdentifier = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.notificationCenter = notificationCenter
        self.timerScheduler = timerScheduler
        self.refreshInterval = refreshInterval
        self.applicationIdentifier = applicationIdentifier
        self.frontmostApplicationIdentifier = frontmostApplicationIdentifier
    }

    func start() {
        guard registration == nil else {
            return
        }

        monitorGeneration &+= 1
        let generation = monitorGeneration
        let applicationIdentifier = applicationIdentifier
        let token = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let identifier = applicationIdentifier(notification)
            Task { @MainActor [weak self] in
                guard let self,
                      self.registration != nil,
                      self.monitorGeneration == generation else {
                    return
                }
                self.handleApplicationActivation(identifier)
            }
        }
        registration = FinderActivationRegistration(
            center: notificationCenter,
            token: token
        )
        handleApplicationActivation(frontmostApplicationIdentifier())
    }

    func stop() {
        monitorGeneration &+= 1
        registration = nil
        isFinderActive = false
        stopPolling()
    }

    private func handleApplicationActivation(_ identifier: String?) {
        guard let identifier else {
            return
        }

        if identifier == Self.finderBundleIdentifier {
            guard !isFinderActive else {
                return
            }
            isFinderActive = true
            startPolling()
            return
        }

        guard isFinderActive else {
            return
        }
        isFinderActive = false
        stopPolling()
        onRefresh?()
    }

    private func startPolling() {
        guard timer == nil else {
            return
        }

        timerGeneration &+= 1
        let generation = timerGeneration
        timer = timerScheduler.scheduleRepeating(every: refreshInterval) { [weak self] in
            guard let self,
                  self.isFinderActive,
                  self.timerGeneration == generation else {
                return
            }
            self.onRefresh?()
        }
    }

    private func stopPolling() {
        timerGeneration &+= 1
        timer?.invalidate()
        timer = nil
    }

    nonisolated private static func bundleIdentifier(from notification: Notification) -> String? {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else {
            return nil
        }
        return application.bundleIdentifier
    }
}

private final class FinderActivationRegistration {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(center: NotificationCenter, token: any NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    deinit {
        center.removeObserver(token)
    }
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
