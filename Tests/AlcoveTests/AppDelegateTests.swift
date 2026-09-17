import AlcoveCore
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

    func restorePortals() async throws {
        restoreCount += 1
        if let error {
            throw error
        }
    }

    func createPortal(
        for folderURL: URL?,
        frame: NSRect?,
        gridCapacity: GridCapacity,
        iconLayout: PortalIconLayout
    ) async throws {
        if let error {
            throw error
        }
        if let folderURL {
            createdFolders.append(folderURL)
        }
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
    func testRelaunchControllerTerminatesThenLaunchesANewActivatedInstance() {
        let appURL = URL(fileURLWithPath: "/Applications/Alcove.app", isDirectory: true)
        var launchedURL: URL?
        var launchesNewInstance = false
        var activates = false
        var launchCount = 0
        var terminateCount = 0
        let controller = ApplicationRelaunchController(
            applicationURL: appURL,
            launchHandler: { url, configuration in
                launchCount += 1
                launchedURL = url
                launchesNewInstance = configuration.createsNewApplicationInstance
                activates = configuration.activates
            },
            terminateHandler: { terminateCount += 1 }
        )

        controller.requestRelaunch()

        XCTAssertEqual(terminateCount, 1)
        XCTAssertNil(launchedURL)

        controller.relaunchIfRequested()

        XCTAssertEqual(launchedURL, appURL)
        XCTAssertEqual(launchCount, 1)
        XCTAssertTrue(launchesNewInstance)
        XCTAssertTrue(activates)

        controller.relaunchIfRequested()
        XCTAssertEqual(launchCount, 1)
        XCTAssertEqual(terminateCount, 1)
    }

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

    func testInfoPlistDeclaresScopedFinderAutomationUsage() throws {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repositoryRoot.appending(path: "App/Resources/Info.plist")
        )
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(
            plist["NSAppleEventsUsageDescription"] as? String,
            "Alcove uses Finder automation only when you choose Get Info for a file or folder."
        )
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let localizationData = try Data(contentsOf: repositoryRoot.appending(
                path: "App/Resources/\(language).lproj/InfoPlist.strings"
            ))
            let localization = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: localizationData, format: nil)
                    as? [String: String]
            )
            XCTAssertFalse(localization["NSAppleEventsUsageDescription", default: ""].isEmpty)
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
