import CoreGraphics
import Foundation

/// A validated grid used to size and align a newly created portal.
public struct CreationGrid: Sendable, Hashable {
    public let metrics: GridMetrics
    public let minimumSize: CGSize

    public let columnIncrement: CGFloat
    public let rowIncrement: CGFloat

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
              metrics.labelFontSize > 0,
              metrics.labelHeight >= 0,
              metrics.itemHorizontalPadding >= 0,
              metrics.iconSelectionPadding >= 0,
              metrics.iconLabelSpacing >= 0,
              metrics.horizontalSpacing >= 0,
              metrics.verticalSpacing >= 0,
              metrics.contentInsets.top >= 0,
              metrics.contentInsets.leading >= 0,
              metrics.contentInsets.bottom >= 0,
              metrics.contentInsets.trailing >= 0
        else {
            throw CreationGeometryError.invalidGridMetrics
        }

        let minimumGridSize = metrics.contentSize(for: .minimum)
        let minimumSize = CGSize(
            width: minimumGridSize.width,
            height: minimumGridSize.height + PortalLayoutMetrics.chromeHeight
        )
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

        self.metrics = metrics
        self.minimumSize = minimumSize
        self.columnIncrement = columnIncrement
        self.rowIncrement = rowIncrement
    }

    public func cardSize(for capacity: GridCapacity) -> CGSize {
        let gridSize = metrics.contentSize(for: capacity)
        return CGSize(
            width: gridSize.width,
            height: gridSize.height + PortalLayoutMetrics.chromeHeight
        )
    }

    fileprivate func selection(
        for requestedSize: CGSize,
        within visibleSize: CGSize
    ) -> CreationGridSelection {
        let horizontal = quantizedExtent(
                requestedSize.width,
                minimum: minimumSize.width,
                increment: columnIncrement,
                limit: visibleSize.width,
                minimumCount: GridCapacity.minimumColumns
            )
        let vertical = quantizedExtent(
                requestedSize.height,
                minimum: minimumSize.height,
                increment: rowIncrement,
                limit: visibleSize.height,
                minimumCount: GridCapacity.minimumRows
            )
        return CreationGridSelection(
            capacity: GridCapacity(
                validatedColumns: horizontal.count,
                validatedRows: vertical.count
            ),
            size: CGSize(width: horizontal.extent, height: vertical.extent),
            ghostColumnProgress: horizontal.ghostProgress,
            ghostRowProgress: vertical.ghostProgress
        )
    }

    private func quantizedExtent(
        _ requested: CGFloat,
        minimum: CGFloat,
        increment: CGFloat,
        limit: CGFloat,
        minimumCount: Int
    ) -> (extent: CGFloat, count: Int, ghostProgress: CGFloat) {
        guard limit >= minimum else {
            return (limit, minimumCount, 0)
        }

        let rawAdditionalUnits = max(0, (requested - minimum) / increment)
        let maximumAdditionalUnits = Int(((limit - minimum) / increment).rounded(.down))
        let additionalUnits = min(
            maximumAdditionalUnits,
            Int(rawAdditionalUnits.rounded(.toNearestOrAwayFromZero))
        )
        let lowerUnits = Int(rawAdditionalUnits.rounded(.down))
        let ghostProgress: CGFloat
        if additionalUnits == lowerUnits, additionalUnits < maximumAdditionalUnits {
            ghostProgress = min(1, (rawAdditionalUnits - CGFloat(lowerUnits)) * 2)
        } else {
            ghostProgress = 0
        }
        return (
            minimum + CGFloat(additionalUnits) * increment,
            minimumCount + additionalUnits,
            ghostProgress
        )
    }
}

public struct CreationGridSelection: Sendable, Hashable {
    public let capacity: GridCapacity
    public let size: CGSize
    public let ghostColumnProgress: CGFloat
    public let ghostRowProgress: CGFloat
}

/// A finite portal frame wholly contained in the display's visible frame.
public struct CreationRectangle: Sendable, Hashable {
    public let frame: CGRect
    public let capacity: GridCapacity
    public let ghostColumnProgress: CGFloat
    public let ghostRowProgress: CGFloat

    fileprivate init(frame: CGRect, selection: CreationGridSelection) {
        self.frame = frame
        capacity = selection.capacity
        ghostColumnProgress = selection.ghostColumnProgress
        ghostRowProgress = selection.ghostRowProgress
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
    /// direction. Its size switches to the nearest whole grid row or column at each
    /// half-unit threshold. The final clamp keeps the returned frame on-screen.
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
        let selection = grid.selection(for: requestedSize, within: visibleFrame.size)
        let horizontal = snappedAxis(
            minimum: dragged.minX,
            maximum: dragged.maxX,
            extent: selection.size.width,
            growsPositive: current.x >= start.x,
            visibleMinimum: visibleFrame.minX,
            visibleMaximum: visibleFrame.maxX
        )
        let vertical = snappedAxis(
            minimum: dragged.minY,
            maximum: dragged.maxY,
            extent: selection.size.height,
            growsPositive: current.y >= start.y,
            visibleMinimum: visibleFrame.minY,
            visibleMaximum: visibleFrame.maxY
        )
        return CreationRectangle(
            frame: CGRect(
                x: horizontal.origin,
                y: vertical.origin,
                width: horizontal.extent,
                height: vertical.extent
            ),
            selection: selection
        )
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

    private static func snappedAxis(
        minimum: CGFloat,
        maximum: CGFloat,
        extent: CGFloat,
        growsPositive: Bool,
        visibleMinimum: CGFloat,
        visibleMaximum: CGFloat
    ) -> (origin: CGFloat, extent: CGFloat) {
        let visibleExtent = visibleMaximum - visibleMinimum
        if extent >= visibleExtent {
            return (visibleMinimum, visibleExtent)
        }
        let origin = growsPositive ? minimum : maximum - extent
        return (
            clamp(origin, minimum: visibleMinimum, maximum: visibleMaximum - extent),
            extent
        )
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}
