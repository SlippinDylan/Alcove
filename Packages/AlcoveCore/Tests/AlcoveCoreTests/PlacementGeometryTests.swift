// PlacementGeometryTests.swift
// AlcoveCore — Automated placement geometry tests.
//
// Asserts exact deterministic outputs where feasible.
// Every test must fail on errors; no tests that merely compare
// an accessor with itself.

import CoreGraphics
import Foundation
import XCTest

@testable import AlcoveCore

final class PlacementGeometryTests: XCTestCase {

    // MARK: - Test Helpers

    /// Capture, verify round-trip properties, then restore with the given parameters.
    private func captureAndRestore(
        windowFrame: CGRect,
        visibleFrame: CGRect,
        currentVisibleFrame: CGRect? = nil,
        gridSpacing: GridSpacing = .noSnap
    ) throws -> CGRect {
        let record = try PlacementGeometry.capture(
            windowFrame: windowFrame,
            visibleFrame: visibleFrame
        )
        return try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: currentVisibleFrame ?? visibleFrame,
            gridSpacing: gridSpacing
        )
    }

    private func assertAlmostEqual(
        _ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.01,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            abs(a - b) <= tolerance,
            "Expected \(a) ≈ \(b) (±\(tolerance))",
            file: file, line: line
        )
    }

    private func assertRectAlmostEqual(
        _ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.01,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertAlmostEqual(a.minX, b.minX, tolerance: tolerance, file: file, line: line)
        assertAlmostEqual(a.minY, b.minY, tolerance: tolerance, file: file, line: line)
        assertAlmostEqual(a.width, b.width, tolerance: tolerance, file: file, line: line)
        assertAlmostEqual(a.height, b.height, tolerance: tolerance, file: file, line: line)
    }

    // MARK: - Anchor Tests: Center and Four Corners

    func testCenterAnchor() throws {
        // Window centered in a 1000×800 visible frame.
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // movableWidth = 1000 - 500 = 500, movableHeight = 800 - 400 = 400
        // nx = 250 / 500 = 0.5, ny = 200 / 400 = 0.5
        assertAlmostEqual(record.normalizedAnchor.x, 0.5)
        assertAlmostEqual(record.normalizedAnchor.y, 0.5)

        // Same-geometry restore → uses absolute origin
        let restored = try PlacementGeometry.restore(record: record, currentVisibleFrame: vf)
        assertRectAlmostEqual(restored, wf)
    }

    func testTopLeftAnchor() throws {
        // Window at top-left of visible frame.
        // (In CG coordinates, y=0 is bottom, so top-left = maxY - height.)
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 0, y: 400, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // movableWidth = 500, movableHeight = 400
        // nx = 0 / 500 = 0, ny = 400 / 400 = 1
        assertAlmostEqual(record.normalizedAnchor.x, 0)
        assertAlmostEqual(record.normalizedAnchor.y, 1)
    }

    func testTopRightAnchor() throws {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 500, y: 400, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // nx = 500 / 500 = 1, ny = 400 / 400 = 1
        assertAlmostEqual(record.normalizedAnchor.x, 1)
        assertAlmostEqual(record.normalizedAnchor.y, 1)
    }

    func testBottomLeftAnchor() throws {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 0, y: 0, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // nx = 0 / 500 = 0, ny = 0 / 400 = 0
        assertAlmostEqual(record.normalizedAnchor.x, 0)
        assertAlmostEqual(record.normalizedAnchor.y, 0)
    }

    func testBottomRightAnchor() throws {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 500, y: 0, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // nx = 500 / 500 = 1, ny = 0 / 400 = 0
        assertAlmostEqual(record.normalizedAnchor.x, 1)
        assertAlmostEqual(record.normalizedAnchor.y, 0)
    }

    // MARK: - Zero Movable Range

    func testZeroMovableRangeXAxis() throws {
        // Window width equals visible frame width → movable width = 0.
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 0, y: 200, width: 1000, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // nx must be 0 (not NaN) when movable range is zero.
        assertAlmostEqual(record.normalizedAnchor.x, 0)
        assertAlmostEqual(record.normalizedAnchor.y, 0.5)
    }

    func testZeroMovableRangeYAxis() throws {
        // Window height equals visible frame height → movable height = 0.
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 0, width: 500, height: 800)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        assertAlmostEqual(record.normalizedAnchor.x, 0.5)
        assertAlmostEqual(record.normalizedAnchor.y, 0)
    }

    func testZeroMovableRangeBothAxes() throws {
        // Window fills the entire visible frame.
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        assertAlmostEqual(record.normalizedAnchor.x, 0)
        assertAlmostEqual(record.normalizedAnchor.y, 0)

        // Restore should return the same frame.
        let restored = try PlacementGeometry.restore(record: record, currentVisibleFrame: vf)
        assertRectAlmostEqual(restored, wf)
    }

    // MARK: - Anchor Clamping

    func testAnchorClampedFromBelowZero() throws {
        // Window origin is outside the visible frame to the left/bottom.
        let vf = CGRect(x: 100, y: 100, width: 800, height: 600)
        let wf = CGRect(x: 50, y: 50, width: 400, height: 300)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // movableWidth = 800 - 400 = 400
        // nx = (50 - 100) / 400 = -0.125 → clamped to 0
        // movableHeight = 600 - 300 = 300
        // ny = (50 - 100) / 300 = -0.1667 → clamped to 0
        assertAlmostEqual(record.normalizedAnchor.x, 0)
        assertAlmostEqual(record.normalizedAnchor.y, 0)
    }

    func testAnchorClampedFromAboveOne() throws {
        // Window origin is beyond the movable range.
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 600, y: 500, width: 400, height: 300)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // movableWidth = 1000 - 400 = 600
        // nx = 600 / 600 = 1.0 → stays at 1
        // movableHeight = 800 - 300 = 500
        // ny = 500 / 500 = 1.0 → stays at 1
        assertAlmostEqual(record.normalizedAnchor.x, 1)
        assertAlmostEqual(record.normalizedAnchor.y, 1)
    }

    func testAnchorClampedAboveOneWhenWindowExceedsMovableRange() throws {
        // Window origin + window size > visible frame → origin is beyond max.
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 800, y: 600, width: 400, height: 300)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // movableWidth = 1000 - 400 = 600
        // nx = 800 / 600 = 1.333 → clamped to 1
        // movableHeight = 800 - 300 = 500
        // ny = 600 / 500 = 1.2 → clamped to 1
        assertAlmostEqual(record.normalizedAnchor.x, 1)
        assertAlmostEqual(record.normalizedAnchor.y, 1)
    }

    // MARK: - Negative Visible-Frame Origins

    func testNegativeVisibleFrameOrigin() throws {
        // Display with negative origin (e.g., secondary display to the left).
        let vf = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let wf = CGRect(x: -1420, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // movableWidth = 1920 - 500 = 1420
        // nx = (-1420 - (-1920)) / 1420 = 500 / 1420 ≈ 0.3521
        assertAlmostEqual(record.normalizedAnchor.x, 500.0 / 1420.0, tolerance: 0.001)
        // movableHeight = 1080 - 400 = 680
        // ny = 200 / 680 ≈ 0.2941
        assertAlmostEqual(record.normalizedAnchor.y, 200.0 / 680.0, tolerance: 0.001)

        // Same-geometry restore → absolute frame.
        let restored = try PlacementGeometry.restore(record: record, currentVisibleFrame: vf)
        assertRectAlmostEqual(restored, wf)
    }

    func testNegativeVisibleFrameOriginBothAxes() throws {
        let vf = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let wf = CGRect(x: -1420, y: -580, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        // nx = (-1420 - (-1920)) / (1920 - 500) = 500 / 1420
        // ny = (-580 - (-1080)) / (1080 - 400) = 500 / 680
        assertAlmostEqual(record.normalizedAnchor.x, 500.0 / 1420.0, tolerance: 0.001)
        assertAlmostEqual(record.normalizedAnchor.y, 500.0 / 680.0, tolerance: 0.001)
    }

    // MARK: - Same Geometry Prefers Absolute Origin

    func testSameGeometryPrefersAbsoluteOrigin() throws {
        let vf = CGRect(x: 100, y: 50, width: 1200, height: 900)
        let wf = CGRect(x: 300, y: 200, width: 600, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        let restored = try PlacementGeometry.restore(record: record, currentVisibleFrame: vf)
        assertRectAlmostEqual(restored, wf)
    }

    func testSameGeometryWithGridSnapStillPreferAbsoluteOrigin() throws {
        // When geometry is unchanged, the absolute origin is used first,
        // then grid-snapped and clamped.
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Place window at an origin that's already on a 50-pt grid.
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: vf,
            gridSpacing: .snap(50)
        )
        // Origin (250, 200) is already on a 50-pt grid.
        assertRectAlmostEqual(restored, wf)
    }

    // MARK: - Changed Geometry Restores Normalized Anchor

    func testChangedGeometryRestoresNormalizedOrigin() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // New visible frame: wider but same height.
        let newVF = CGRect(x: 0, y: 0, width: 1400, height: 800)
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: newVF,
            gridSpacing: .noSnap
        )

        // movableWidth = 1400 - 500 = 900
        // x = 0 + 0.5 * 900 = 450
        // movableHeight = 800 - 400 = 400
        // y = 0 + 0.5 * 400 = 200
        assertAlmostEqual(restored.minX, 450)
        assertAlmostEqual(restored.minY, 200)
        assertAlmostEqual(restored.width, 500)
        assertAlmostEqual(restored.height, 400)
    }

    func testChangedGeometrySmallerVisibleFrame() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let wf = CGRect(x: 960, y: 540, width: 480, height: 360)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // Smaller visible frame: movable range shrinks.
        let newVF = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: newVF
        )

        // nx = 960 / (1920 - 480) = 960 / 1440 = 0.6667
        // ny = 540 / (1080 - 360) = 540 / 720 = 0.75
        // constrainedWidth = min(480, 1200) = 480
        // constrainedHeight = min(360, 800) = 360
        // movableWidth = 1200 - 480 = 720
        // x = 0.6667 * 720 = 480
        // movableHeight = 800 - 360 = 440
        // y = 0.75 * 440 = 330
        assertAlmostEqual(restored.minX, 480, tolerance: 0.5)
        assertAlmostEqual(restored.minY, 330, tolerance: 0.5)
    }

    // MARK: - Preferred Size Constrained Before Movable Range

    func testPreferredSizeConstrainedBeforeMovableRange() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let wf = CGRect(x: 200, y: 100, width: 800, height: 600)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // New visible frame is smaller than the saved preferred size.
        let newVF = CGRect(x: 0, y: 0, width: 600, height: 500)
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: newVF
        )

        // constrainedWidth = min(800, 600) = 600
        // constrainedHeight = min(600, 500) = 500
        // movableWidth = 600 - 600 = 0 → x = 0
        // movableHeight = 500 - 500 = 0 → y = 0
        XCTAssertEqual(restored.width, 600)
        XCTAssertEqual(restored.height, 500)
        XCTAssertEqual(restored.minX, 0)
        XCTAssertEqual(restored.minY, 0)
    }

    func testPreferredSizeConstraintOnlyOneAxis() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let wf = CGRect(x: 400, y: 200, width: 800, height: 600)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // Width constrained, height not.
        let newVF = CGRect(x: 0, y: 0, width: 600, height: 1080)
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: newVF
        )

        // constrainedWidth = min(800, 600) = 600
        // constrainedHeight = min(600, 1080) = 600
        // movableWidth = 600 - 600 = 0 → x clamped to 0
        // movableHeight = 1080 - 600 = 480
        // ny = 200 / (1080 - 600) = 200 / 480 = 0.4167
        // y = 0 + 0.4167 * 480 = 200
        XCTAssertEqual(restored.width, 600)
        XCTAssertEqual(restored.height, 600)
        XCTAssertEqual(restored.minX, 0)
        assertAlmostEqual(restored.minY, 200)
    }

    // MARK: - Grid Snap Before Final Clamp

    func testGridSnapBeforeFinalClamp() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // New visible frame with same size → uses absolute origin.
        // Grid spacing 100: snap (250, 200) → (300, 200).
        // Clamp: maxX = 1000 - 500 = 500, maxY = 800 - 400 = 400.
        // 300 ≤ 500 ✓, 200 ≤ 400 ✓.
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: saveVF,
            gridSpacing: .snap(100)
        )
        assertAlmostEqual(restored.minX, 300)
        assertAlmostEqual(restored.minY, 200)
        assertAlmostEqual(restored.width, 500)
        assertAlmostEqual(restored.height, 400)
    }

    func testGridSnapOvershootThenClamp() throws {
        // Edge case where grid snap overshoots the visible frame boundary.
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // Change geometry: smaller visible frame.
        let newVF = CGRect(x: 0, y: 0, width: 800, height: 600)
        // Same anchor (0.5, 0.5) with new movable range:
        // movableWidth = 800 - 500 = 300 → x = 150
        // movableHeight = 600 - 400 = 200 → y = 100
        // Grid snap 200: snap (150, 100) → (200, 200).
        // Clamp: maxX = 800 - 500 = 300, maxY = 600 - 400 = 200.
        // 200 ≤ 300 ✓, 200 ≤ 200 ✓.
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: newVF,
            gridSpacing: .snap(200)
        )
        assertAlmostEqual(restored.minX, 200)
        assertAlmostEqual(restored.minY, 200)
        assertAlmostEqual(restored.width, 500)
        assertAlmostEqual(restored.height, 400)
    }

    func testGridSnapOvershootClampsToBoundary() throws {
        // Snap would push the frame outside the visible area → clamp.
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Window near the right edge.
        let wf = CGRect(x: 480, y: 380, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // Same geometry, grid snap 100.
        // Absolute origin (480, 380) → snap to (500, 400).
        // maxX = 1000 - 500 = 500 → 500 ≤ 500 ✓ (exactly at boundary).
        // maxY = 800 - 400 = 400 → 400 ≤ 400 ✓.
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: saveVF,
            gridSpacing: .snap(100)
        )
        assertAlmostEqual(restored.minX, 500)
        assertAlmostEqual(restored.minY, 400)
    }

    func testGridSnapLargeSpacingOvershootsAndClamps() throws {
        // Grid snap with very large spacing overshoots significantly.
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 100, y: 100, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // Grid snap 500: snap (100, 100) → (0, 0) [rounded to nearest 500].
        // Wait: 100/500 = 0.2 → rounded = 0 → snapped = 0.
        // maxX = 500, maxY = 400 → 0 ≤ 500 ✓, 0 ≤ 400 ✓.
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: saveVF,
            gridSpacing: .snap(500)
        )
        assertAlmostEqual(restored.minX, 0)
        assertAlmostEqual(restored.minY, 0)

        // Another case: origin at 350, snap to 500, but max is 500.
        let wf2 = CGRect(x: 350, y: 350, width: 500, height: 400)
        let record2 = try PlacementGeometry.capture(windowFrame: wf2, visibleFrame: saveVF)
        let restored2 = try PlacementGeometry.restore(
            record: record2,
            currentVisibleFrame: saveVF,
            gridSpacing: .snap(500)
        )
        // 350 / 500 = 0.7 → rounded = 1 → snapped = 500.
        // maxX = 500, maxY = 400 → 500 ≤ 500 ✓, 500 > 400 → clamp to 400.
        assertAlmostEqual(restored2.minX, 500)
        assertAlmostEqual(restored2.minY, 400)
    }

    // MARK: - No-Snap Restore

    func testNoSnapRestore() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 333, y: 277, width: 444, height: 333)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // No snap → exact origin preserved.
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: saveVF,
            gridSpacing: .noSnap
        )
        assertRectAlmostEqual(restored, wf)
    }

    func testNoSnapChangedGeometry() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        let newVF = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: newVF,
            gridSpacing: .noSnap
        )

        // movableWidth = 1200 - 500 = 700, nx = 0.5 → x = 350
        // movableHeight = 900 - 400 = 500, ny = 0.5 → y = 250
        assertAlmostEqual(restored.minX, 350)
        assertAlmostEqual(restored.minY, 250)
    }

    // MARK: - Invalid Input Errors

    func testNormalizedAnchorClampsFiniteValues() throws {
        let anchor = try NormalizedAnchor(x: -0.25, y: 1.25)
        XCTAssertEqual(anchor, try NormalizedAnchor(x: 0, y: 1))
    }

    func testNormalizedAnchorRejectsNonFiniteValues() {
        XCTAssertThrowsError(try NormalizedAnchor(x: .nan, y: 0.5)) { error in
            guard case PlacementError.nonFiniteValue = error else {
                XCTFail("Expected nonFiniteValue, got \(error)")
                return
            }
        }
        XCTAssertThrowsError(try NormalizedAnchor(x: 0.5, y: .infinity)) { error in
            guard case PlacementError.nonFiniteValue = error else {
                XCTFail("Expected nonFiniteValue, got \(error)")
                return
            }
        }
    }

    func testRejectsNaNWindowOrigin() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: CGFloat.nan, y: 0, width: 500, height: 400)
        XCTAssertThrowsError(try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)) { error in
            guard case PlacementError.nonFiniteValue = error else {
                XCTFail("Expected nonFiniteValue, got \(error)")
                return
            }
        }
    }

    func testRejectsInfiniteWindowOrigin() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: CGFloat.infinity, y: 0, width: 500, height: 400)
        XCTAssertThrowsError(try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)) { error in
            guard case PlacementError.nonFiniteValue = error else {
                XCTFail("Expected nonFiniteValue, got \(error)")
                return
            }
        }
    }

    func testRejectsNaNVisibleFrameSize() {
        let vf = CGRect(x: 0, y: 0, width: CGFloat.nan, height: 800)
        let wf = CGRect(x: 0, y: 0, width: 500, height: 400)
        XCTAssertThrowsError(try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)) { error in
            guard case PlacementError.nonFiniteValue = error else {
                XCTFail("Expected nonFiniteValue, got \(error)")
                return
            }
        }
    }

    func testRejectsInfiniteVisibleFrameSize() {
        let vf = CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 800)
        let wf = CGRect(x: 0, y: 0, width: 500, height: 400)
        XCTAssertThrowsError(try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)) { error in
            guard case PlacementError.nonFiniteValue = error else {
                XCTFail("Expected nonFiniteValue, got \(error)")
                return
            }
        }
    }

    func testRejectsNonPositiveVisibleWidth() {
        let vf = CGRect(x: 0, y: 0, width: 0, height: 800)
        let wf = CGRect(x: 0, y: 0, width: 500, height: 400)
        XCTAssertThrowsError(try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)) { error in
            guard case PlacementError.nonPositiveVisibleSize = error else {
                XCTFail("Expected nonPositiveVisibleSize, got \(error)")
                return
            }
        }
    }

    func testRejectsNonPositiveVisibleHeight() {
        // CGRect normalizes negative dimensions (height -1 → origin shifts, height 1).
        // Test with zero height which is not normalized.
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 0)
        let wf = CGRect(x: 0, y: 0, width: 500, height: 400)
        XCTAssertThrowsError(try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)) { error in
            guard case PlacementError.nonPositiveVisibleSize = error else {
                XCTFail("Expected nonPositiveVisibleSize, got \(error)")
                return
            }
        }
    }

    func testRejectsNegativePreferredWidth() {
        // DisplayPlacementEntry.preferredSize is CGSize (does not normalize).
        // A negative preferred size must be rejected during restore.
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let record = DisplayPlacementEntry(
            absoluteFrame: CGRect(x: 0, y: 0, width: 0, height: 0),
            referenceVisibleFrame: saveVF,
            preferredSize: CGSize(width: -1, height: 400),
            normalizedAnchor: .center
        )
        XCTAssertThrowsError(
            try PlacementGeometry.restore(record: record, currentVisibleFrame: saveVF)
        ) { error in
            guard case PlacementError.negativeDimension = error else {
                XCTFail("Expected negativeDimension, got \(error)")
                return
            }
        }
    }

    func testRejectsNegativePreferredHeight() {
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let record = DisplayPlacementEntry(
            absoluteFrame: CGRect(x: 0, y: 0, width: 0, height: 0),
            referenceVisibleFrame: saveVF,
            preferredSize: CGSize(width: 500, height: -1),
            normalizedAnchor: .center
        )
        XCTAssertThrowsError(
            try PlacementGeometry.restore(record: record, currentVisibleFrame: saveVF)
        ) { error in
            guard case PlacementError.negativeDimension = error else {
                XCTFail("Expected negativeDimension, got \(error)")
                return
            }
        }
    }

    func testCGRectNormalizationProducesNonNegativeDimensions() {
        // Document that CGRect normalizes negative dimensions.
        // After normalization, width/height are always non-negative.
        let negativeWidth = CGRect(x: 0, y: 0, width: -100, height: 50)
        XCTAssertTrue(negativeWidth.width >= 0, "CGRect normalizes negative width")
        XCTAssertTrue(negativeWidth.height >= 0, "CGRect normalizes negative height")

        let negativeHeight = CGRect(x: 0, y: 0, width: 100, height: -50)
        XCTAssertTrue(negativeHeight.width >= 0, "CGRect normalizes negative width")
        XCTAssertTrue(negativeHeight.height >= 0, "CGRect normalizes negative height")
    }

    func testRejectsNonFinitePreferredSize() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for size in [
            CGSize(width: CGFloat.nan, height: 400),
            CGSize(width: 500, height: CGFloat.infinity),
        ] {
            let record = DisplayPlacementEntry(
                absoluteFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
                referenceVisibleFrame: visibleFrame,
                preferredSize: size,
                normalizedAnchor: .center
            )
            XCTAssertThrowsError(
                try PlacementGeometry.restore(
                    record: record,
                    currentVisibleFrame: visibleFrame
                )
            ) { error in
                guard case PlacementError.nonFiniteValue = error else {
                    XCTFail("Expected nonFiniteValue, got \(error)")
                    return
                }
            }
        }
    }

    func testRejectsNonFiniteSavedAbsoluteFrame() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let record = DisplayPlacementEntry(
            absoluteFrame: CGRect(
                x: CGFloat.nan, y: 0, width: 500, height: 400
            ),
            referenceVisibleFrame: visibleFrame,
            preferredSize: CGSize(width: 500, height: 400),
            normalizedAnchor: .center
        )
        XCTAssertThrowsError(
            try PlacementGeometry.restore(
                record: record,
                currentVisibleFrame: visibleFrame
            )
        ) { error in
            guard case PlacementError.nonFiniteValue = error else {
                XCTFail("Expected nonFiniteValue, got \(error)")
                return
            }
        }
    }

    func testRejectsNonFiniteReferenceVisibleFrame() {
        let currentFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let record = DisplayPlacementEntry(
            absoluteFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            referenceVisibleFrame: CGRect(
                x: 0, y: 0, width: CGFloat.infinity, height: 800
            ),
            preferredSize: CGSize(width: 500, height: 400),
            normalizedAnchor: .center
        )
        XCTAssertThrowsError(
            try PlacementGeometry.restore(
                record: record,
                currentVisibleFrame: currentFrame
            )
        ) { error in
            guard case PlacementError.nonFiniteValue = error else {
                XCTFail("Expected nonFiniteValue, got \(error)")
                return
            }
        }
    }

    func testRejectsNonPositiveReferenceVisibleFrame() {
        let currentFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let record = DisplayPlacementEntry(
            absoluteFrame: CGRect(x: 0, y: 0, width: 500, height: 400),
            referenceVisibleFrame: CGRect(x: 0, y: 0, width: 0, height: 800),
            preferredSize: CGSize(width: 500, height: 400),
            normalizedAnchor: .center
        )
        XCTAssertThrowsError(
            try PlacementGeometry.restore(
                record: record,
                currentVisibleFrame: currentFrame
            )
        ) { error in
            guard case PlacementError.nonPositiveVisibleSize = error else {
                XCTFail("Expected nonPositiveVisibleSize, got \(error)")
                return
            }
        }
    }

    func testRejectsNonFiniteGridSpacing() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        XCTAssertThrowsError(
            try PlacementGeometry.restore(
                record: record,
                currentVisibleFrame: saveVF,
                gridSpacing: .snap(CGFloat.nan)
            )
        ) { error in
            guard case PlacementError.invalidGridSpacing = error else {
                XCTFail("Expected invalidGridSpacing, got \(error)")
                return
            }
        }
    }

    func testRejectsNonPositiveGridSpacing() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        XCTAssertThrowsError(
            try PlacementGeometry.restore(
                record: record,
                currentVisibleFrame: saveVF,
                gridSpacing: .snap(0)
            )
        ) { error in
            guard case PlacementError.invalidGridSpacing = error else {
                XCTFail("Expected invalidGridSpacing, got \(error)")
                return
            }
        }

        XCTAssertThrowsError(
            try PlacementGeometry.restore(
                record: record,
                currentVisibleFrame: saveVF,
                gridSpacing: .snap(-10)
            )
        ) { error in
            guard case PlacementError.invalidGridSpacing = error else {
                XCTFail("Expected invalidGridSpacing, got \(error)")
                return
            }
        }
    }

    func testHalfGridRoundsToNearestAwayFromZero() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let windowFrame = CGRect(x: 50, y: 50, width: 400, height: 300)
        let record = try PlacementGeometry.capture(
            windowFrame: windowFrame,
            visibleFrame: visibleFrame
        )
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: visibleFrame,
            gridSpacing: .snap(100)
        )
        XCTAssertEqual(restored.origin, CGPoint(x: 100, y: 100))
    }

    // MARK: - Final-Frame Containment Invariants

    /// Verify that the restored frame is wholly inside the current visible frame
    /// across a table of representative geometries.
    func testFinalFrameContainmentAcrossRepresentativeGeometries() throws {
        let geometries: [(name: String, saveVF: CGRect, wf: CGRect, newVF: CGRect)] = (
            [
                // Standard display
                ("standard", CGRect(x: 0, y: 0, width: 1920, height: 1080),
                 CGRect(x: 400, y: 200, width: 800, height: 600),
                 CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                // Wider new display
                ("wider", CGRect(x: 0, y: 0, width: 1920, height: 1080),
                 CGRect(x: 400, y: 200, width: 800, height: 600),
                 CGRect(x: 0, y: 0, width: 2560, height: 1440)),
                // Narrower new display
                ("narrower", CGRect(x: 0, y: 0, width: 1920, height: 1080),
                 CGRect(x: 400, y: 200, width: 800, height: 600),
                 CGRect(x: 0, y: 0, width: 1280, height: 720)),
                // Window larger than new visible frame
                ("window-larger", CGRect(x: 0, y: 0, width: 1920, height: 1080),
                 CGRect(x: 100, y: 100, width: 1600, height: 900),
                 CGRect(x: 0, y: 0, width: 1280, height: 720)),
                // Negative display origin
                ("negative-origin", CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                 CGRect(x: -1420, y: 200, width: 500, height: 400),
                 CGRect(x: -1920, y: 0, width: 1920, height: 1080)),
                // Window fills entire visible frame
                ("fullscreen", CGRect(x: 0, y: 0, width: 1000, height: 800),
                 CGRect(x: 0, y: 0, width: 1000, height: 800),
                 CGRect(x: 0, y: 0, width: 1000, height: 800)),
                // Very small window in large visible frame
                ("tiny-window", CGRect(x: 0, y: 0, width: 3840, height: 2160),
                 CGRect(x: 1000, y: 500, width: 200, height: 150),
                 CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            ]
        )

        for (name, saveVF, wf, newVF) in geometries {
            let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

            for snapDesc in ["noSnap", "snap(100)"] {
                let gridSpacing: GridSpacing = snapDesc == "noSnap" ? .noSnap : .snap(100)
                let restored = try PlacementGeometry.restore(
                    record: record,
                    currentVisibleFrame: newVF,
                    gridSpacing: gridSpacing
                )

                // Containment: frame must be wholly inside visible frame.
                XCTAssertTrue(
                    restored.minX >= newVF.minX,
                    "\(name)/\(snapDesc): minX \(restored.minX) < visible minX \(newVF.minX)"
                )
                XCTAssertTrue(
                    restored.minY >= newVF.minY,
                    "\(name)/\(snapDesc): minY \(restored.minY) < visible minY \(newVF.minY)"
                )
                XCTAssertTrue(
                    restored.maxX <= newVF.maxX + 0.01,
                    "\(name)/\(snapDesc): maxX \(restored.maxX) > visible maxX \(newVF.maxX)"
                )
                XCTAssertTrue(
                    restored.maxY <= newVF.maxY + 0.01,
                    "\(name)/\(snapDesc): maxY \(restored.maxY) > visible maxY \(newVF.maxY)"
                )
                // Size must not exceed visible frame.
                XCTAssertTrue(
                    restored.width <= newVF.width,
                    "\(name)/\(snapDesc): width \(restored.width) > visible width \(newVF.width)"
                )
                XCTAssertTrue(
                    restored.height <= newVF.height,
                    "\(name)/\(snapDesc): height \(restored.height) > visible height \(newVF.height)"
                )
            }
        }
    }

    // MARK: - Capture Record Properties

    func testCapturePreservesAbsoluteFrameAndVisibleFrame() throws {
        let vf = CGRect(x: 100, y: 50, width: 1200, height: 900)
        let wf = CGRect(x: 300, y: 200, width: 600, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        XCTAssertEqual(record.absoluteFrame, wf)
        XCTAssertEqual(record.referenceVisibleFrame, vf)
        XCTAssertEqual(record.preferredSize, wf.size)
    }

    // MARK: - Deterministic Behavior

    func testCaptureIsDeterministic() throws {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)

        let r1 = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)
        let r2 = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        XCTAssertEqual(r1, r2, "Capture must be deterministic")
    }

    func testRestoreIsDeterministic() throws {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 250, y: 200, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        let f1 = try PlacementGeometry.restore(record: record, currentVisibleFrame: vf)
        let f2 = try PlacementGeometry.restore(record: record, currentVisibleFrame: vf)

        XCTAssertEqual(f1, f2, "Restore must be deterministic")
    }

    // MARK: - Edge Case: Window Larger Than Visible Frame

    func testWindowLargerThanVisibleFrameClampsSize() throws {
        let saveVF = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let wf = CGRect(x: 100, y: 100, width: 1600, height: 900)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // New visible frame is smaller than preferred size.
        let newVF = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: newVF
        )

        // constrainedWidth = min(1600, 1280) = 1280
        // constrainedHeight = min(900, 720) = 720
        // movableWidth = 1280 - 1280 = 0 → x = 0
        // movableHeight = 720 - 720 = 0 → y = 0
        XCTAssertEqual(restored.width, 1280)
        XCTAssertEqual(restored.height, 720)
        XCTAssertEqual(restored.minX, 0)
        XCTAssertEqual(restored.minY, 0)
    }

    // MARK: - Edge Case: Anchor at Boundary

    func testAnchorAtExactBoundary() throws {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Window exactly at the maximum movable position.
        let wf = CGRect(x: 500, y: 400, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        assertAlmostEqual(record.normalizedAnchor.x, 1.0)
        assertAlmostEqual(record.normalizedAnchor.y, 1.0)

        // Restore with same geometry → uses absolute origin.
        let restored = try PlacementGeometry.restore(record: record, currentVisibleFrame: vf)
        assertRectAlmostEqual(restored, wf)
    }

    // MARK: - Grid Snap with Non-Zero Visible Frame Origin

    func testGridSnapWithNonZeroVisibleFrameOrigin() throws {
        let saveVF = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let wf = CGRect(x: 350, y: 250, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: saveVF)

        // Grid snap 100 relative to visible frame origin (100, 50).
        // Absolute origin (350, 250).
        // Relative: (250, 200) → snap to (300, 200) → absolute (400, 250).
        let restored = try PlacementGeometry.restore(
            record: record,
            currentVisibleFrame: saveVF,
            gridSpacing: .snap(100)
        )
        assertAlmostEqual(restored.minX, 400)
        assertAlmostEqual(restored.minY, 250)
    }

    // MARK: - Window at Origin Zero

    func testWindowAtOriginZero() throws {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let wf = CGRect(x: 0, y: 0, width: 500, height: 400)
        let record = try PlacementGeometry.capture(windowFrame: wf, visibleFrame: vf)

        assertAlmostEqual(record.normalizedAnchor.x, 0)
        assertAlmostEqual(record.normalizedAnchor.y, 0)

        let restored = try PlacementGeometry.restore(record: record, currentVisibleFrame: vf)
        assertRectAlmostEqual(restored, wf)
    }
}
