// PlacementStateMachineTests.swift
// AlcoveCore — Primary-display-following placement state tests.

import CoreGraphics
import XCTest

@testable import AlcoveCore

final class PlacementStateMachineTests: XCTestCase {
    private let homeID = DisplayIdentity(rawValue: "home")
    private let primaryID = DisplayIdentity(rawValue: "primary")
    private let otherID = DisplayIdentity(rawValue: "other")

    func testDisconnectEvictsToPrimaryWithoutChangingHomePlacement() throws {
        let original = try makeSession()
        let transition = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [descriptor(primaryID, x: 0, width: 1200)],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(transition.session.homeDisplay, homeID)
        XCTAssertEqual(transition.session.placements, original.placements)
        XCTAssertEqual(transition.session.presentation, .temporarilyDisplaced(to: primaryID))
        let directive = try XCTUnwrap(transition.directive)
        XCTAssertEqual(directive.targetDisplay, primaryID)
        XCTAssertEqual(directive.reason, .followPrimaryDisplay)
        assertContained(directive.frame, in: descriptor(primaryID, x: 0, width: 1200).visibleFrame)
    }

    func testRepeatedPrimaryFollowingDoesNotMutateHomePlacement() throws {
        let original = try makeSession()
        let first = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [descriptor(primaryID, x: 0, width: 1200)],
            primaryDisplay: primaryID
        )
        let second = try PlacementStateMachine.reconcileTopology(
            session: first.session,
            displays: [descriptor(primaryID, x: 50, width: 1000)],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(second.session.placements, original.placements)
        XCTAssertEqual(second.session.homeDisplay, homeID)
        XCTAssertEqual(second.directive?.reason, .followPrimaryDisplay)
    }

    func testAvailableHomeDoesNotOverrideCurrentPrimaryDisplay() throws {
        let original = try makeSession()
        let displaced = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [descriptor(primaryID, x: 0, width: 1200)],
            primaryDisplay: primaryID
        )
        let returnedHome = descriptor(homeID, x: -1600, width: 1600)
        let restored = try PlacementStateMachine.reconcileTopology(
            session: displaced.session,
            displays: [descriptor(primaryID, x: 0, width: 1200), returnedHome],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(restored.session.placements, original.placements)
        XCTAssertEqual(restored.session.homeDisplay, homeID)
        XCTAssertEqual(restored.session.presentation, .temporarilyDisplaced(to: primaryID))
        XCTAssertEqual(restored.directive?.targetDisplay, primaryID)
        XCTAssertEqual(restored.directive?.reason, .followPrimaryDisplay)
        XCTAssertEqual(restored.directive?.frame, CGRect(x: 600, y: 250, width: 400, height: 300))
    }

    func testChangedNonPrimaryGeometryDoesNotMovePortalOffPrimary() throws {
        let original = try makeSession()
        let changedHome = descriptor(homeID, x: -2000, width: 2000, height: 1000)
        let transition = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [descriptor(primaryID, x: 0, width: 1200), changedHome],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(transition.session.placements, original.placements)
        XCTAssertEqual(transition.directive?.reason, .followPrimaryDisplay)
        XCTAssertEqual(transition.directive?.frame.origin, CGPoint(x: 600, y: 250))
        XCTAssertEqual(transition.directive?.frame.size, CGSize(width: 400, height: 300))
    }

    func testNonPrimaryRearrangementDoesNotChangePrimaryPresentation() throws {
        let original = try makeSession()
        let rearranged = descriptor(homeID, x: 1200, width: 1600)
        let transition = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [descriptor(primaryID, x: 0, width: 1200), rearranged],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(transition.session.homeDisplay, homeID)
        XCTAssertEqual(transition.session.placements, original.placements)
        XCTAssertEqual(transition.directive?.targetDisplay, primaryID)
        XCTAssertEqual(transition.directive?.frame.origin, CGPoint(x: 600, y: 250))
    }

    func testSystemFrameChangeNeverWritesPlacement() throws {
        let original = try makeSession()
        let systemFrame = CGRect(x: 50, y: 50, width: 300, height: 200)
        let updated = try PlacementStateMachine.recordFrameChange(
            session: original,
            frame: systemFrame,
            display: descriptor(primaryID, x: 0, width: 1200),
            origin: .system
        )

        XCTAssertEqual(updated.placements, original.placements)
        XCTAssertEqual(updated.homeDisplay, homeID)
        XCTAssertEqual(updated.presentation, .temporarilyDisplaced(to: primaryID))
    }

