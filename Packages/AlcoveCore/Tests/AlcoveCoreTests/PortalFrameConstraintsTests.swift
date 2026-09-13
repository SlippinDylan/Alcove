// PortalFrameConstraintsTests.swift
// AlcoveCore — Automated portal drag constraint tests.

import CoreGraphics
import XCTest

@testable import AlcoveCore

final class PortalFrameConstraintsTests: XCTestCase {

    private let visibleFrame = CGRect(x: 100, y: 50, width: 800, height: 600)
    private let portalSize = CGSize(width: 120, height: 100)

    private func frame(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: portalSize)
    }

    private func constrain(
        initial: CGRect,
        proposed: CGRect,
        others: [CGRect] = [],
        gap: CGFloat = PortalFrameConstraints.defaultMinimumGap
    ) throws -> CGRect {
        try PortalFrameConstraints.constrainedDragFrame(
            initialFrame: initial,
            proposedFrame: proposed,
            visibleFrame: visibleFrame,
            otherPortalFrames: others,
            minimumGap: gap
        )
    }

    func testUnobstructedDragReturnsProposedFrame() throws {
        let result = try constrain(
            initial: frame(200, 200),
            proposed: frame(500, 400)
        )

        XCTAssertEqual(result, frame(500, 400))
    }

    func testUnobstructedDragClampsAtEveryVisibleFrameEdge() throws {
        let result = try constrain(
            initial: frame(300, 300),
            proposed: frame(-100, 900)
        )

        XCTAssertEqual(result, frame(112, 538))
        XCTAssertTrue(visibleFrame.contains(result))
    }

    func testHorizontalDragStopsAtMinimumGapBeforePortal() throws {
        let obstacle = frame(500, 200)

        let result = try constrain(
            initial: frame(200, 200),
            proposed: frame(700, 200),
            others: [obstacle]
        )

        XCTAssertEqual(result, frame(368, 200))
        XCTAssertEqual(obstacle.minX - result.maxX, 12)
    }

    func testVerticalDragStopsAtMinimumGapBeforePortal() throws {
        let obstacle = frame(200, 400)

        let result = try constrain(
            initial: frame(200, 100),
            proposed: frame(200, 500),
            others: [obstacle]
        )

        XCTAssertEqual(result, frame(200, 288))
        XCTAssertEqual(obstacle.minY - result.maxY, 12)
    }

    func testDiagonalDragStopsAtFirstPortalCorner() throws {
        let obstacle = frame(500, 400)

        let result = try constrain(
            initial: frame(200, 100),
            proposed: frame(700, 500),
            others: [obstacle]
        )

        XCTAssertEqual(result, frame(435, 288))
        XCTAssertEqual(obstacle.minY - result.maxY, 12)
    }

    func testFastDragCannotPassThroughPortal() throws {
        let obstacle = frame(400, 200)

        let result = try constrain(
            initial: frame(120, 200),
            proposed: frame(780, 200),
            others: [obstacle]
        )

        XCTAssertEqual(result, frame(268, 200))
        XCTAssertEqual(obstacle.minX - result.maxX, 12)
    }

    func testDragPastOnePortalStopsAtFirstOfMultiplePortals() throws {
        let first = frame(400, 200)
        let second = frame(650, 200)

        let result = try constrain(
            initial: frame(120, 200),
            proposed: frame(780, 200),
            others: [second, first]
        )

        XCTAssertEqual(result, frame(268, 200))
    }

    func testPortalAtExactMinimumGapIsLegalAndCanMoveAway() throws {
        let obstacle = frame(500, 200)
        let initial = frame(368, 200)

        let result = try constrain(
            initial: initial,
            proposed: frame(200, 200),
            others: [obstacle]
        )

        XCTAssertEqual(result, frame(200, 200))
    }

    func testHorizontalPathThatPassesBelowPortalIsNotBlocked() throws {
        let obstacle = frame(500, 400)

        let result = try constrain(
            initial: frame(200, 100),
            proposed: frame(700, 100),
            others: [obstacle]
        )

        XCTAssertEqual(result, frame(700, 100))
    }

    func testZeroGapAllowsPortalEdgesToTouch() throws {
        let obstacle = frame(500, 200)

        let result = try constrain(
            initial: frame(200, 200),
            proposed: frame(700, 200),
            others: [obstacle],
            gap: 0
        )

        XCTAssertEqual(result, frame(380, 200))
        XCTAssertEqual(result.maxX, obstacle.minX)
    }

    func testPlacementRequiresGapFromEveryVisibleFrameEdge() throws {
        XCTAssertFalse(try PortalFrameConstraints.isValidPlacement(
            frame: frame(100, 200),
            visibleFrame: visibleFrame,
            otherPortalFrames: []
        ))
        XCTAssertTrue(try PortalFrameConstraints.isValidPlacement(
            frame: frame(112, 62),
            visibleFrame: visibleFrame,
            otherPortalFrames: []
        ))
    }

    func testPlacementRejectsOverlapAndInsufficientPortalGap() throws {
        let obstacle = frame(500, 200)

        XCTAssertFalse(try PortalFrameConstraints.isValidPlacement(
            frame: frame(390, 200),
            visibleFrame: visibleFrame,
            otherPortalFrames: [obstacle]
        ))
        XCTAssertTrue(try PortalFrameConstraints.isValidPlacement(
            frame: frame(368, 200),
            visibleFrame: visibleFrame,
            otherPortalFrames: [obstacle]
        ))
    }

    func testRejectsAProposedResize() {
        XCTAssertThrowsError(
            try PortalFrameConstraints.constrainedDragFrame(
                initialFrame: frame(200, 200),
                proposedFrame: CGRect(x: 300, y: 200, width: 140, height: 100),
                visibleFrame: visibleFrame,
                otherPortalFrames: []
            )
        ) { error in
            XCTAssertEqual(
                error as? PortalFrameConstraintError,
                .inconsistentFrameSize(
                    initial: self.portalSize,
                    proposed: CGSize(width: 140, height: 100)
                )
            )
        }
    }

    func testRejectsAnInitialFrameThatAlreadyOverlapsAnotherPortal() {
        XCTAssertThrowsError(
            try constrain(
                initial: frame(300, 200),
                proposed: frame(350, 200),
                others: [frame(400, 200)]
            )
        ) { error in
            XCTAssertEqual(
                error as? PortalFrameConstraintError,
                .initialFrameIntersectsOtherPortal
            )
        }
    }
}
