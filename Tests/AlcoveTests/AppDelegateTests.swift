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
    var error: Error?

    func createPortal(for folderURL: URL) async throws {
        if let error {
            throw error
        }
        createdFolders.append(folderURL)
    }

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
        XCTAssertEqual(portalSpy.createdFolders, [startupFolder])
        XCTAssertNil(delegate.startupError)
        XCTAssertEqual(NSApplication.shared.activationPolicy(), .accessory)
    }

    @MainActor
    func testStartupPortalFailureIsRetained() async {
        let statusSpy = StatusMenuControllerSpy()
        let portalSpy = PortalCoordinatorSpy()
        portalSpy.error = StartupFixtureError.rejected
        let delegate = AppDelegate(
            statusMenuController: statusSpy,
            portalCoordinator: portalSpy,
            startupFolderURL: URL(fileURLWithPath: "/tmp/rejected")
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await delegate.waitForStartupForTesting()

        XCTAssertEqual(delegate.startupError as? StartupFixtureError, .rejected)
        XCTAssertTrue(portalSpy.createdFolders.isEmpty)
    }
}
