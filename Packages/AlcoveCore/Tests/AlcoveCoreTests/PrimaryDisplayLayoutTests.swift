import CoreGraphics
import XCTest

@testable import AlcoveCore

final class PrimaryDisplayLayoutTests: XCTestCase {
    func testTopLeftProjectionPreservesPointOffsets() throws {
        let source = CGRect(x: 0, y: 46, width: 3008, height: 1616)
        let target = CGRect(x: -1800, y: 155, width: 1800, height: 1130)
        let frame = CGRect(x: 128, y: source.maxY - 128 - 200, width: 300, height: 200)

        let projected = try PrimaryDisplayLayout.projectTopLeft(
            frame: frame,
            from: source,
            to: target
        )

        XCTAssertEqual(projected.minX - target.minX, 128)
        XCTAssertEqual(target.maxY - projected.maxY, 128)
        XCTAssertEqual(projected.size, frame.size)
    }

    func testOverflowRowsOpenANewColumnWithoutMovingContainedFrames() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 400, height: 310)
        let frames = [
            CGRect(x: 10, y: 210, width: 100, height: 90),
            CGRect(x: 120, y: 210, width: 100, height: 90),
            CGRect(x: 10, y: 110, width: 100, height: 90),
            CGRect(x: 120, y: 110, width: 100, height: 90),
            CGRect(x: 10, y: 10, width: 100, height: 90),
            CGRect(x: 120, y: 10, width: 100, height: 90),
            CGRect(x: 10, y: -90, width: 100, height: 90),
            CGRect(x: 120, y: -90, width: 100, height: 90),
        ]
        let fixed = try PrimaryDisplayLayout.containedIndices(
            in: frames,
            visibleFrame: visibleFrame,
            minimumGap: 10
        )

        let repaired = try PrimaryDisplayLayout.repairOverflow(
            candidateFrames: frames,
            fixedIndices: fixed,
            visibleFrame: visibleFrame,
            minimumGap: 10,
            minimumExposedHeight: 40
        )

        XCTAssertEqual(Array(repaired.prefix(6)), Array(frames.prefix(6)))
        XCTAssertEqual(repaired[6], CGRect(x: 230, y: 210, width: 100, height: 90))
        XCTAssertEqual(repaired[7], CGRect(x: 230, y: 110, width: 100, height: 90))
    }

    func testFallbackUsesDistinctTopLeftSlotsBeforeItMustRepeat() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 220, height: 180)
        let frames = (0..<6).map { index in
            CGRect(x: 0, y: -CGFloat(index + 1) * 200, width: 200, height: 160)
        }

        let repaired = try PrimaryDisplayLayout.repairOverflow(
            candidateFrames: frames,
            fixedIndices: [],
            visibleFrame: visibleFrame,
            minimumGap: 10,
            minimumExposedHeight: 40
        )

        for frame in repaired {
            XCTAssertGreaterThanOrEqual(frame.maxY, visibleFrame.minY + 10 + 40)
            XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - 10)
            XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX + 10)
            XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - 10)
        }
        let topLeftSlots = repaired.map { CGPoint(x: $0.minX, y: $0.maxY) }
        XCTAssertEqual(Set(topLeftSlots).count, 4)
        XCTAssertEqual(topLeftSlots[0], CGPoint(x: 10, y: 170))
        XCTAssertNotEqual(topLeftSlots[0], topLeftSlots[1])
    }

    func testContainedIndicesRejectsAFrameCollidingWithAnEarlierFixedFrame() throws {
        let frames = [
            CGRect(x: 10, y: 100, width: 100, height: 100),
            CGRect(x: 50, y: 120, width: 100, height: 100),
            CGRect(x: 200, y: 100, width: 100, height: 100),
        ]

        let fixed = try PrimaryDisplayLayout.containedIndices(
            in: frames,
            visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 300),
            minimumGap: 10
        )

        XCTAssertEqual(fixed, [0, 2])
    }

    func testRepairRejectsVisibleFrameConsumedByTheMinimumGap() {
        XCTAssertThrowsError(try PrimaryDisplayLayout.repairOverflow(
            candidateFrames: [],
            fixedIndices: [],
            visibleFrame: CGRect(x: 0, y: 0, width: 30, height: 30),
            minimumGap: 20,
            minimumExposedHeight: 10
        )) { error in
            XCTAssertEqual(
                error as? PrimaryDisplayLayoutError,
                .insufficientUsableSize(.zero)
            )
        }
    }

    func testRepairRejectsInvalidFixedIndex() {
        XCTAssertThrowsError(try PrimaryDisplayLayout.repairOverflow(
            candidateFrames: [CGRect(x: 0, y: 0, width: 100, height: 100)],
            fixedIndices: [1],
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 500),
            minimumGap: 10,
            minimumExposedHeight: 40
        )) { error in
            XCTAssertEqual(error as? PrimaryDisplayLayoutError, .invalidFixedIndex(1))
        }
    }
}
