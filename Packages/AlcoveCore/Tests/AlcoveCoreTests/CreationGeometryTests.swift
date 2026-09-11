import XCTest
@testable import AlcoveCore

final class CreationGeometryTests: XCTestCase {
    private let metrics = GridMetrics(
        iconSize: .small,
        labelHeight: 20,
        horizontalSpacing: 10,
        verticalSpacing: 12,
        contentInsets: GridInsets(top: 8, leading: 6, bottom: 4, trailing: 14)
    )

    func testMinimumPortalSizeDisplaysTwoColumnsAndRows() {
        XCTAssertEqual(metrics.minimumPortalSize, CGSize(width: 126, height: 160))
    }

    func testRectangleGrowsToTwoByTwoMinimum() throws {
        let rectangle = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: 100, y: 100),
            currentPoint: CGPoint(x: 110, y: 110),
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(rectangle.frame, CGRect(x: 58, y: 80, width: 126, height: 160))
        assert(rectangle.frame, contains: CGPoint(x: 100, y: 100))
        assert(rectangle.frame, contains: CGPoint(x: 110, y: 110))
    }

    func testRectangleSnapsSizeUpAndOriginToGrid() throws {
        let rectangle = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: 63, y: 81),
            currentPoint: CGPoint(x: 216, y: 269),
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(rectangle.frame, CGRect(x: 58, y: 80, width: 184, height: 240))
        assert(rectangle.frame, contains: CGPoint(x: 63, y: 81))
        assert(rectangle.frame, contains: CGPoint(x: 216, y: 269))
    }

    func testRectanglePreservesNegativeDirection() throws {
        let rectangle = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: 330, y: 320),
            currentPoint: CGPoint(x: 200, y: 190),
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(rectangle.frame, CGRect(x: 174, y: 160, width: 184, height: 160))
        assert(rectangle.frame, contains: CGPoint(x: 330, y: 320))
        assert(rectangle.frame, contains: CGPoint(x: 200, y: 190))
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

        XCTAssertEqual(downThenLeft.frame, CGRect(x: 116, y: 80, width: 184, height: 240))
        XCTAssertEqual(upThenRight.frame, CGRect(x: 58, y: 80, width: 184, height: 240))
        assert(downThenLeft.frame, contains: CGPoint(x: 300, y: 100))
        assert(downThenLeft.frame, contains: CGPoint(x: 170, y: 250))
        assert(upThenRight.frame, contains: CGPoint(x: 100, y: 300))
        assert(upThenRight.frame, contains: CGPoint(x: 230, y: 150))
    }

    func testRectangleClampsPointsAndFinalSnapToVisibleFrame() throws {
        let visibleFrame = CGRect(x: -500, y: -300, width: 300, height: 250)
        let rectangle = try CreationGeometry.rectangle(
            mouseDown: CGPoint(x: -600, y: -400),
            currentPoint: CGPoint(x: -100, y: 20),
            visibleFrame: visibleFrame,
            grid: try CreationGrid(metrics: metrics)
        )

        XCTAssertEqual(rectangle.frame, visibleFrame)
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

    private func assert(
        _ frame: CGRect,
        contains point: CGPoint,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(point.x, frame.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(point.x, frame.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(point.y, frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(point.y, frame.maxY, file: file, line: line)
    }
}
