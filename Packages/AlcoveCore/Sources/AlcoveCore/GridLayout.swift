import Foundation
import CoreGraphics

/// The durable number of visible icon positions in a portal grid.
public struct GridCapacity: Sendable, Hashable {
    public static let minimumColumns = 3
    public static let minimumRows = 1
    public static let minimum = GridCapacity(
        validatedColumns: minimumColumns,
        validatedRows: minimumRows
    )

    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) throws {
        guard columns >= Self.minimumColumns else {
            throw GridCapacityError.insufficientColumns(columns)
        }
        guard rows >= Self.minimumRows else {
            throw GridCapacityError.insufficientRows(rows)
        }
        self.columns = columns
        self.rows = rows
    }

    init(validatedColumns: Int, validatedRows: Int) {
        columns = validatedColumns
        rows = validatedRows
    }
}

public enum GridCapacityError: Error, Equatable, Sendable {
    case insufficientColumns(Int)
    case insufficientRows(Int)
    case nonFiniteContentSize(CGSize)
}

/// Measurements shared by a portal's tab strip and its grid content.
public enum PortalLayoutMetrics {
    public static let tabBarHeight: CGFloat = 40
}

public struct GridInsets: Sendable, Hashable {
    public let top: CGFloat
    public let leading: CGFloat
    public let bottom: CGFloat
    public let trailing: CGFloat

    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

/// The fixed visual measurements for an icon grid.
public struct GridMetrics: Sendable, Hashable {
    public static let minimumColumnCount = GridCapacity.minimum.columns

    public let iconSize: IconSize
    public let labelFontSize: CGFloat
    public let labelHeight: CGFloat
    public let itemHorizontalPadding: CGFloat
    public let iconSelectionPadding: CGFloat
    public let iconLabelSpacing: CGFloat
    public let horizontalSpacing: CGFloat
    public let verticalSpacing: CGFloat
    public let contentInsets: GridInsets

    public init(
        iconSize: IconSize,
        labelFontSize: CGFloat = 12,
        labelHeight: CGFloat? = nil,
        itemHorizontalPadding: CGFloat? = nil,
        iconSelectionPadding: CGFloat = 4,
        iconLabelSpacing: CGFloat = 4,
        horizontalSpacing: CGFloat = 12,
        verticalSpacing: CGFloat = 4,
        contentInsets: GridInsets = GridInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    ) {
        self.iconSize = iconSize
        self.labelFontSize = labelFontSize
        self.labelHeight = labelHeight
            ?? (labelFontSize * 2.4 + 3).rounded(.up)
        self.itemHorizontalPadding = itemHorizontalPadding ?? iconSize.rawValue * 0.5
        self.iconSelectionPadding = iconSelectionPadding
        self.iconLabelSpacing = iconLabelSpacing
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.contentInsets = contentInsets
    }

    public var itemSize: CGSize {
        CGSize(
            width: iconSize.rawValue + itemHorizontalPadding,
            height: iconSelectionSize.height + iconLabelSpacing + labelHeight
        )
    }

    public var iconSelectionSize: CGSize {
        let extent = iconSize.rawValue + iconSelectionPadding * 2
        return CGSize(width: extent, height: extent)
    }

    public var minimumContainerSize: CGSize {
        contentSize(for: .minimum)
    }

    /// The smallest content area that can display the minimum portal capacity.
    public var minimumPortalSize: CGSize {
        contentSize(for: .minimum)
    }

    /// Returns the grid content extent required to display every position in `capacity`.
    public func contentSize(for capacity: GridCapacity) -> CGSize {
        CGSize(
            width: contentInsets.leading + contentInsets.trailing
                + itemSize.width * CGFloat(capacity.columns)
                + horizontalSpacing * CGFloat(capacity.columns - 1),
            height: contentInsets.top + contentInsets.bottom
                + itemSize.height * CGFloat(capacity.rows)
                + verticalSpacing * CGFloat(capacity.rows - 1)
        )
    }

    /// Quantizes a grid content extent to the nearest valid portal capacity.
    public func nearestCapacity(for contentSize: CGSize) throws -> GridCapacity {
        guard contentSize.width.isFinite, contentSize.height.isFinite else {
            throw GridCapacityError.nonFiniteContentSize(contentSize)
        }
        let columns = nearestCount(
            extent: contentSize.width,
            leadingInset: contentInsets.leading,
            trailingInset: contentInsets.trailing,
            itemExtent: itemSize.width,
            spacing: horizontalSpacing,
            minimum: GridCapacity.minimum.columns
        )
        let rows = nearestCount(
            extent: contentSize.height,
            leadingInset: contentInsets.top,
            trailingInset: contentInsets.bottom,
            itemExtent: itemSize.height,
            spacing: verticalSpacing,
            minimum: GridCapacity.minimum.rows
        )
        return GridCapacity(validatedColumns: columns, validatedRows: rows)
    }

    private func nearestCount(
        extent: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        itemExtent: CGFloat,
        spacing: CGFloat,
        minimum: Int
    ) -> Int {
        let count = ((extent - leadingInset - trailingInset + spacing) / (itemExtent + spacing))
            .rounded(.toNearestOrAwayFromZero)
        return max(minimum, Int(count))
    }
}

/// A pure layout calculator for the scrollable icon grid.
public struct GridLayout: Sendable {
    public let metrics: GridMetrics

    public init(metrics: GridMetrics) {
        self.metrics = metrics
    }

    public func layout(itemCount: Int, availableWidth: CGFloat) -> GridLayoutResult {
        let columnCount = derivedColumnCount(availableWidth: availableWidth)
        let rowCount = itemCount.quotientAndRemainder(dividingBy: columnCount).quotient
            + (itemCount.isMultiple(of: columnCount) ? 0 : 1)
        let contentWidth = max(availableWidth, metrics.minimumContainerSize.width)
        let contentHeight = metrics.contentInsets.top
            + (CGFloat(rowCount) * metrics.itemSize.height)
            + (CGFloat(max(0, rowCount - 1)) * metrics.verticalSpacing)
            + metrics.contentInsets.bottom
        let frames = (0..<itemCount).map { index in
            let row = index / columnCount
            let column = index % columnCount
            let x = metrics.contentInsets.leading
                + CGFloat(column) * (metrics.itemSize.width + metrics.horizontalSpacing)
            let y = metrics.contentInsets.top
                + CGFloat(row) * (metrics.itemSize.height + metrics.verticalSpacing)
            return CGRect(
                x: x,
                y: y,
                width: metrics.itemSize.width,
                height: metrics.itemSize.height
            )
        }

        return GridLayoutResult(
            columnCount: columnCount,
            contentSize: CGSize(width: contentWidth, height: contentHeight),
            itemFrames: frames
        )
    }

    private func derivedColumnCount(availableWidth: CGFloat) -> Int {
        let usableWidth = max(0, availableWidth - metrics.contentInsets.leading - metrics.contentInsets.trailing)
        let columnWidth = metrics.itemSize.width + metrics.horizontalSpacing
        let fittingColumnCount = Int((usableWidth + metrics.horizontalSpacing) / columnWidth)
        return max(GridMetrics.minimumColumnCount, fittingColumnCount)
    }
}

/// The transient output of a single layout pass. Its column count is derived, never persistence state.
public struct GridLayoutResult: Sendable {
    public let columnCount: Int
    public let contentSize: CGSize
    public let itemFrames: [CGRect]
}
