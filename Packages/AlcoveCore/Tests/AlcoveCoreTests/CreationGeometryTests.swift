import XCTest
@testable import AlcoveCore

final class CreationGeometryTests: XCTestCase {
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

    func testMinimumPortalSizeDisplaysThreeColumnsAndOneRow() {
        XCTAssertEqual(metrics.minimumPortalSize, CGSize(width: 184, height: 80))
    }

    func testRectangleGrowsToThreeByOneMinimum() throws {
        let rectangle = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: 100, y: 100),
            currentPoint: CGPoint(x: 110, y: 110),
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(rectangle.frame, CGRect(x: 100, y: 100, width: 184, height: 120))
        XCTAssertEqual(rectangle.capacity, .minimum)
    }

    func testRectangleSnapsToNearestWholeCapacity() throws {
        let rectangle = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: 63, y: 81),
            currentPoint: CGPoint(x: 216, y: 269),
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(rectangle.frame, CGRect(x: 63, y: 81, width: 184, height: 200))
        XCTAssertEqual(rectangle.capacity, try GridCapacity(columns: 3, rows: 2))
    }

    func testRectanglePreservesNegativeDirection() throws {
        let rectangle = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: 330, y: 320),
            currentPoint: CGPoint(x: 200, y: 190),
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(rectangle.frame, CGRect(x: 146, y: 200, width: 184, height: 120))
        XCTAssertEqual(rectangle.frame.maxX, 330)
        XCTAssertEqual(rectangle.frame.maxY, 320)
    }

    func testRectangleSupportsMixedDragDirections() throws {
        let downThenLeft = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: 300, y: 100),
            currentPoint: CGPoint(x: 170, y: 250),
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            grid: try CreationGrid(metrics: metrics)
        )
        let upThenRight = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: 100, y: 300),
            currentPoint: CGPoint(x: 230, y: 150),
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(downThenLeft.frame, CGRect(x: 116, y: 100, width: 184, height: 120))
        XCTAssertEqual(upThenRight.frame, CGRect(x: 100, y: 180, width: 184, height: 120))
    }

    func testRectangleClampsPointsAndFinalSnapToVisibleFrame() throws {
        let visibleFrame = CGRect(x: -500, y: -300, width: 300, height: 250)
        let rectangle = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: -600, y: -400),
            currentPoint: CGPoint(x: -100, y: 20),
            visibleFrame: visibleFrame,
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(rectangle.frame, CGRect(x: -500, y: -300, width: 300, height: 200))
        XCTAssertEqual(rectangle.capacity, try GridCapacity(columns: 5, rows: 2))
    }

    func testSmallVisibleFrameUsesEntireVisibleArea() throws {
        let visibleFrame = CGRect(x: -40, y: 30, width: 100, height: 90)
        let rectangle = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: -20, y: 40),
            currentPoint: CGPoint(x: 50, y: 110),
            visibleFrame: visibleFrame,
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(rectangle.frame, visibleFrame)
        XCTAssertEqual(rectangle.capacity, .minimum)
    }

    func testHalfUnitThresholdCommitsCandidateColumnAndRow() throws {
        let grid = try CreationGrid(metrics: metrics)
        let visibleFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let belowThreshold = try CreationGeometry.rectangle(
            mouseDown: .zero,
            currentPoint: CGPoint(
                x: grid.minimumSize.width + grid.columnIncrement * 0.2,
                y: grid.minimumSize.height + grid.rowIncrement * 0.2
            ),
            visibleFrame: visibleFrame,
            grid: grid
        )
        let atThreshold = try CreationGeometry.rectangle(
            mouseDown: .zero,
            currentPoint: CGPoint(
                x: grid.minimumSize.width + grid.columnIncrement * 0.5,
                y: grid.minimumSize.height + grid.rowIncrement * 0.5
            ),
            visibleFrame: visibleFrame,
            grid: grid
        )

        XCTAssertEqual(belowThreshold.capacity, .minimum)
        XCTAssertEqual(belowThreshold.ghostColumnProgress, 0.4, accuracy: 0.001)
        XCTAssertEqual(belowThreshold.ghostRowProgress, 0.4, accuracy: 0.001)
        XCTAssertEqual(atThreshold.capacity, try GridCapacity(columns: 4, rows: 2))
        XCTAssertEqual(atThreshold.ghostColumnProgress, 0)
        XCTAssertEqual(atThreshold.ghostRowProgress, 0)
    }

    func testRectangleRejectsNonFiniteGestureAndDisplayValues() throws {
        let grid = try CreationGrid(metrics: metrics)
        XCTAssertThrowsError(
            try CreationGeometry.rectangle(
                mouseDown: CGPoint(x: CGFloat.nan, y: 0),
                currentPoint: .zero,
                visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
                grid: grid
            )
        ) { error in
            XCTAssertEqual(error as? CreationGeometryError, .nonFiniteValue("mouseDown"))
        }
        XCTAssertThrowsError(
            try CreationGeometry.rectangle(
                mouseDown: .zero,
                currentPoint: .zero,
                visibleFrame: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 400),
                grid: grid
            )
        ) { error in
            XCTAssertEqual(error as? CreationGeometryError, .nonFiniteValue("visibleFrame"))
        }
    }

    func testCreationGridRejectsInvalidMetrics() {
        let invalidMetrics = GridMetrics(iconSize: .small, horizontalSpacing: -.infinity)

        XCTAssertThrowsError(try CreationGrid(metrics: invalidMetrics)) { error in
            XCTAssertEqual(error as? CreationGeometryError, .invalidGridMetrics)
        }
    }

}
