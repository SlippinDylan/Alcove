// PrimaryDisplayLayout.swift
// AlcoveCore — Pure layout projection and overflow recovery for the primary display.

import CoreGraphics
import Foundation

public enum PrimaryDisplayLayoutError: Error, Sendable, Equatable {
    case nonFiniteFrame(index: Int)
    case nonFiniteVisibleFrame
    case nonPositiveVisibleSize(CGSize)
    case invalidMinimumGap(CGFloat)
    case invalidMinimumExposedHeight(CGFloat)
    case insufficientUsableSize(CGSize)
    case invalidFixedIndex(Int)
}

/// Projects one primary-display layout onto another display and repairs only
/// the frames that no longer fit. Frames selected as fixed are never moved.
public enum PrimaryDisplayLayout {
    /// Preserves a frame's distances from the left and top edges of the source
    /// visible frame. The result is intentionally not clamped so overflow can
    /// be planned for the complete layout instead of independently per panel.
    public static func projectTopLeft(
        frame: CGRect,
        from sourceVisibleFrame: CGRect,
        to targetVisibleFrame: CGRect
    ) throws -> CGRect {
        try validateFinite(frame, index: 0)
        try validateVisibleFrame(sourceVisibleFrame)
        try validateVisibleFrame(targetVisibleFrame)

        let leftOffset = frame.minX - sourceVisibleFrame.minX
        let topOffset = sourceVisibleFrame.maxY - frame.maxY
        return CGRect(
            x: targetVisibleFrame.minX + leftOffset,
            y: targetVisibleFrame.maxY - topOffset - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    /// Keeps every fixed frame unchanged, then places overflow frames in new
    /// columns to their right, from top to bottom. If fixed-size columns cannot
    /// fit, remaining panels cascade with an exposed top strip.
    public static func repairOverflow(
        candidateFrames: [CGRect],
        fixedIndices: Set<Int>,
        visibleFrame: CGRect,
        minimumGap: CGFloat,
        minimumExposedHeight: CGFloat
    ) throws -> [CGRect] {
        try validateVisibleFrame(visibleFrame)
        guard minimumGap.isFinite, minimumGap >= 0 else {
            throw PrimaryDisplayLayoutError.invalidMinimumGap(minimumGap)
        }
        guard minimumExposedHeight.isFinite, minimumExposedHeight > 0 else {
            throw PrimaryDisplayLayoutError.invalidMinimumExposedHeight(minimumExposedHeight)
        }
        for (index, frame) in candidateFrames.enumerated() {
            try validateFinite(frame, index: index)
        }
        for index in fixedIndices where !candidateFrames.indices.contains(index) {
            throw PrimaryDisplayLayoutError.invalidFixedIndex(index)
        }

        let usableFrame = visibleFrame.insetBy(dx: minimumGap, dy: minimumGap)
        guard usableFrame.width > 0, usableFrame.height > 0 else {
            throw PrimaryDisplayLayoutError.insufficientUsableSize(usableFrame.size)
        }
        var result = candidateFrames
        let fixedFrames = fixedIndices.sorted().map { candidateFrames[$0] }
        var placedFrames = fixedFrames
        let overflowIndices = candidateFrames.indices
            .filter { !fixedIndices.contains($0) }
            .sorted { first, second in
                let firstFrame = candidateFrames[first]
                let secondFrame = candidateFrames[second]
                if firstFrame.maxY != secondFrame.maxY {
                    return firstFrame.maxY > secondFrame.maxY
                }
                if firstFrame.minX != secondFrame.minX {
                    return firstFrame.minX < secondFrame.minX
                }
                return first < second
            }

        var columnX = fixedFrames.map(\.maxX).max().map { $0 + minimumGap }
            ?? usableFrame.minX
        var columnTop = usableFrame.maxY
        var columnWidth: CGFloat = 0
        var fallbackIndices: [Int] = []

        for index in overflowIndices {
            let frame = candidateFrames[index]
            var proposed = CGRect(
                x: columnX,
                y: columnTop - frame.height,
                width: frame.width,
                height: frame.height
            )
            if !fits(proposed, in: usableFrame, avoiding: placedFrames, gap: minimumGap) {
                columnX += columnWidth + minimumGap
                columnTop = usableFrame.maxY
                columnWidth = 0
                proposed.origin = CGPoint(x: columnX, y: columnTop - frame.height)
            }
            guard fits(proposed, in: usableFrame, avoiding: placedFrames, gap: minimumGap) else {
                fallbackIndices.append(index)
                continue
            }
            result[index] = proposed
            placedFrames.append(proposed)
            columnTop = proposed.minY - minimumGap
            columnWidth = max(columnWidth, frame.width)
        }

        let exposedHeight = min(minimumExposedHeight, usableFrame.height)
        let visibleRows = max(1, Int(floor(usableFrame.height / exposedHeight)))
        var usedTopLeftPoints = Set(placedFrames.map {
            CGPoint(x: $0.minX, y: $0.maxY)
        })
        for (offset, index) in fallbackIndices.enumerated() {
            let frame = candidateFrames[index]
            let xPositions: [CGFloat]
            if frame.width <= usableFrame.width {
                let rightAlignedX = usableFrame.maxX - frame.width
                let horizontalTravel = rightAlignedX - usableFrame.minX
                let layers = max(1, Int(floor(horizontalTravel / exposedHeight)) + 1)
                xPositions = (0..<layers).map { layer in
                    max(
                        usableFrame.minX,
                        rightAlignedX - CGFloat(layer) * exposedHeight
                    )
                }
            } else {
                xPositions = [usableFrame.minX]
            }
            let slots = xPositions.flatMap { x in
                (0..<visibleRows).map { row in
                    CGPoint(
                        x: x,
                        y: usableFrame.maxY - CGFloat(row) * exposedHeight
                    )
                }
            }
            let topLeft = slots.first { !usedTopLeftPoints.contains($0) }
                ?? slots[offset % slots.count]
            usedTopLeftPoints.insert(topLeft)
            result[index] = CGRect(
                x: topLeft.x,
                y: topLeft.y - frame.height,
                width: frame.width,
                height: frame.height
            )
        }

        return result
    }

    public static func containedIndices(
        in frames: [CGRect],
        visibleFrame: CGRect,
        minimumGap: CGFloat
    ) throws -> Set<Int> {
        try validateVisibleFrame(visibleFrame)
        guard minimumGap.isFinite, minimumGap >= 0 else {
            throw PrimaryDisplayLayoutError.invalidMinimumGap(minimumGap)
        }
        var result = Set<Int>()
        var fixedFrames: [CGRect] = []
        for (index, frame) in frames.enumerated() {
            try validateFinite(frame, index: index)
            if fits(frame, in: visibleFrame, avoiding: fixedFrames, gap: minimumGap) {
                result.insert(index)
                fixedFrames.append(frame)
            }
        }
        return result
    }

    private static func fits(
        _ frame: CGRect,
        in usableFrame: CGRect,
        avoiding otherFrames: [CGRect],
        gap: CGFloat
    ) -> Bool {
        guard usableFrame.contains(frame) else { return false }
        return !otherFrames.contains { other in
            frame.insetBy(dx: -gap, dy: -gap).intersects(other)
        }
    }

    private static func validateFinite(_ frame: CGRect, index: Int) throws {
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite else {
            throw PrimaryDisplayLayoutError.nonFiniteFrame(index: index)
        }
    }

    private static func validateVisibleFrame(_ frame: CGRect) throws {
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite else {
            throw PrimaryDisplayLayoutError.nonFiniteVisibleFrame
        }
        guard frame.width > 0, frame.height > 0 else {
            throw PrimaryDisplayLayoutError.nonPositiveVisibleSize(frame.size)
        }
    }
}
