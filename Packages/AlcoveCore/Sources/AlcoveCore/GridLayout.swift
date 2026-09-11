import Foundation
import CoreGraphics

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
    public static let minimumColumnCount = 2

    public let iconSize: IconSize
    public let labelHeight: CGFloat
    public let horizontalSpacing: CGFloat
    public let verticalSpacing: CGFloat
    public let contentInsets: GridInsets

    public init(
        iconSize: IconSize,
        labelHeight: CGFloat = 36,
        horizontalSpacing: CGFloat = 16,
        verticalSpacing: CGFloat = 16,
        contentInsets: GridInsets = GridInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    ) {
        self.iconSize = iconSize
        self.labelHeight = labelHeight
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.contentInsets = contentInsets
    }

    public var itemSize: CGSize {
        CGSize(width: iconSize.rawValue, height: iconSize.rawValue + labelHeight)
    }

    public var minimumContainerSize: CGSize {
        CGSize(
            width: contentInsets.leading + contentInsets.trailing
                + (itemSize.width * CGFloat(Self.minimumColumnCount))
                + horizontalSpacing,
            height: contentInsets.top + itemSize.height + contentInsets.bottom
        )
    }

    /// The smallest content area that can display two columns and two rows.
    public var minimumPortalSize: CGSize {
        CGSize(
            width: minimumContainerSize.width,
            height: contentInsets.top + contentInsets.bottom
                + (itemSize.height * CGFloat(Self.minimumColumnCount))
                + verticalSpacing
        )
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