    func testUserMoveOnFallbackExplicitlyChangesHome() throws {
        let original = try makeSession()
        let primary = descriptor(primaryID, x: 0, width: 1200)
        let userFrame = CGRect(x: 100, y: 150, width: 500, height: 350)
        let updated = try PlacementStateMachine.recordFrameChange(
            session: original,
            frame: userFrame,
            display: primary,
            origin: .userInteractionEnded
        )

        XCTAssertEqual(updated.homeDisplay, primaryID)
        XCTAssertEqual(updated.presentation, .active(on: primaryID))
        XCTAssertEqual(updated.placements[primaryID]?.absoluteFrame, userFrame)
        XCTAssertEqual(updated.placements[primaryID]?.preferredSize, userFrame.size)
        XCTAssertEqual(updated.placements[homeID], original.placements[homeID])
    }

    func testOldHomeReturnDoesNotOverrideNewUserChosenHome() throws {
        let original = try makeSession()
        let primary = descriptor(primaryID, x: 0, width: 1200)
        let userFrame = CGRect(x: 100, y: 150, width: 500, height: 350)
        let userMoved = try PlacementStateMachine.recordFrameChange(
            session: original,
            frame: userFrame,
            display: primary,
            origin: .userInteractionEnded
        )
        let transition = try PlacementStateMachine.reconcileTopology(
            session: userMoved,
            displays: [primary, descriptor(homeID, x: -1600, width: 1600)],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(transition.session.homeDisplay, primaryID)
        XCTAssertEqual(transition.directive?.targetDisplay, primaryID)
        XCTAssertEqual(transition.directive?.frame, userFrame)
    }

    func testUnrelatedSavedDisplayDoesNotOverridePrimaryPresentation() throws {
        let original = try makeSession()
        let other = descriptor(otherID, x: 2000, width: 1000)
        let otherRecord = try PlacementGeometry.capture(
            windowFrame: CGRect(x: 2200, y: 100, width: 300, height: 250),
            visibleFrame: other.visibleFrame
        )
        var placements = original.placements
        placements[otherID] = otherRecord
        let session = try PlacementSession(
            placements: placements,
            homeDisplay: homeID,
            presentation: .active(on: homeID)
        )
        let transition = try PlacementStateMachine.reconcileTopology(
            session: session,
            displays: [
                descriptor(primaryID, x: 0, width: 1200),
                descriptor(homeID, x: -1600, width: 1600),
                other,
            ],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(transition.session.homeDisplay, homeID)
        XCTAssertEqual(transition.directive?.targetDisplay, primaryID)
        XCTAssertEqual(transition.session.placements, placements)
    }

    func testRememberedPrimaryPlacementWinsOverHomeProjection() throws {
        let original = try makeSession()
        let primary = descriptor(primaryID, x: 0, width: 1200)
        let primaryFrame = CGRect(x: 100, y: 120, width: 400, height: 300)
        let primaryRecord = try PlacementGeometry.capture(
            windowFrame: primaryFrame,
            visibleFrame: primary.visibleFrame
        )
        var placements = original.placements
        placements[primaryID] = primaryRecord
        let session = try PlacementSession(
            placements: placements,
            homeDisplay: homeID,
            presentation: .active(on: homeID)
        )

        let transition = try PlacementStateMachine.reconcileTopology(
            session: session,
            displays: [primary, descriptor(homeID, x: -1600, width: 1600)],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(transition.directive?.targetDisplay, primaryID)
        XCTAssertEqual(transition.directive?.frame, primaryFrame)
        XCTAssertEqual(transition.session.placements, placements)
    }

    func testOversizedPortalIsCenteredAndConstrainedOnFallback() throws {
        let original = try makeSession(
            frame: CGRect(x: -1600, y: 0, width: 1600, height: 800)
        )
        let primary = descriptor(primaryID, x: 100, width: 900, height: 600)
        let transition = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [primary],
            primaryDisplay: primaryID
        )
        let frame = try XCTUnwrap(transition.directive?.frame)

        XCTAssertEqual(frame, primary.visibleFrame)
        XCTAssertEqual(transition.session.placements, original.placements)
    }

    func testSystemMoveBackToHomeOnlyChangesTransientPresentation() throws {
        let original = try makeSession()
        let displaced = try PlacementStateMachine.recordFrameChange(
            session: original,
            frame: .zero,
            display: descriptor(otherID, x: 2000, width: 1000),
            origin: .system
        )
        let returned = try PlacementStateMachine.recordFrameChange(
            session: displaced,
            frame: .zero,
            display: descriptor(homeID, x: -1600, width: 1600),
            origin: .system
        )

        XCTAssertEqual(returned.placements, original.placements)
        XCTAssertEqual(returned.homeDisplay, homeID)
        XCTAssertEqual(returned.presentation, .active(on: homeID))
    }

    func testGridSnapIsAppliedToFallbackAfterSizeAndAnchorRestore() throws {
        let original = try makeSession(frame: CGRect(x: -1190, y: 255, width: 410, height: 310))
        let primary = descriptor(primaryID, x: 5, width: 1000, height: 700)
        let transition = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [primary],
            primaryDisplay: primaryID,
            gridSpacing: .snap(50)
        )

        let directive = try XCTUnwrap(transition.directive)
        XCTAssertEqual((directive.frame.minX - primary.visibleFrame.minX).truncatingRemainder(dividingBy: 50), 0)
        XCTAssertEqual((directive.frame.minY - primary.visibleFrame.minY).truncatingRemainder(dividingBy: 50), 0)
        XCTAssertEqual(directive.frame, CGRect(x: 405, y: 150, width: 410, height: 310))
        assertContained(directive.frame, in: primary.visibleFrame)
    }

    func testInvalidTopologyErrorsAreExplicit() throws {
        let session = try makeSession()
        let primary = descriptor(primaryID, x: 0, width: 1200)
        XCTAssertThrowsError(
            try PlacementStateMachine.reconcileTopology(
                session: session,
                displays: [primary, primary],
                primaryDisplay: primaryID
            )
        ) { XCTAssertEqual($0 as? PlacementStateError, .duplicateDisplayIdentity(primaryID)) }

        XCTAssertThrowsError(
            try PlacementStateMachine.reconcileTopology(
                session: session,
                displays: [descriptor(otherID, x: 0, width: 1200)],
                primaryDisplay: primaryID
            )
        ) { XCTAssertEqual($0 as? PlacementStateError, .primaryDisplayUnavailable(primaryID)) }
    }

    func testReconciliationRequiresDeclaredPrimaryDisplay() throws {
        let session = try makeSession()
        XCTAssertThrowsError(try PlacementStateMachine.reconcileTopology(
            session: session,
            displays: [descriptor(homeID, x: -1600, width: 1600)],
            primaryDisplay: primaryID
        )) { error in
            XCTAssertEqual(
                error as? PlacementStateError,
                .primaryDisplayUnavailable(primaryID)
            )
        }
    }

    func testNonPrimaryReturnNeverOverridesPrimaryOrWritesMemory() throws {
        let original = try makeSession()
        let displaced = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [descriptor(primaryID, x: 0, width: 1200)],
            primaryDisplay: primaryID
        )
        let returnedHome = descriptor(homeID, x: -2000, width: 2000, height: 1000)
        let restored = try PlacementStateMachine.reconcileTopology(
            session: displaced.session,
            displays: [descriptor(primaryID, x: 0, width: 1200), returnedHome],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(restored.session.placements, original.placements)
        XCTAssertEqual(restored.session.homeDisplay, homeID)
        XCTAssertEqual(restored.directive?.reason, .followPrimaryDisplay)
        XCTAssertEqual(restored.directive?.targetDisplay, primaryID)
        XCTAssertEqual(restored.directive?.frame, CGRect(x: 600, y: 250, width: 400, height: 300))
    }

    func testFallbackMovesToNewPrimaryWithoutWritingMemory() throws {
        let original = try makeSession()
        let first = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [descriptor(primaryID, x: 0, width: 1200)],
            primaryDisplay: primaryID
        )
        let newPrimary = descriptor(otherID, x: 1800, width: 1000, height: 700)
        let second = try PlacementStateMachine.reconcileTopology(
            session: first.session,
            displays: [newPrimary],
            primaryDisplay: otherID
        )

        XCTAssertEqual(second.session.placements, original.placements)
        XCTAssertEqual(second.session.homeDisplay, homeID)
        XCTAssertEqual(second.session.presentation, .temporarilyDisplaced(to: otherID))
        XCTAssertEqual(second.directive?.targetDisplay, otherID)
        XCTAssertEqual(second.directive?.frame, CGRect(x: 2400, y: 150, width: 400, height: 300))
    }

