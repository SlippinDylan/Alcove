// PortalFrameConstraints.swift
// AlcoveCore — Pure constraints for a portal's drag path.
//
// UI-free: AppKit supplies the current visible frame and the frames of the
// other portals. This type only decides where a portal may be placed.

import CoreGraphics
import Foundation

/// Errors reported when a portal drag does not meet its geometry contract.
public enum PortalFrameConstraintError: Error, Sendable, Equatable {
    case nonFiniteValue(String)
    case nonPositiveVisibleSize(CGSize)
    case negativeDimension(String)
    case invalidMinimumGap(CGFloat)
    case inconsistentFrameSize(initial: CGSize, proposed: CGSize)
    case portalExceedsVisibleFrame(CGSize)
    case initialFrameOutsideVisibleFrame
    case initialFrameIntersectsOtherPortal
}

/// Pure geometry for constraining a portal while it is dragged.
///
/// The previous frame must already be legal. The returned frame keeps that
/// frame's size, remains wholly inside `visibleFrame`, and stops at the first
/// portal it would reach along the drag path. The other portals never move.
public enum PortalFrameConstraints {
    /// The default edge-to-edge separation between two portals, in points.
    public static let defaultMinimumGap: CGFloat = 12

    /// Constrains a portal movement to the display and other portal frames.
    ///
    /// The proposed frame must have the same size as `initialFrame`; resizing
    /// has distinct layout semantics and is intentionally outside this drag-only
    /// operation. `initialFrame` must be a frame that is already legal for the
    /// supplied display and portals.
    ///
    /// The proposed origin is first clamped to the display. The resulting path
    /// is then swept from the initial origin to that clamped origin, so a fast
    /// drag cannot pass through another portal between pointer events.
    public static func constrainedDragFrame(
        initialFrame: CGRect,
        proposedFrame: CGRect,
        visibleFrame: CGRect,
        otherPortalFrames: [CGRect],
        minimumGap: CGFloat = defaultMinimumGap
    ) throws -> CGRect {
        try validateFinite(initialFrame, label: "initialFrame")
        try validateFinite(proposedFrame, label: "proposedFrame")
        try validateFinite(visibleFrame, label: "visibleFrame")
        for frame in otherPortalFrames {
            try validateFinite(frame, label: "otherPortalFrame")
        }

        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            throw PortalFrameConstraintError.nonPositiveVisibleSize(visibleFrame.size)
        }
        try validateNonNegativeSize(initialFrame.size, label: "initialFrame")
        try validateNonNegativeSize(proposedFrame.size, label: "proposedFrame")
        for frame in otherPortalFrames {
            try validateNonNegativeSize(frame.size, label: "otherPortalFrame")
        }
        guard minimumGap.isFinite, minimumGap >= 0 else {
            throw PortalFrameConstraintError.invalidMinimumGap(minimumGap)
        }
        guard initialFrame.size == proposedFrame.size else {
            throw PortalFrameConstraintError.inconsistentFrameSize(
                initial: initialFrame.size,
                proposed: proposedFrame.size
            )
        }
        let usableFrame = visibleFrame.insetBy(dx: minimumGap, dy: minimumGap)
        guard usableFrame.width >= 0, usableFrame.height >= 0,
              initialFrame.width <= usableFrame.width,
              initialFrame.height <= usableFrame.height
        else {
            throw PortalFrameConstraintError.portalExceedsVisibleFrame(initialFrame.size)
        }
        guard visibleFrame.contains(initialFrame) else {
            throw PortalFrameConstraintError.initialFrameOutsideVisibleFrame
        }

        let forbiddenOriginFrames = otherPortalFrames.map {
            forbiddenOriginFrame(
                for: $0,
                movingPortalSize: initialFrame.size,
                minimumGap: minimumGap
            )
        }
        guard !forbiddenOriginFrames.contains(where: { strictlyContains($0, initialFrame.origin) }) else {
            throw PortalFrameConstraintError.initialFrameIntersectsOtherPortal
        }

        let targetOrigin = clampedOrigin(
            proposedFrame.origin,
            portalSize: initialFrame.size,
            visibleFrame: usableFrame
        )
        let initialOrigin = initialFrame.origin
        let movement = CGPoint(
            x: targetOrigin.x - initialOrigin.x,
            y: targetOrigin.y - initialOrigin.y
        )

        let stoppingTime = forbiddenOriginFrames.compactMap {
            firstIntersectionTime(
                origin: initialOrigin,
                movement: movement,
                forbiddenOriginFrame: $0
            )
        }.min()

