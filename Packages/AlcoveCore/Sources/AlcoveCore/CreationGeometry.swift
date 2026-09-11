import CoreGraphics
import Foundation

/// A validated grid used to size and align a newly created portal.
public struct CreationGrid: Sendable, Hashable {
    public let minimumSize: CGSize

    fileprivate let columnIncrement: CGFloat
    fileprivate let rowIncrement: CGFloat

    public init(metrics: GridMetrics) throws {
        let values = [
            metrics.itemSize.width,
            metrics.itemSize.height,
            metrics.labelHeight,
            metrics.horizontalSpacing,
            metrics.verticalSpacing,
            metrics.contentInsets.top,
            metrics.contentInsets.leading,
            metrics.contentInsets.bottom,
            metrics.contentInsets.trailing
        ]
        guard values.allSatisfy(\.isFinite) else {
            throw CreationGeometryError.invalidGridMetrics
        }
        guard metrics.itemSize.width > 0,
              metrics.itemSize.height > 0,
              metrics.labelHeight >= 0,
              metrics.horizontalSpacing >= 0,
              metrics.verticalSpacing >= 0,
              metrics.contentInsets.top >= 0,
              metrics.contentInsets.leading >= 0,
              metrics.contentInsets.bottom >= 0,
              metrics.contentInsets.trailing >= 0
        else {
            throw CreationGeometryError.invalidGridMetrics
        }

        let minimumSize = metrics.minimumPortalSize
        let columnIncrement = metrics.itemSize.width + metrics.horizontalSpacing
        let rowIncrement = metrics.itemSize.height + metrics.verticalSpacing
        guard minimumSize.width.isFinite,
              minimumSize.height.isFinite,
              minimumSize.width > 0,
              minimumSize.height > 0,
              columnIncrement.isFinite,
              rowIncrement.isFinite,
              columnIncrement > 0,
              rowIncrement > 0
        else {
            throw CreationGeometryError.invalidGridMetrics
        }

        self.minimumSize = minimumSize
        self.columnIncrement = columnIncrement
        self.rowIncrement = rowIncrement
    }

    fileprivate func snappedSize(for requestedSize: CGSize, within visibleSize: CGSize) -> CGSize {
        CGSize(
            width: snappedExtent(
                requestedSize.width,
                minimum: minimumSize.width,
                increment: columnIncrement,
                limit: visibleSize.width
            ),
            height: snappedExtent(
                requestedSize.height,
                minimum: minimumSize.height,
                increment: rowIncrement,
                limit: visibleSize.height
            )
        )
    }

    private func snappedExtent(
        _ requested: CGFloat,
        minimum: CGFloat,
        increment: CGFloat,
        limit: CGFloat
    ) -> CGFloat {
        guard limit >= minimum else {
            return limit
        }

        let additionalUnits = max(0, ((requested - minimum) / increment).rounded(.up))
        return min(minimum + additionalUnits * increment, limit)
    }
}

/// A finite portal frame wholly contained in the display's visible frame.
public struct CreationRectangle: Sendable, Hashable {
    public let frame: CGRect

    fileprivate init(frame: CGRect) {
        self.frame = frame
    }
}

/// Errors reported when creation geometry cannot establish its input invariants.
public enum CreationGeometryError: Error, Sendable, Equatable {
    case nonFiniteValue(String)
    case nonPositiveVisibleSize(CGSize)
    case invalidGridMetrics
}

/// Pure geometry for the portal-creation drag overlay.
public enum CreationGeometry {
    /// Creates a grid-aligned rectangle from a drag gesture.
    ///
    /// Both gesture points are first clamped to `visibleFrame`. The rectangle grows
    /// from the mouse-down edge toward the current point, which preserves every drag
    /// direction. Its size is then rounded up to the next grid row or column that can
    /// contain the drag. Origins snap to the nearest grid point relative to the visible
    /// frame origin, with half-grid values rounded away from zero. The final clamp keeps
    /// the returned frame on-screen after snapping.
    public static func rectangle(
        mouseDown: CGPoint,
        currentPoint: CGPoint,
        visibleFrame: CGRect,
        grid: CreationGrid
    ) throws -> CreationRectangle {
        try validate(mouseDown, label: "mouseDown")
        try validate(currentPoint, label: "currentPoint")
        try validate(visibleFrame)

        let start = clamped(mouseDown, to: visibleFrame)
        let current = clamped(currentPoint, to: visibleFrame)
        let dragged = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        let requestedSize = CGSize(
            width: min(max(dragged.width, grid.minimumSize.width), visibleFrame.width),
            height: min(max(dragged.height, grid.minimumSize.height), visibleFrame.height)
        )
        let snappedSize = grid.snappedSize(for: requestedSize, within: visibleFrame.size)
        let unsnappedOrigin = CGPoint(
            x: current.x >= start.x ? dragged.minX : dragged.maxX - snappedSize.width,
            y: current.y >= start.y ? dragged.minY : dragged.maxY - snappedSize.height
        )
        let snappedOrigin = CGPoint(
            x: snap(unsnappedOrigin.x, relativeTo: visibleFrame.minX, grid: grid.columnIncrement),
            y: snap(unsnappedOrigin.y, relativeTo: visibleFrame.minY, grid: grid.rowIncrement)
        )
        let origin = CGPoint(
            x: clamp(
                snappedOrigin.x,
                minimum: visibleFrame.minX,
                maximum: visibleFrame.maxX - snappedSize.width
            ),
            y: clamp(
                snappedOrigin.y,
                minimum: visibleFrame.minY,
                maximum: visibleFrame.maxY - snappedSize.height
            )
        )

        return CreationRectangle(frame: CGRect(origin: origin, size: snappedSize))
    }

    private static func validate(_ point: CGPoint, label: String) throws {
        guard point.x.isFinite, point.y.isFinite else {
            throw CreationGeometryError.nonFiniteValue(label)
        }
    }

    private static func validate(_ visibleFrame: CGRect) throws {
        guard visibleFrame.origin.x.isFinite,
              visibleFrame.origin.y.isFinite,
              visibleFrame.width.isFinite,
              visibleFrame.height.isFinite
        else {
            throw CreationGeometryError.nonFiniteValue("visibleFrame")
        }
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            throw CreationGeometryError.nonPositiveVisibleSize(visibleFrame.size)
        }
    }

    private static func clamped(_ point: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(
            x: clamp(point.x, minimum: frame.minX, maximum: frame.maxX),
            y: clamp(point.y, minimum: frame.minY, maximum: frame.maxY)
        )
    }

    private static func snap(_ value: CGFloat, relativeTo origin: CGFloat, grid: CGFloat) -> CGFloat {
        origin + ((value - origin) / grid).rounded(.toNearestOrAwayFromZero) * grid
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}
