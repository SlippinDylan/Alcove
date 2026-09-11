// PlacementGeometry.swift
// AlcoveCore — Pure display placement geometry model.
//
// UI-free: imports CoreGraphics and Foundation only.
// No AppKit, no real screen enumeration, no display UUID lookup.
// AppKit screen discovery and persistence mapping remain outside AlcoveCore.

import CoreGraphics
import Foundation

// MARK: - NormalizedAnchor

/// Portal origin expressed as fractions of the actual movable range
/// inside `visibleFrame`, after constraining the portal size.
///
/// x: 0.0 = leftmost origin, 1.0 = rightmost origin.
/// y: 0.0 = bottommost origin, 1.0 = topmost origin.
/// Components are always clamped to `0...1` at construction time.
public struct NormalizedAnchor: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) throws {
        guard x.isFinite && y.isFinite else {
            throw PlacementError.nonFiniteValue("normalizedAnchor")
        }
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    /// An anchor at the center of the movable range.
    public static let center = NormalizedAnchor(validatedX: 0.5, y: 0.5)

    private init(validatedX x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

// MARK: - DisplayPlacementEntry

/// Immutable record of a portal's saved placement on one display.
///
/// Stores both the absolute frame (for same-geometry restore) and the
/// normalized anchor (for changed-geometry restore).
public struct DisplayPlacementEntry: Sendable, Equatable {
    /// Absolute frame in points, as saved by the user.
    public let absoluteFrame: CGRect
    /// `NSScreen.visibleFrame` at save time.
    public let referenceVisibleFrame: CGRect
    /// Preferred portal size in points.
    public let preferredSize: CGSize
    /// Origin normalized within the movable range at save time.
    public let normalizedAnchor: NormalizedAnchor

    public init(
        absoluteFrame: CGRect,
        referenceVisibleFrame: CGRect,
        preferredSize: CGSize,
        normalizedAnchor: NormalizedAnchor
    ) {
        self.absoluteFrame = absoluteFrame
        self.referenceVisibleFrame = referenceVisibleFrame
        self.preferredSize = preferredSize
        self.normalizedAnchor = normalizedAnchor
    }
}

// MARK: - GridSpacing

/// Controls grid-snap behavior during placement restore.
public enum GridSpacing: Sendable, Equatable {
    /// Do not snap; place at the computed origin directly.
    case noSnap
    /// Snap to a grid with the given positive spacing (in points).
    case snap(CGFloat)
}

// MARK: - PlacementError

/// Explicit geometry/input error type for placement operations.
public enum PlacementError: Error, Sendable, Equatable {
    /// A coordinate or size component is NaN or infinite.
    case nonFiniteValue(String)
    /// `visibleFrame` has non-positive width or height.
    case nonPositiveVisibleSize(CGSize)
    /// Window frame or preferred size has negative width or height.
    case negativeDimension(String)
    /// Grid spacing is non-finite or non-positive when snapping is requested.
    case invalidGridSpacing(CGFloat)
}

// MARK: - PlacementGeometry

/// Pure capture and restore operations for display placement geometry.
///
/// All functions are synchronous, deterministic, and UI-free.
public enum PlacementGeometry {

    // MARK: Capture

    /// Compute a placement record from a window's current frame and the
    /// visible frame of its display.
    ///
    /// Operation order:
    /// 1. Validate inputs (no NaN/infinity, positive visible dimensions,
    ///    non-negative window dimensions).
    /// 2. Compute movable range: `max(0, visible - window)`.
    /// 3. Normalize origin relative to `visibleFrame.minX/minY` and
    ///    the movable range.
    /// 4. Use anchor component `0` when movable range is zero.
    /// 5. Clamp stored anchor components to `0...1`.
    ///
    /// Note: `CGRect` normalizes negative dimensions (e.g., width -1 becomes
    /// width 1 with origin shifted). This function validates the post-normalization
    /// values. Callers that need to validate raw negative sizes should check
    /// `CGSize` values before constructing `CGRect`.
    public static func capture(
        windowFrame: CGRect,
        visibleFrame: CGRect
    ) throws -> DisplayPlacementEntry {
        // --- Validate inputs ---
        try validateFiniteRect(windowFrame, label: "windowFrame")
        try validateFiniteRect(visibleFrame, label: "visibleFrame")

        guard visibleFrame.width > 0 && visibleFrame.height > 0 else {
            throw PlacementError.nonPositiveVisibleSize(visibleFrame.size)
        }
        // CGRect normalizes negative dimensions, so width/height are non-negative
        // after construction. Validate non-negative as a safety check.
        guard windowFrame.width >= 0 && windowFrame.height >= 0 else {
            throw PlacementError.negativeDimension(
                "windowFrame size (\(windowFrame.width), \(windowFrame.height))"
            )
        }

        // --- Compute movable range ---
        let movableWidth = max(0, visibleFrame.width - windowFrame.width)
        let movableHeight = max(0, visibleFrame.height - windowFrame.height)

        // --- Normalize origin ---
        let nx: Double = movableWidth > 0
            ? Double(windowFrame.minX - visibleFrame.minX) / Double(movableWidth)
            : 0
        let ny: Double = movableHeight > 0
            ? Double(windowFrame.minY - visibleFrame.minY) / Double(movableHeight)
            : 0

        let anchor = try NormalizedAnchor(x: nx, y: ny)

        return DisplayPlacementEntry(
            absoluteFrame: windowFrame,
            referenceVisibleFrame: visibleFrame,
            preferredSize: windowFrame.size,
            normalizedAnchor: anchor
        )
    }

    // MARK: Restore

    /// Restore a portal frame from a saved placement record and the
    /// current display's visible frame.
    ///
    /// - Parameters:
    ///   - record: The saved placement record.
    ///   - currentVisibleFrame: The current visible frame of the target display.
    ///   - gridSpacing: Grid-snap configuration.
    /// - Returns: The restored `CGRect` wholly inside `currentVisibleFrame`.
    ///
    /// Operation order:
    /// 1. Constrain preferred size to the current visible frame.
    /// 2. If geometry is unchanged, prefer the saved absolute origin.
    /// 3. If geometry changed, restore origin from the normalized anchor.
    /// 4. Grid-snap the restored origin when snapping is enabled.
    /// 5. Clamp only after grid snap so the final frame is inside
    ///    `currentVisibleFrame`.
    public static func restore(
        record: DisplayPlacementEntry,
        currentVisibleFrame: CGRect,
        gridSpacing: GridSpacing = .noSnap
    ) throws -> CGRect {
        // --- Validate inputs ---
        try validateFiniteRect(currentVisibleFrame, label: "currentVisibleFrame")
        guard currentVisibleFrame.width > 0 && currentVisibleFrame.height > 0 else {
            throw PlacementError.nonPositiveVisibleSize(currentVisibleFrame.size)
        }
        try validateGridSpacing(gridSpacing)

        try validateFiniteRect(record.absoluteFrame, label: "record.absoluteFrame")
        try validateFiniteRect(
            record.referenceVisibleFrame,
            label: "record.referenceVisibleFrame"
        )
        guard record.referenceVisibleFrame.width > 0
            && record.referenceVisibleFrame.height > 0
        else {
            throw PlacementError.nonPositiveVisibleSize(
                record.referenceVisibleFrame.size
            )
        }

        // Validate preferred size from the record (CGSize does not normalize).
        guard record.preferredSize.width.isFinite
            && record.preferredSize.height.isFinite
        else {
            throw PlacementError.nonFiniteValue("record.preferredSize")
        }
        guard record.preferredSize.width >= 0 && record.preferredSize.height >= 0 else {
            throw PlacementError.negativeDimension(
                "preferredSize (\(record.preferredSize.width), \(record.preferredSize.height))"
            )
        }

        // --- Step 1: Constrain preferred size to current visible frame ---
        let constrainedWidth = min(record.preferredSize.width, currentVisibleFrame.width)
        let constrainedHeight = min(record.preferredSize.height, currentVisibleFrame.height)

        // --- Step 2 or 3: Choose origin ---
        let origin: CGPoint
        let geometryUnchanged = currentVisibleFrame == record.referenceVisibleFrame

        if geometryUnchanged {
            // Prefer the saved absolute origin.
            origin = CGPoint(
                x: record.absoluteFrame.minX,
                y: record.absoluteFrame.minY
            )
        } else {
            // --- Compute movable range with constrained size ---
            let movableWidth = max(0, currentVisibleFrame.width - constrainedWidth)
            let movableHeight = max(0, currentVisibleFrame.height - constrainedHeight)

            // Restore origin from normalized anchor (already clamped to 0...1).
            let ax = currentVisibleFrame.minX
                + CGFloat(record.normalizedAnchor.x) * movableWidth
            let ay = currentVisibleFrame.minY
                + CGFloat(record.normalizedAnchor.y) * movableHeight

            origin = CGPoint(x: ax, y: ay)
        }

        // --- Step 4: Grid-snap ---
        let snappedOrigin = snapToGrid(
            origin: origin,
            gridSpacing: gridSpacing,
            visibleFrameOrigin: currentVisibleFrame.origin
        )

        // --- Step 5: Clamp to visible frame ---
        let clampedX = clampToRange(
            snappedOrigin.x,
            min: currentVisibleFrame.minX,
            max: currentVisibleFrame.maxX - constrainedWidth
        )
        let clampedY = clampToRange(
            snappedOrigin.y,
            min: currentVisibleFrame.minY,
            max: currentVisibleFrame.maxY - constrainedHeight
        )

        return CGRect(
            x: clampedX,
            y: clampedY,
            width: constrainedWidth,
            height: constrainedHeight
        )
    }

    // MARK: - Private Helpers

    private static func validateFiniteRect(_ rect: CGRect, label: String) throws {
        guard rect.origin.x.isFinite && rect.origin.y.isFinite else {
            throw PlacementError.nonFiniteValue("\(label).origin")
        }
        guard rect.size.width.isFinite && rect.size.height.isFinite else {
            throw PlacementError.nonFiniteValue("\(label).size")
        }
    }

    private static func validateGridSpacing(_ gridSpacing: GridSpacing) throws {
        switch gridSpacing {
        case .noSnap:
            return
        case .snap(let value):
            guard value.isFinite && value > 0 else {
                throw PlacementError.invalidGridSpacing(value)
            }
        }
    }

    /// Snap `origin` to the grid relative to `visibleFrameOrigin`.
    /// When snapping is disabled, returns `origin` unchanged.
    private static func snapToGrid(
        origin: CGPoint,
        gridSpacing: GridSpacing,
        visibleFrameOrigin: CGPoint
    ) -> CGPoint {
        switch gridSpacing {
        case .noSnap:
            return origin
        case .snap(let spacing):
            // Snap relative to the visible frame origin so the grid
            // aligns with the display's usable area.
            let relX = origin.x - visibleFrameOrigin.x
            let relY = origin.y - visibleFrameOrigin.y
            let snappedRelX = (relX / spacing)
                .rounded(.toNearestOrAwayFromZero) * spacing
            let snappedRelY = (relY / spacing)
                .rounded(.toNearestOrAwayFromZero) * spacing
            return CGPoint(
                x: visibleFrameOrigin.x + snappedRelX,
                y: visibleFrameOrigin.y + snappedRelY
            )
        }
    }

    /// Clamp a value to `[min, max]`.
    private static func clampToRange(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}
