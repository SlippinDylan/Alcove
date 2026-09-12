import XCTest
@testable import AlcoveCore

final class GridLayoutTests: XCTestCase {
    private let metrics = GridMetrics(
        iconSize: .small,
        labelHeight: 20,
        itemHorizontalPadding: 0,
        iconSelectionPadding: 0,
        iconLabelSpacing: 0,
        horizontalSpacing: 10,
        verticalSpacing: 12,
        contentInsets: GridInsets(top: 8, leading: 6, bottom: 4, trailing: 14)
    )

    func testDefaultMetricsProvideDesktopStyleTileSpaceAroundTheIcon() {
        let metrics = GridMetrics(iconSize: .medium)

        XCTAssertEqual(metrics.iconSelectionSize, CGSize(width: 72, height: 72))
        XCTAssertEqual(metrics.itemSize, CGSize(width: 96, height: 108))
        XCTAssertEqual(metrics.horizontalSpacing, 12)
        XCTAssertEqual(metrics.verticalSpacing, 4)
        XCTAssertEqual(metrics.minimumPortalSize, CGSize(width: 236, height: 252))
        XCTAssertEqual(GridMetrics(iconSize: .small).itemSize.width, 72)
        XCTAssertEqual(GridMetrics(iconSize: .large).itemSize.width, 120)
    }

    func testMinimumContainerSizeAllowsTwoColumns() {
        XCTAssertEqual(metrics.minimumContainerSize.width, 126)
        XCTAssertEqual(metrics.minimumContainerSize.height, 80)
    }

    func testLayoutNeverUsesFewerThanTwoColumns() {
        let result = GridLayout(metrics: metrics).layout(itemCount: 3, availableWidth: 30)

        XCTAssertEqual(result.columnCount, 2)
        XCTAssertEqual(result.contentSize, CGSize(width: 126, height: 160))
        XCTAssertEqual(result.itemFrames.count, 3)
        XCTAssertEqual(result.itemFrames[2].origin, CGPoint(x: 6, y: 88))
    }

    func testLayoutDerivesColumnsAndFramesFromAvailableWidth() {
        let result = GridLayout(metrics: metrics).layout(itemCount: 5, availableWidth: 190)

        XCTAssertEqual(result.columnCount, 3)
        XCTAssertEqual(result.contentSize, CGSize(width: 190, height: 160))
        XCTAssertEqual(result.itemFrames[2], CGRect(x: 122, y: 8, width: 48, height: 68))
        XCTAssertEqual(result.itemFrames[3], CGRect(x: 6, y: 88, width: 48, height: 68))
    }

    func testEmptyLayoutKeepsOnlyInsetsInItsHeight() {
        let result = GridLayout(metrics: metrics).layout(itemCount: 0, availableWidth: 126)

        XCTAssertEqual(result.columnCount, 2)
        XCTAssertEqual(result.contentSize, CGSize(width: 126, height: 12))
        XCTAssertTrue(result.itemFrames.isEmpty)
    }
}
