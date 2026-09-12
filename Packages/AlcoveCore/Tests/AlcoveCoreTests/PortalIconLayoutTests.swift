import XCTest
@testable import AlcoveCore

final class PortalIconLayoutTests: XCTestCase {
    func testDesktopSettingsValidateTextSizeBoundsAndFiniteness() {
        XCTAssertNotNil(DesktopIconSettings(iconSize: .medium, textSize: 8))
        XCTAssertNotNil(DesktopIconSettings(iconSize: .medium, textSize: 32))
        XCTAssertNil(DesktopIconSettings(iconSize: .medium, textSize: 7.9))
        XCTAssertNil(DesktopIconSettings(iconSize: .medium, textSize: 32.1))
        XCTAssertNil(DesktopIconSettings(iconSize: .medium, textSize: .infinity))
    }

    func testLayoutDerivesIconAndTextSizes() throws {
        let desktop = try XCTUnwrap(
            DesktopIconSettings(iconSize: .large, textSize: 14)
        )

        XCTAssertEqual(PortalIconLayout.fixed(.small).iconSize, .small)
        XCTAssertEqual(
            PortalIconLayout.fixed(.small).textSize,
            DesktopIconSettings.defaultTextSize
        )
        XCTAssertEqual(PortalIconLayout.followDesktop(desktop).iconSize, .large)
        XCTAssertEqual(PortalIconLayout.followDesktop(desktop).textSize, 14)
    }
}
