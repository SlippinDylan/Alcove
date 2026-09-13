// PortalFrameReflow.swift
// AlcoveCore — Deterministic, UI-free layout derived from saved portal frames.

import CoreGraphics
import Foundation

/// Repositions fixed-size portal frames by the minimum amount needed to satisfy
/// display-edge and inter-portal spacing. Input order is the stable priority:
/// earlier portals keep their intended positions before later portals are placed.
public enum PortalFrameReflow {
    /// Distances at or below this value represent an intentional attachment to
    /// a screen edge or another portal, rather than unrelated free placement.
    public static let defaultAttachmentThreshold: CGFloat = 20

    /// Returns `nil` when all fixed-size portals cannot fit on the display.
    public static func reflowedFrames(
        _ frames: [CGRect],
        visibleFrame: CGRect,
        minimumGap: CGFloat,
        attachmentThreshold: CGFloat = defaultAttachmentThreshold
    ) throws -> [CGRect]? {
        var placedFrames: [CGRect] = []
        for (index, frame) in frames.enumerated() {
            let intendedFrame = intendedFrame(
                for: frame,
                at: index,
                originalFrames: frames,
                placedFrames: placedFrames,
                visibleFrame: visibleFrame,
                spacing: minimumGap,
                attachmentThreshold: attachmentThreshold
            )
            guard let placedFrame = try nearestLegalFrame(
                to: intendedFrame,
                visibleFrame: visibleFrame,
                placedFrames: placedFrames,
                minimumGap: minimumGap
            ) else {
                return nil
            }
            placedFrames.append(placedFrame)
        }
        return placedFrames
    }

    private static func intendedFrame(
        for frame: CGRect,
        at index: Int,
        originalFrames: [CGRect],
        placedFrames: [CGRect],
        visibleFrame: CGRect,
        spacing: CGFloat,
        attachmentThreshold: CGFloat
    ) -> CGRect {
        var origin = edgeAdjustedOrigin(
            for: frame,
            visibleFrame: visibleFrame,
            spacing: spacing,
            attachmentThreshold: attachmentThreshold
        )
        var horizontalAttachment: (distance: CGFloat, value: CGFloat)?
        var verticalAttachment: (distance: CGFloat, value: CGFloat)?

        for priorIndex in placedFrames.indices {
            let originalPrior = originalFrames[priorIndex]
            let placedPrior = placedFrames[priorIndex]

            if rangesOverlap(
                frame.minY...frame.maxY,
                originalPrior.minY...originalPrior.maxY
            ) {
                if frame.maxX <= originalPrior.minX {
                    let distance = originalPrior.minX - frame.maxX
                    selectNearest(
                        distance: distance,
                        value: placedPrior.minX - spacing - frame.width,
                        attachment: &horizontalAttachment,
                        threshold: attachmentThreshold
                    )
                } else if originalPrior.maxX <= frame.minX {
                    let distance = frame.minX - originalPrior.maxX
                    selectNearest(
                        distance: distance,
                        value: placedPrior.maxX + spacing,
                        attachment: &horizontalAttachment,
                        threshold: attachmentThreshold
                    )
                }
            }

            if rangesOverlap(
                frame.minX...frame.maxX,
                originalPrior.minX...originalPrior.maxX
            ) {
                if frame.maxY <= originalPrior.minY {
                    let distance = originalPrior.minY - frame.maxY
                    selectNearest(
                        distance: distance,
                        value: placedPrior.minY - spacing - frame.height,
                        attachment: &verticalAttachment,
                        threshold: attachmentThreshold
                    )
                } else if originalPrior.maxY <= frame.minY {
                    let distance = frame.minY - originalPrior.maxY
                    selectNearest(
                        distance: distance,
                        value: placedPrior.maxY + spacing,
                        attachment: &verticalAttachment,
                        threshold: attachmentThreshold
                    )
                }
            }
        }

        if let horizontalAttachment {
            origin.x = horizontalAttachment.value
        }
        if let verticalAttachment {
            origin.y = verticalAttachment.value
        }
        return CGRect(origin: origin, size: frame.size)
    }