    func testTopologyFailuresLeaveCompleteSessionUnchanged() throws {
        let original = try makeSession()
        let invalidHome = DisplayDescriptor(
            identity: homeID,
            visibleFrame: CGRect(x: 0, y: 0, width: 0, height: 800)
        )
        XCTAssertThrowsError(
            try PlacementStateMachine.reconcileTopology(
                session: original,
                displays: [invalidHome],
                primaryDisplay: homeID
            )
        )

        let invalidFallback = DisplayDescriptor(
            identity: primaryID,
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 0)
        )
        XCTAssertThrowsError(
            try PlacementStateMachine.reconcileTopology(
                session: original,
                displays: [invalidFallback],
                primaryDisplay: primaryID
            )
        )

        XCTAssertThrowsError(
            try PlacementStateMachine.reconcileTopology(
                session: original,
                displays: [descriptor(homeID, x: -1600, width: 1600)],
                primaryDisplay: homeID,
                gridSpacing: .snap(0)
            )
        )
        XCTAssertEqual(original, try makeSession())
    }

    func testEmptyTopologyDefersWithoutChangingMemory() throws {
        let original = try makeSession()
        let transition = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(transition.session.placements, original.placements)
        XCTAssertEqual(transition.session.homeDisplay, original.homeDisplay)
        XCTAssertEqual(transition.session.presentation, .awaitingDisplay)
        XCTAssertNil(transition.directive)
    }

    func testDisplayAfterEmptyTopologyContinuesPrimaryFollowing() throws {
        let original = try makeSession()
        let waiting = try PlacementStateMachine.reconcileTopology(
            session: original,
            displays: [],
            primaryDisplay: primaryID
        )
        let resumed = try PlacementStateMachine.reconcileTopology(
            session: waiting.session,
            displays: [descriptor(primaryID, x: 0, width: 1200)],
            primaryDisplay: primaryID
        )

        XCTAssertEqual(resumed.session.homeDisplay, homeID)
        XCTAssertEqual(resumed.session.presentation, .temporarilyDisplaced(to: primaryID))
        XCTAssertEqual(resumed.directive?.reason, .followPrimaryDisplay)
    }

    func testInvalidUserFrameDoesNotMutateSession() throws {
        let original = try makeSession()
        let invalid = CGRect(x: CGFloat.infinity, y: 0, width: 300, height: 200)
        XCTAssertThrowsError(
            try PlacementStateMachine.recordFrameChange(
                session: original,
                frame: invalid,
                display: descriptor(homeID, x: -1600, width: 1600),
                origin: .userInteractionEnded
            )
        ) { error in
            XCTAssertEqual(
                error as? PlacementStateError,
                .invalidGeometry(.nonFiniteValue("windowFrame.origin"))
            )
        }
        XCTAssertEqual(original.homeDisplay, homeID)
    }

    func testSessionRejectsMissingHomePlacement() throws {
        XCTAssertThrowsError(
            try PlacementSession(
                placements: [:],
                homeDisplay: homeID,
                presentation: .active(on: homeID)
            )
        ) { XCTAssertEqual($0 as? PlacementStateError, .missingHomePlacement(homeID)) }
    }

    func testSessionRejectsPresentationContradictingHome() throws {
        let original = try makeSession()
        XCTAssertThrowsError(
            try PlacementSession(
                placements: original.placements,
                homeDisplay: homeID,
                presentation: .active(on: otherID)
            )
        ) {
            XCTAssertEqual(
                $0 as? PlacementStateError,
                .invalidPresentation(home: homeID, presentation: .active(on: otherID))
            )
        }
        XCTAssertThrowsError(
            try PlacementSession(
                placements: original.placements,
                homeDisplay: homeID,
                presentation: .temporarilyDisplaced(to: homeID)
            )
        )
    }

    private func makeSession(
        frame: CGRect = CGRect(x: -1000, y: 250, width: 400, height: 300)
    ) throws -> PlacementSession {
        let home = descriptor(homeID, x: -1600, width: 1600)
        let record = try PlacementGeometry.capture(
            windowFrame: frame,
            visibleFrame: home.visibleFrame
        )
        return try PlacementSession(
            placements: [homeID: record],
            homeDisplay: homeID,
            presentation: .active(on: homeID)
        )
    }

    private func descriptor(
        _ identity: DisplayIdentity,
        x: CGFloat,
        width: CGFloat,
        height: CGFloat = 800
    ) -> DisplayDescriptor {
        DisplayDescriptor(
            identity: identity,
            visibleFrame: CGRect(x: x, y: 0, width: width, height: height)
        )
    }

    private func assertContained(
        _ frame: CGRect,
        in visibleFrame: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY, file: file, line: line)
    }
}
