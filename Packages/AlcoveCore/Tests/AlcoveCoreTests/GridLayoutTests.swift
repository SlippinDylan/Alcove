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
        XCTAssertEqual(metrics.minimumPortalSize, CGSize(width: 344, height: 140))
        XCTAssertEqual(GridMetrics(iconSize: .small).itemSize.width, 72)
        XCTAssertEqual(GridMetrics(iconSize: .large).itemSize.width, 120)
    }

    func testMinimumContainerSizeAllowsThreeColumns() {
        XCTAssertEqual(metrics.minimumContainerSize.width, 184)
        XCTAssertEqual(metrics.minimumContainerSize.height, 80)
    }

    func testLayoutNeverUsesFewerThanThreeColumns() {
        let result = GridLayout(metrics: metrics).layout(itemCount: 3, availableWidth: 30)

        XCTAssertEqual(result.columnCount, 3)
        XCTAssertEqual(result.contentSize, CGSize(width: 184, height: 80))
        XCTAssertEqual(result.itemFrames.count, 3)
        XCTAssertEqual(result.itemFrames[2].origin, CGPoint(x: 122, y: 8))
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

        XCTAssertEqual(result.columnCount, 3)
        XCTAssertEqual(result.contentSize, CGSize(width: 184, height: 12))
        XCTAssertTrue(result.itemFrames.isEmpty)
    }

    func testCapacityRequiresAtLeastThreeColumnsAndOneRow() {
        XCTAssertEqual(GridCapacity.minimum.columns, 3)
        XCTAssertEqual(GridCapacity.minimum.rows, 1)
        XCTAssertThrowsError(try GridCapacity(columns: 2, rows: 1)) { error in
            XCTAssertEqual(error as? GridCapacityError, .insufficientColumns(2))
        }
        XCTAssertThrowsError(try GridCapacity(columns: 3, rows: 0)) { error in
            XCTAssertEqual(error as? GridCapacityError, .insufficientRows(0))
        }
    }

    func testContentSizeAndNearestCapacityShareTheSameGridMath() throws {
        let capacity = try GridCapacity(columns: 5, rows: 3)

        XCTAssertEqual(metrics.contentSize(for: capacity), CGSize(width: 300, height: 240))
        XCTAssertEqual(
            try metrics.nearestCapacity(for: CGSize(width: 212.9, height: 119.9)),
            .minimum
        )
        XCTAssertEqual(
            try metrics.nearestCapacity(for: CGSize(width: 213, height: 120)),
            try GridCapacity(columns: 4, rows: 2)
        )
        XCTAssertThrowsError(
            try metrics.nearestCapacity(
                for: CGSize(width: CGFloat.infinity, height: 120)
            )
        ) { error in
            XCTAssertEqual(
                error as? GridCapacityError,
                .nonFiniteContentSize(CGSize(width: CGFloat.infinity, height: 120))
            )
        }
    }
}
