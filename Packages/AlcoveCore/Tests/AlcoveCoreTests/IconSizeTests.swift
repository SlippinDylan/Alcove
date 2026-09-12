import XCTest
@testable import AlcoveCore

final class IconSizeTests: XCTestCase {
    func testPresetValues() {
        XCTAssertEqual(IconSize.small.rawValue, 48)
        XCTAssertEqual(IconSize.medium.rawValue, 64)
        XCTAssertEqual(IconSize.large.rawValue, 80)
    }

    func testValidationIncludesBoundsAndRejectsInvalidValues() {
        XCTAssertNotNil(IconSize(rawValue: IconSize.minimum))
        XCTAssertNotNil(IconSize(rawValue: IconSize.maximum))
        XCTAssertNil(IconSize(rawValue: IconSize.minimum - 1))
        XCTAssertNil(IconSize(rawValue: IconSize.maximum + 1))
        XCTAssertNil(IconSize(rawValue: .nan))
    }

    func testFinderRangeIncludesSmallDesktopIcons() {
        XCTAssertEqual(IconSize.minimum, 16)
        XCTAssertNotNil(IconSize(rawValue: 16))
        XCTAssertNil(IconSize(rawValue: 15))
    }

    func testComparisonUsesRawValue() {
        XCTAssertLessThan(IconSize.small, IconSize.medium)
        XCTAssertLessThan(IconSize.medium, IconSize.large)
    }
}
