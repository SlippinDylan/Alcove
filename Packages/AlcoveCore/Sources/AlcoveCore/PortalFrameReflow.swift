// PortalFrameReflow.swift
// AlcoveCore — Deterministic, UI-free layout derived from saved portal frames.

import CoreGraphics
import Foundation

/// Repositions fixed-size portal frames by the minimum amount needed to satisfy
/// display-edge and inter-portal spacing. Input order is the stable priority:
/// earlier portals keep their intended positions before later portals are placed.
public enum PortalFrameReflow {
    /// Returns `nil` when all fixed-size portals cannot fit on the display.
    public static func reflowedFrames(
        _ frames: [CGRect],
        visibleFrame: CGRect,
        minimumGap: CGFloat
    ) throws -> [CGRect]? {
        var placedFrames: [CGRect] = []
        for frame in frames {
            guard let placedFrame = try nearestLegalFrame(
                to: frame,
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
