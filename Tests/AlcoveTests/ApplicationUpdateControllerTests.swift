import XCTest
@testable import Alcove

final class ApplicationUpdateControllerTests: XCTestCase {
    @MainActor
    func testDisabledUpdaterCannotCheckForUpdates() {
        let controller = ApplicationUpdateController(
            updaterEnabled: false,
            updateChannel: "stable"
        )

        XCTAssertFalse(controller.canCheckForUpdates)
        controller.checkForUpdates()
    }

    @MainActor
    func testStableBuildUsesOnlyTheDefaultChannel() {
        XCTAssertEqual(ApplicationUpdateController.allowedChannels(for: "stable"), [])
    }

    @MainActor
    func testBetaBuildAlsoReceivesBetaUpdates() {
        XCTAssertEqual(ApplicationUpdateController.allowedChannels(for: "beta"), ["beta"])
    }

    @MainActor
    func testAlphaBuildReceivesAlphaAndBetaUpdates() {
        XCTAssertEqual(
            ApplicationUpdateController.allowedChannels(for: "alpha"),
            ["alpha", "beta"]
        )
    }
}
