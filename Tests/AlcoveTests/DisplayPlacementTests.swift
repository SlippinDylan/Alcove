// DisplayPlacementTests.swift
// Alcove — AppKit display topology boundary tests.

import AppKit
import CoreGraphics
import XCTest

@testable import Alcove
@testable import AlcoveCore

@MainActor
final class DisplayPlacementTests: XCTestCase {
    func testSnapshotKeepsExplicitPrimaryRegardlessOfDisplayOrder() throws {
        let primary = display("primary", x: 0)
        let secondary = display("secondary", x: -1_000)

        let snapshot = try DisplaySnapshot(
            displays: [secondary, primary],
            primaryDisplay: primary.identity
        )

        XCTAssertEqual(snapshot.primaryDisplay, primary.identity)
        XCTAssertEqual(snapshot.primaryDescriptor, primary)
    }

    func testSnapshotRejectsDuplicateIdentities() {
        let primary = display("primary", x: 0)
        XCTAssertThrowsError(
            try DisplaySnapshot(
                displays: [primary, primary],
                primaryDisplay: primary.identity
            )
        ) { error in
            XCTAssertEqual(
                error as? DisplaySnapshotError,
                .duplicateDisplayIdentity(primary.identity)
            )
        }
    }

    func testLegacyFrameUsesLargestVisibleFrameIntersection() throws {
        let primary = display("primary", x: 0, width: 100)
        let secondary = display("secondary", x: 100, width: 200)
        let snapshot = try DisplaySnapshot(
            displays: [secondary, primary],
            primaryDisplay: primary.identity
        )

        let resolved = try LegacyFrameDisplayResolver.resolve(
            frame: CGRect(x: 80, y: 0, width: 140, height: 100),
            in: snapshot
        )

        XCTAssertEqual(resolved.identity, secondary.identity)
    }

    func testLegacyFrameWithoutIntersectionUsesExplicitPrimary() throws {
        let primary = display("primary", x: 0)
        let secondary = display("secondary", x: 1_000)
        let snapshot = try DisplaySnapshot(
            displays: [secondary, primary],
            primaryDisplay: primary.identity
        )

        let resolved = try LegacyFrameDisplayResolver.resolve(
            frame: CGRect(x: 3_000, y: 0, width: 100, height: 100),
            in: snapshot
        )

        XCTAssertEqual(resolved.identity, primary.identity)
    }

    func testEqualLegacyIntersectionPrefersPrimaryWithoutUsingInputOrder() throws {
        let primary = display("z-primary", x: 0, width: 100)
        let secondary = display("a-secondary", x: 100, width: 100)
        let snapshot = try DisplaySnapshot(
            displays: [secondary, primary],
            primaryDisplay: primary.identity
        )

        let resolved = try LegacyFrameDisplayResolver.resolve(
            frame: CGRect(x: 50, y: 0, width: 100, height: 100),
            in: snapshot
        )

        XCTAssertEqual(resolved.identity, primary.identity)
    }

    func testEqualNonPrimaryIntersectionsUseStableIdentityTieBreak() throws {
        let primary = display("primary", x: -1_000, width: 100)
        let first = display("a-display", x: 0, width: 100)
        let second = display("z-display", x: 100, width: 100)
        let snapshot = try DisplaySnapshot(
            displays: [second, primary, first],
            primaryDisplay: primary.identity
        )

        let resolved = try LegacyFrameDisplayResolver.resolve(
            frame: CGRect(x: 50, y: 0, width: 100, height: 100),
            in: snapshot
        )

        XCTAssertEqual(resolved.identity, first.identity)
    }

    func testDisplayIDExtractionRejectsBooleanAndFractionalValues() {
        let key = NSDeviceDescriptionKey("NSScreenNumber")

        XCTAssertThrowsError(
            try DisplayIdentityLookup.displayID(from: [key: NSNumber(value: true)])
        ) { error in
            XCTAssertEqual(error as? DisplaySnapshotError, .nonNumericDisplayID)
        }
        XCTAssertThrowsError(
            try DisplayIdentityLookup.displayID(from: [key: NSNumber(value: 1.5)])
        ) { error in
            XCTAssertEqual(error as? DisplaySnapshotError, .invalidDisplayIDValue)
        }
    }

    func testObserverDeliversFreshMainActorSnapshotsAndStops() async throws {
        let center = NotificationCenter()
        let primary = display("primary", x: 0)
        let first = try DisplaySnapshot(displays: [primary], primaryDisplay: primary.identity)
        let second = try DisplaySnapshot(
            displays: [display("updated", x: 0)],
            primaryDisplay: DisplayIdentity(rawValue: "updated")
        )
        var snapshots = [DisplaySnapshot]()
        var captures = 0
        let observer = DisplayPlacementObserver(
            center: center,
            wakeCenter: center,
            snapshotProvider: {
                captures += 1
                return .success(captures == 1 ? first : second)
            },
            eventHandler: { result in
                MainActor.preconditionIsolated()
                if case .success(let snapshot) = result {
                    snapshots.append(snapshot)
                }
            }
        )

        observer.start()
        observer.start()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await allowNotificationDelivery()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await allowNotificationDelivery()
        observer.stop()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await allowNotificationDelivery()

        XCTAssertEqual(snapshots, [first, second])
        XCTAssertEqual(captures, 2)
        XCTAssertFalse(observer.isObserving)
    }

    func testObserverRefreshesTopologyAfterWake() async throws {
        let center = NotificationCenter()
        let primary = display("primary", x: 0)
        let snapshot = try DisplaySnapshot(
            displays: [primary],
            primaryDisplay: primary.identity
        )
        var deliveries = 0
        let observer = DisplayPlacementObserver(
            center: center,
            wakeCenter: center,
            snapshotProvider: { .success(snapshot) },
            eventHandler: { _ in deliveries += 1 }
        )
        observer.start()

        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await allowNotificationDelivery()
        observer.stop()

        XCTAssertEqual(deliveries, 1)
    }

    func testCurrentScreenCaptureHasAnExplicitPrimaryIdentity() throws {
        guard !NSScreen.screens.isEmpty else {
            throw XCTSkip("No screens are available in this test session")
        }
        let snapshot = try DisplaySnapshot.capture()

        XCTAssertFalse(snapshot.displays.isEmpty)
        XCTAssertNotNil(snapshot.display(with: snapshot.primaryDisplay))
        XCTAssertEqual(Set(snapshot.displays.map(\.identity)).count, snapshot.displays.count)
    }

    private func display(
        _ identity: String,
        x: CGFloat,
        width: CGFloat = 1_000
    ) -> DisplayDescriptor {
        DisplayDescriptor(
            identity: DisplayIdentity(rawValue: identity),
            visibleFrame: CGRect(x: x, y: 0, width: width, height: 800)
        )
    }

    private func allowNotificationDelivery() async throws {
        await Task.yield()
        try await Task.sleep(for: .milliseconds(20))
    }
}
