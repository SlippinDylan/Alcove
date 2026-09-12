import XCTest
@testable import Alcove

private final class StatusMenuControllerSpy: StatusMenuControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

}

private final class PortalCoordinatorSpy: PortalCoordinating {
    private(set) var createdFolders: [URL] = []
    private(set) var restoreCount = 0
    var error: Error?
    private(set) var stopCount = 0
    private(set) var desktopSettingsRefreshCount = 0

    func restorePortals() async throws {
        restoreCount += 1
        if let error {
            throw error
        }
    }

    func createPortal(for folderURL: URL, frame: NSRect?) async throws {
        if let error {
            throw error
        }
        createdFolders.append(folderURL)
    }

    func refreshFollowedDesktopIconSettings() async {
        desktopSettingsRefreshCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func prepareForTermination() async {}

}

private enum StartupFixtureError: Error, Equatable {
    case rejected
}

final class AppDelegateTests: XCTestCase {
    @MainActor
    func testApplicationLifecycleStartsAndStopsStatusMenu() async {
        let spy = StatusMenuControllerSpy()
        let portalSpy = PortalCoordinatorSpy()
        let startupFolder = URL(fileURLWithPath: "/tmp/alcove-startup-folder")
        let delegate = AppDelegate(
            statusMenuController: spy,
            portalCoordinator: portalSpy,
            startupFolderURL: startupFolder
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await delegate.waitForStartupForTesting()
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(spy.startCount, 1)
        XCTAssertEqual(spy.stopCount, 1)
        XCTAssertEqual(portalSpy.restoreCount, 1)
        XCTAssertEqual(portalSpy.createdFolders, [startupFolder])
        XCTAssertEqual(portalSpy.desktopSettingsRefreshCount, 1)
        XCTAssertEqual(portalSpy.stopCount, 1)
        XCTAssertNil(delegate.startupError)
        XCTAssertEqual(NSApplication.shared.activationPolicy(), .accessory)
    }

    @MainActor
    func testStartupPortalFailureIsRetained() async {
        let statusSpy = StatusMenuControllerSpy()
        let portalSpy = PortalCoordinatorSpy()
        portalSpy.error = StartupFixtureError.rejected
        let errorPresenter = StartupErrorPresenterSpy(resolutions: [.stop])
        var stopCount = 0
        let delegate = AppDelegate(
            statusMenuController: statusSpy,
            portalCoordinator: portalSpy,
            startupFolderURL: URL(fileURLWithPath: "/tmp/rejected"),
            startupErrorPresenter: errorPresenter,
            stopAfterStartupFailure: { stopCount += 1 }
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await delegate.waitForStartupForTesting()

        XCTAssertEqual(delegate.startupError as? StartupFixtureError, .rejected)
        XCTAssertTrue(portalSpy.createdFolders.isEmpty)
        XCTAssertEqual(errorPresenter.presentedErrors.count, 1)
        XCTAssertEqual(stopCount, 1)
    }

    @MainActor
    func testBecomingActiveRefreshesFollowedDesktopSettings() async {
        let coordinator = PortalCoordinatorSpy()
        let activeDelegate = AppDelegate(
            statusMenuController: StatusMenuControllerSpy(),
            portalCoordinator: coordinator,
            startupFolderURL: nil
        )

        activeDelegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )
        await activeDelegate.waitForDesktopSettingsRefreshForTesting()

        XCTAssertEqual(coordinator.desktopSettingsRefreshCount, 1)
    }

    @MainActor
    func testStartupRestoreCanRetryWithoutOverwritingState() async {
        let statusSpy = StatusMenuControllerSpy()
        let portalSpy = PortalCoordinatorSpy()
        portalSpy.error = StartupFixtureError.rejected
        let errorPresenter = StartupErrorPresenterSpy(resolutions: [.retry])
        errorPresenter.onPresent = { portalSpy.error = nil }
        var stopCount = 0
        let delegate = AppDelegate(
            statusMenuController: statusSpy,
            portalCoordinator: portalSpy,
            startupFolderURL: nil,
            startupErrorPresenter: errorPresenter,
            stopAfterStartupFailure: { stopCount += 1 }
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await delegate.waitForStartupForTesting()

        XCTAssertEqual(portalSpy.restoreCount, 2)
        XCTAssertNil(delegate.startupError)
        XCTAssertEqual(errorPresenter.presentedErrors.count, 1)
        XCTAssertEqual(stopCount, 0)
    }

    func testFinderReaderMapsDesktopIconAndTextSizes() async throws {
        let reader = FinderDesktopSettingsReader { source, promptIfNeeded in
            XCTAssertTrue(source.contains("icon view options of desktop window"))
            XCTAssertTrue(promptIfNeeded)
            return .success("64\n12")
        }

        let settings = try await reader.readDesktopIconSettings(promptIfNeeded: true)

        XCTAssertEqual(settings.iconSize, .medium)
        XCTAssertEqual(settings.textSize, 12)
    }

    func testFinderReaderCanRefreshWithoutRequestingPermission() async throws {
        let reader = FinderDesktopSettingsReader { _, promptIfNeeded in
            XCTAssertFalse(promptIfNeeded)
            return .success("80\n14")
        }

        let settings = try await reader.readDesktopIconSettings(promptIfNeeded: false)

        XCTAssertEqual(settings.iconSize, .large)
        XCTAssertEqual(settings.textSize, 14)
    }

    func testFinderReaderPreservesPermissionAndValidationFailures() async {
        let permission = FinderAppleScriptFailure(
            domain: "NSAppleScriptErrorDomain",
            code: -1743,
            message: "Not authorized to send Apple events to Finder."
        )
        await assertFinderError(
            .scriptExecutionFailed(permission),
            from: FinderDesktopSettingsReader { _, _ in
                .failure(.scriptExecutionFailed(permission))
            }
        )
        await assertFinderError(
            .invalidResultFormat("64,12"),
            from: FinderDesktopSettingsReader { _, _ in .success("64,12") }
        )
        await assertFinderError(
            .invalidIconSize(129),
            from: FinderDesktopSettingsReader { _, _ in .success("129\n12") }
        )
        await assertFinderError(
            .invalidTextSize(33),
            from: FinderDesktopSettingsReader { _, _ in .success("64\n33") }
        )
    }

    func testInfoPlistDescribesUserInitiatedFinderAutomation() throws {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repositoryRoot.appending(path: "Alcove/Resources/Info.plist")
        )
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(
            plist["NSAppleEventsUsageDescription"] as? String,
            "Alcove 仅在你启用“跟随桌面设置”后读取 Finder 桌面的图标和文字大小，并在启动或重新激活时同步。"
        )
    }

    private func assertFinderError(
        _ expected: FinderDesktopSettingsReaderError,
        from reader: FinderDesktopSettingsReader,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await reader.readDesktopIconSettings(promptIfNeeded: true)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as FinderDesktopSettingsReaderError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

@MainActor
private final class StartupErrorPresenterSpy: StartupErrorPresenting {
    private var resolutions: [StartupFailureResolution]
    private(set) var presentedErrors: [Error] = []
    var onPresent: (() -> Void)?

    init(resolutions: [StartupFailureResolution]) {
        self.resolutions = resolutions
    }

    func present(_ error: Error) -> StartupFailureResolution {
        presentedErrors.append(error)
        onPresent?()
        guard !resolutions.isEmpty else { return .stop }
        return resolutions.removeFirst()
    }
}
