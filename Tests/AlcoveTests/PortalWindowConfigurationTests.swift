import AppKit
import XCTest
@testable import Alcove

final class PortalWindowConfigurationTests: XCTestCase {
    @MainActor
    func testDevelopmentStrategyAppliesToKeyEligiblePortalWindow() {
        let strategy = PortalWindowStrategy.developmentDefault
        let contentController = NSViewController()
        contentController.view = NSView()

        let window = PortalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            strategy: strategy,
            contentViewController: contentController
        )

        XCTAssertEqual(window.level, strategy.level)
        XCTAssertEqual(window.collectionBehavior, strategy.collectionBehavior)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize, NSSize(width: 240, height: 240))
    }

    @MainActor
    func testKeyEligibilityIsAnIndependentStrategyDimension() {
        let strategy = PortalWindowStrategy(
            level: .normal,
            collectionBehavior: [],
            canBecomeKey: false
        )
        let contentController = NSViewController()
        contentController.view = NSView()

        let window = PortalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            strategy: strategy,
            contentViewController: contentController
        )

        XCTAssertFalse(window.canBecomeKey)
        XCTAssertEqual(window.level, .normal)
        XCTAssertEqual(window.collectionBehavior, [])
    }
}