        let resolvedOrigin: CGPoint
        if let stoppingTime {
            resolvedOrigin = CGPoint(
                x: initialOrigin.x + movement.x * stoppingTime,
                y: initialOrigin.y + movement.y * stoppingTime
            )
        } else {
            resolvedOrigin = targetOrigin
        }
        return CGRect(origin: resolvedOrigin, size: initialFrame.size)
    }

    /// Returns whether a frame observes both the display-edge and inter-portal gap.
    public static func isValidPlacement(
        frame: CGRect,
        visibleFrame: CGRect,
        otherPortalFrames: [CGRect],
        minimumGap: CGFloat = defaultMinimumGap
    ) throws -> Bool {
        try validateFinite(frame, label: "frame")
        try validateFinite(visibleFrame, label: "visibleFrame")
        for otherFrame in otherPortalFrames {
            try validateFinite(otherFrame, label: "otherPortalFrame")
        }
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            throw PortalFrameConstraintError.nonPositiveVisibleSize(visibleFrame.size)
        }
        try validateNonNegativeSize(frame.size, label: "frame")
        for otherFrame in otherPortalFrames {
            try validateNonNegativeSize(otherFrame.size, label: "otherPortalFrame")
        }
        guard minimumGap.isFinite, minimumGap >= 0 else {
            throw PortalFrameConstraintError.invalidMinimumGap(minimumGap)
        }

        let usableFrame = visibleFrame.insetBy(dx: minimumGap, dy: minimumGap)
        guard usableFrame.width >= 0, usableFrame.height >= 0,
              usableFrame.contains(frame) else {
            return false
        }
        return !otherPortalFrames.contains {
            framesViolateMinimumGap(frame, $0, minimumGap: minimumGap)
        }
    }

    private static func validateFinite(_ rect: CGRect, label: String) throws {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite
        else {
            throw PortalFrameConstraintError.nonFiniteValue(label)
        }
    }

    private static func validateNonNegativeSize(_ size: CGSize, label: String) throws {
        guard size.width >= 0, size.height >= 0 else {
            throw PortalFrameConstraintError.negativeDimension(label)
        }
    }

    private static func clampedOrigin(
        _ origin: CGPoint,
        portalSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: clamp(
                origin.x,
                minimum: visibleFrame.minX,
                maximum: visibleFrame.maxX - portalSize.width
            ),
            y: clamp(
                origin.y,
                minimum: visibleFrame.minY,
                maximum: visibleFrame.maxY - portalSize.height
            )
        )
    }

    /// Converts an obstacle frame into the origins that would overlap it.
    private static func forbiddenOriginFrame(
        for obstacle: CGRect,
        movingPortalSize: CGSize,
        minimumGap: CGFloat
    ) -> CGRect {
        CGRect(
            x: obstacle.minX - minimumGap - movingPortalSize.width,
            y: obstacle.minY - minimumGap - movingPortalSize.height,
            width: obstacle.width + movingPortalSize.width + minimumGap * 2,
            height: obstacle.height + movingPortalSize.height + minimumGap * 2
        )
    }

    /// Returns the first point in `0...1` where the origin path enters a
    /// forbidden rectangle. Edges are legal: an entry time therefore places the
    /// moving portal exactly at the requested gap rather than one point before it.
    private static func firstIntersectionTime(
        origin: CGPoint,
        movement: CGPoint,
        forbiddenOriginFrame: CGRect
    ) -> CGFloat? {
        let horizontal = intersectionTimes(
            origin: origin.x,
            movement: movement.x,
            minimum: forbiddenOriginFrame.minX,
            maximum: forbiddenOriginFrame.maxX
        )
        let vertical = intersectionTimes(
            origin: origin.y,
            movement: movement.y,
            minimum: forbiddenOriginFrame.minY,
            maximum: forbiddenOriginFrame.maxY
        )
        guard let horizontal, let vertical else {
            return nil
        }

        let entry = max(horizontal.entry, vertical.entry)
        let exit = min(horizontal.exit, vertical.exit)
        guard entry < exit, exit > 0, entry < 1 else {
            return nil
        }
        return max(0, entry)
    }

    /// Finds the interval during which one coordinate lies strictly inside the
    /// forbidden interval. A stationary coordinate outside that interval cannot
    /// collide; a stationary coordinate inside it is active for the whole path.
    private static func intersectionTimes(
        origin: CGFloat,
        movement: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> (entry: CGFloat, exit: CGFloat)? {
        guard movement != 0 else {
            return origin > minimum && origin < maximum
                ? (-.infinity, .infinity)
                : nil
        }
        let first = (minimum - origin) / movement
        let second = (maximum - origin) / movement
        return (min(first, second), max(first, second))
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }

    private static func strictlyContains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x > frame.minX && point.x < frame.maxX
            && point.y > frame.minY && point.y < frame.maxY
    }

    private static func framesViolateMinimumGap(
        _ first: CGRect,
        _ second: CGRect,
        minimumGap: CGFloat
    ) -> Bool {
        first.maxX + minimumGap > second.minX
            && second.maxX + minimumGap > first.minX
            && first.maxY + minimumGap > second.minY
            && second.maxY + minimumGap > first.minY
    }
}