    private static func edgeAdjustedOrigin(
        for frame: CGRect,
        visibleFrame: CGRect,
        spacing: CGFloat,
        attachmentThreshold: CGFloat
    ) -> CGPoint {
        var origin = frame.origin
        let leftDistance = frame.minX - visibleFrame.minX
        let rightDistance = visibleFrame.maxX - frame.maxX
        if isAttached(leftDistance, threshold: attachmentThreshold),
           leftDistance <= rightDistance {
            origin.x = visibleFrame.minX + spacing
        } else if isAttached(rightDistance, threshold: attachmentThreshold) {
            origin.x = visibleFrame.maxX - spacing - frame.width
        }

        let bottomDistance = frame.minY - visibleFrame.minY
        let topDistance = visibleFrame.maxY - frame.maxY
        if isAttached(bottomDistance, threshold: attachmentThreshold),
           bottomDistance <= topDistance {
            origin.y = visibleFrame.minY + spacing
        } else if isAttached(topDistance, threshold: attachmentThreshold) {
            origin.y = visibleFrame.maxY - spacing - frame.height
        }
        return origin
    }

    private static func selectNearest(
        distance: CGFloat,
        value: CGFloat,
        attachment: inout (distance: CGFloat, value: CGFloat)?,
        threshold: CGFloat
    ) {
        guard isAttached(distance, threshold: threshold) else {
            return
        }
        if let current = attachment, current.distance <= distance { return }
        attachment = (distance, value)
    }

    private static func isAttached(_ distance: CGFloat, threshold: CGFloat) -> Bool {
        distance >= 0 && distance <= threshold
    }

    private static func rangesOverlap(
        _ first: ClosedRange<CGFloat>,
        _ second: ClosedRange<CGFloat>
    ) -> Bool {
        first.lowerBound < second.upperBound && second.lowerBound < first.upperBound
    }

    private static func nearestLegalFrame(
        to frame: CGRect,
        visibleFrame: CGRect,
        placedFrames: [CGRect],
        minimumGap: CGFloat
    ) throws -> CGRect? {
        let usableFrame = visibleFrame.insetBy(dx: minimumGap, dy: minimumGap)
        guard frame.width <= usableFrame.width, frame.height <= usableFrame.height else {
            return nil
        }

        let clampedOrigin = CGPoint(
            x: clamp(
                frame.minX,
                minimum: usableFrame.minX,
                maximum: usableFrame.maxX - frame.width
            ),
            y: clamp(
                frame.minY,
                minimum: usableFrame.minY,
                maximum: usableFrame.maxY - frame.height
            )
        )
        var xCandidates: Set<CGFloat> = [
            clampedOrigin.x,
            usableFrame.minX,
            usableFrame.maxX - frame.width,
        ]
        var yCandidates: Set<CGFloat> = [
            clampedOrigin.y,
            usableFrame.minY,
            usableFrame.maxY - frame.height,
        ]
        for placedFrame in placedFrames {
            xCandidates.insert(placedFrame.minX - minimumGap - frame.width)
            xCandidates.insert(placedFrame.maxX + minimumGap)
            yCandidates.insert(placedFrame.minY - minimumGap - frame.height)
            yCandidates.insert(placedFrame.maxY + minimumGap)
        }

        return xCandidates.flatMap { x in
            yCandidates.map { y in CGRect(origin: CGPoint(x: x, y: y), size: frame.size) }
        }
        .filter { candidate in
            (try? PortalFrameConstraints.isValidPlacement(
                frame: candidate,
                visibleFrame: visibleFrame,
                otherPortalFrames: placedFrames,
                minimumGap: minimumGap
            )) == true
        }
        .min { first, second in
            let firstDistance = squaredDistance(from: first.origin, to: frame.origin)
            let secondDistance = squaredDistance(from: second.origin, to: frame.origin)
            if firstDistance != secondDistance {
                return firstDistance < secondDistance
            }
            if first.minY != second.minY {
                return first.minY > second.minY
            }
            return first.minX < second.minX
        }
    }

    private static func squaredDistance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}
