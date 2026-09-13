import CoreGraphics
import XCTest

@testable import AlcoveCore

final class PortalFrameReflowTests: XCTestCase {
    func testReflowInsetsEdgeAlignedPortalsAndExpandsTheirVerticalGap() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let upper = CGRect(x: 4, y: 496, width: 500, height: 400)
        let lower = CGRect(x: 4, y: 192, width: 500, height: 300)

        let result = try XCTUnwrap(PortalFrameReflow.reflowedFrames(
            [upper, lower],
            visibleFrame: visibleFrame,
            minimumGap: 20
        ))

        XCTAssertEqual(result[0], CGRect(x: 20, y: 480, width: 500, height: 400))
        XCTAssertEqual(result[1], CGRect(x: 20, y: 160, width: 500, height: 300))
        XCTAssertEqual(result[0].minY - result[1].maxY, 20)
    }

    func testReflowFromTheSameSavedFramesIsReversibleAcrossSpacingLevels() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let savedFrames = [
            CGRect(x: 4, y: 496, width: 500, height: 400),
            CGRect(x: 4, y: 192, width: 500, height: 300),
        ]

        let maximum = try XCTUnwrap(PortalFrameReflow.reflowedFrames(
            savedFrames,
            visibleFrame: visibleFrame,
            minimumGap: 20
        ))
        let minimum = try XCTUnwrap(PortalFrameReflow.reflowedFrames(
            savedFrames,
            visibleFrame: visibleFrame,
            minimumGap: 4
        ))

        XCTAssertNotEqual(maximum, minimum)
        XCTAssertEqual(minimum, savedFrames)
    }

    func testAttachedTwelvePointLayoutContractsToSelectedFourPointSpacing() throws {
        let visibleFrame = CGRect(x: 0, y: 46, width: 1000, height: 900)
        let savedFrames = [
            CGRect(x: 12, y: 534, width: 500, height: 400),
            CGRect(x: 12, y: 222, width: 500, height: 300),
        ]

        let result = try XCTUnwrap(PortalFrameReflow.reflowedFrames(
            savedFrames,
            visibleFrame: visibleFrame,
            minimumGap: 4
        ))

        XCTAssertEqual(result[0].minX, visibleFrame.minX + 4)
        XCTAssertEqual(result[0].maxY, visibleFrame.maxY - 4)
        XCTAssertEqual(result[0].minY - result[1].maxY, 4)
    }

    func testHorizontalAttachmentContractsWithoutPullingAnUnrelatedPortal() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let left = CGRect(x: 100, y: 500, width: 300, height: 200)
        let right = CGRect(x: 412, y: 500, width: 300, height: 200)
        let unrelated = CGRect(x: 700, y: 100, width: 300, height: 200)

        let result = try XCTUnwrap(PortalFrameReflow.reflowedFrames(
            [left, right, unrelated],
            visibleFrame: visibleFrame,
            minimumGap: 4
        ))

        XCTAssertEqual(result[1].minX - result[0].maxX, 4)
        XCTAssertEqual(result[2], unrelated)
    }

    func testReflowReturnsNilWhenFixedSizePortalsCannotFit() throws {
        let result = try PortalFrameReflow.reflowedFrames(
            [
                CGRect(x: 0, y: 0, width: 300, height: 300),
                CGRect(x: 0, y: 0, width: 300, height: 300),
            ],
            visibleFrame: CGRect(x: 0, y: 0, width: 320, height: 320),
            minimumGap: 20
        )

        XCTAssertNil(result)
    }
}
