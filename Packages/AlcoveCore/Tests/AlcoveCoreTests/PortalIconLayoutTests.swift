import XCTest
@testable import AlcoveCore

final class PortalIconLayoutTests: XCTestCase {
    func testFixedLayoutProvidesIconAndStandardTextSizes() {
        XCTAssertEqual(PortalIconLayout.fixed(.small).iconSize, .small)
        XCTAssertEqual(PortalIconLayout.fixed(.small).textSize, 12)
    }
}
