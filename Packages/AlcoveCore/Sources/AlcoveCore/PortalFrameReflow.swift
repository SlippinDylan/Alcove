// PortalFrameReflow.swift
// AlcoveCore — Deterministic, UI-free layout derived from saved portal frames.

import CoreGraphics
import Foundation

public enum PortalFrameReflowError: Error, Sendable, Equatable {
    case mismatchedFrameCounts(targets: Int, references: Int)
    case invalidReferenceFrame(index: Int)
}

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
        try reflowedFrames(
            frames,
            attachmentReferenceFrames: frames,
            visibleFrame: visibleFrame,
            minimumGap: minimumGap,
            attachmentThreshold: attachmentThreshold
        )
    }

    /// Reflows target frames while deriving edge and portal attachments from a
    /// separate pre-change snapshot. This preserves relationships when a size
    /// increase makes the unadjusted target frames overlap.
    public static func reflowedFrames(
        _ targetFrames: [CGRect],
        attachmentReferenceFrames: [CGRect],
        visibleFrame: CGRect,
        minimumGap: CGFloat,
        attachmentThreshold: CGFloat = defaultAttachmentThreshold
    ) throws -> [CGRect]? {
        guard targetFrames.count == attachmentReferenceFrames.count else {
            throw PortalFrameReflowError.mismatchedFrameCounts(
                targets: targetFrames.count,
                references: attachmentReferenceFrames.count
            )
        }
        for (index, frame) in attachmentReferenceFrames.enumerated() {
            guard frame.origin.x.isFinite,
                  frame.origin.y.isFinite,
                  frame.width.isFinite,
                  frame.height.isFinite,
                  frame.width >= 0,
                  frame.height >= 0 else {
                throw PortalFrameReflowError.invalidReferenceFrame(index: index)
            }
        }
        var placedFrames: [CGRect] = []
        for (index, targetFrame) in targetFrames.enumerated() {
            let intendedFrame = intendedFrame(
                for: targetFrame,
                at: index,
                attachmentReferenceFrames: attachmentReferenceFrames,
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
        for targetFrame: CGRect,
        at index: Int,
        attachmentReferenceFrames: [CGRect],
        placedFrames: [CGRect],
        visibleFrame: CGRect,
        spacing: CGFloat,
        attachmentThreshold: CGFloat
    ) -> CGRect {
        let referenceFrame = attachmentReferenceFrames[index]
        var origin = edgeAdjustedOrigin(
            for: targetFrame,
            referenceFrame: referenceFrame,
            visibleFrame: visibleFrame,
            spacing: spacing,
            attachmentThreshold: attachmentThreshold
        )
        var horizontalAttachment: (distance: CGFloat, value: CGFloat)?
        var verticalAttachment: (distance: CGFloat, value: CGFloat)?

        for priorIndex in placedFrames.indices {
            let referencePrior = attachmentReferenceFrames[priorIndex]
            let placedPrior = placedFrames[priorIndex]

            if rangesOverlap(
                referenceFrame.minY...referenceFrame.maxY,
                referencePrior.minY...referencePrior.maxY
            ) {
                if referenceFrame.maxX <= referencePrior.minX {
                    let distance = referencePrior.minX - referenceFrame.maxX
                    selectNearest(
                        distance: distance,
                        value: placedPrior.minX - spacing - targetFrame.width,
                        attachment: &horizontalAttachment,
                        threshold: attachmentThreshold
                    )
                } else if referencePrior.maxX <= referenceFrame.minX {
                    let distance = referenceFrame.minX - referencePrior.maxX
                    selectNearest(
                        distance: distance,
                        value: placedPrior.maxX + spacing,
                        attachment: &horizontalAttachment,
                        threshold: attachmentThreshold
                    )
                }
            }

            if rangesOverlap(
                referenceFrame.minX...referenceFrame.maxX,
                referencePrior.minX...referencePrior.maxX
            ) {
                if referenceFrame.maxY <= referencePrior.minY {
                    let distance = referencePrior.minY - referenceFrame.maxY
                    selectNearest(
                        distance: distance,
                        value: placedPrior.minY - spacing - targetFrame.height,
                        attachment: &verticalAttachment,
                        threshold: attachmentThreshold
                    )
                } else if referencePrior.maxY <= referenceFrame.minY {
                    let distance = referenceFrame.minY - referencePrior.maxY
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
        return CGRect(origin: origin, size: targetFrame.size)
    }

    private static func edgeAdjustedOrigin(
        for targetFrame: CGRect,
        referenceFrame: CGRect,
        visibleFrame: CGRect,
        spacing: CGFloat,
        attachmentThreshold: CGFloat
    ) -> CGPoint {
        var origin = targetFrame.origin
        let leftDistance = referenceFrame.minX - visibleFrame.minX
        let rightDistance = visibleFrame.maxX - referenceFrame.maxX
        if isAttached(leftDistance, threshold: attachmentThreshold),
           leftDistance <= rightDistance {
            origin.x = visibleFrame.minX + spacing
        } else if isAttached(rightDistance, threshold: attachmentThreshold) {
            origin.x = visibleFrame.maxX - spacing - targetFrame.width
        }

        let bottomDistance = referenceFrame.minY - visibleFrame.minY
        let topDistance = visibleFrame.maxY - referenceFrame.maxY
        if isAttached(bottomDistance, threshold: attachmentThreshold),
           bottomDistance <= topDistance {
            origin.y = visibleFrame.minY + spacing
        } else if isAttached(topDistance, threshold: attachmentThreshold) {
            origin.y = visibleFrame.maxY - spacing - targetFrame.height
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
