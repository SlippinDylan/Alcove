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

final class AppDelegateTests: XCTestCase {
    @MainActor
    func testApplicationLifecycleStartsAndStopsStatusMenu() {
        let spy = StatusMenuControllerSpy()
        let delegate = AppDelegate(statusMenuController: spy)

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(spy.startCount, 1)
        XCTAssertEqual(spy.stopCount, 1)
        XCTAssertEqual(NSApplication.shared.activationPolicy(), .accessory)
    }
}
