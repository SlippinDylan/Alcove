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

    func createPortal(for folderURL: URL, frame: NSRect?) async throws {
        if let error {
            throw error
        }
        createdFolders.append(folderURL)
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
}

@MainActor
private final class StartupErrorPresenterSpy: StartupErrorPresenting {
    private var resolutions: [StartupFailureResolution]
    private(set) var presentedErrors: [Error] = []

    init(resolutions: [StartupFailureResolution]) {
        self.resolutions = resolutions
    }

    func present(_ error: Error) -> StartupFailureResolution {
        presentedErrors.append(error)
        guard !resolutions.isEmpty else { return .stop }
        return resolutions.removeFirst()
    }
}
