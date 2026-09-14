// PlacementStateMachine.swift
// AlcoveCore — Pure primary-display-following placement state.
//
// UI-free and persistence-free. This reducer distinguishes explicit user
// placement from system-driven movement and emits window placement directives.

import CoreGraphics
import Foundation

public struct DisplayIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct DisplayDescriptor: Sendable, Equatable {
    public let identity: DisplayIdentity
    public let visibleFrame: CGRect

    public init(identity: DisplayIdentity, visibleFrame: CGRect) {
        self.identity = identity
        self.visibleFrame = visibleFrame
    }
}

public enum PlacementPresentation: Sendable, Equatable {
    case active(on: DisplayIdentity)
    case temporarilyDisplaced(to: DisplayIdentity)
    case awaitingDisplay

    public var display: DisplayIdentity? {
        switch self {
        case .active(let display), .temporarilyDisplaced(let display):
            display
        case .awaitingDisplay:
            nil
        }
    }
}

/// Pure state. `placements` contains user-confirmed records only.
public struct PlacementSession: Sendable, Equatable {
    public private(set) var placements: [DisplayIdentity: DisplayPlacementEntry]
    public private(set) var homeDisplay: DisplayIdentity
    public private(set) var presentation: PlacementPresentation

    public init(
        placements: [DisplayIdentity: DisplayPlacementEntry],
        homeDisplay: DisplayIdentity,
        presentation: PlacementPresentation
    ) throws {
        guard placements[homeDisplay] != nil else {
            throw PlacementStateError.missingHomePlacement(homeDisplay)
        }
        switch presentation {
        case .active(let display) where display != homeDisplay,
             .temporarilyDisplaced(let display) where display == homeDisplay:
            throw PlacementStateError.invalidPresentation(
                home: homeDisplay,
                presentation: presentation
            )
        default:
            break
        }
        self.placements = placements
        self.homeDisplay = homeDisplay
        self.presentation = presentation
    }

    fileprivate mutating func recordUserPlacement(
        _ placement: DisplayPlacementEntry,
        on display: DisplayIdentity
    ) {
        placements[display] = placement
        homeDisplay = display
        presentation = .active(on: display)
    }

    fileprivate mutating func recordSystemPresentation(on display: DisplayIdentity) {
        presentation = display == homeDisplay
            ? .active(on: display)
            : .temporarilyDisplaced(to: display)
    }

    fileprivate mutating func awaitDisplay() {
        presentation = .awaitingDisplay
    }
}

public enum FrameChangeOrigin: Sendable, Equatable {
    case userInteractionEnded
    case system
}

public enum PlacementDirectiveReason: Sendable, Equatable {
    case refreshHomeGeometry
    case restoreReturnedHome
    case followPrimaryDisplay
}

public struct PlacementDirective: Sendable, Equatable {
    public let targetDisplay: DisplayIdentity
    public let frame: CGRect
    public let reason: PlacementDirectiveReason

    public init(
        targetDisplay: DisplayIdentity,
        frame: CGRect,
        reason: PlacementDirectiveReason
    ) {
        self.targetDisplay = targetDisplay
        self.frame = frame
        self.reason = reason
    }
}

public struct PlacementTransition: Sendable, Equatable {
    public let session: PlacementSession
    public let directive: PlacementDirective?

    public init(session: PlacementSession, directive: PlacementDirective?) {
        self.session = session
        self.directive = directive
    }
}

public enum PlacementStateError: Error, Sendable, Equatable {
    case missingHomePlacement(DisplayIdentity)
    case invalidPresentation(home: DisplayIdentity, presentation: PlacementPresentation)
    case primaryDisplayUnavailable(DisplayIdentity)
    case duplicateDisplayIdentity(DisplayIdentity)
    case invalidGeometry(PlacementError)
    case invalidPrimaryLayout(PrimaryDisplayLayoutError)
}

public enum PlacementStateMachine {
    /// Record a frame notification without confusing its origin.
    ///
    /// Only `.userInteractionEnded` captures a durable placement and changes
    /// `homeDisplay`. System changes update transient presentation only.
    public static func recordFrameChange(
        session: PlacementSession,
        frame: CGRect,
        display: DisplayDescriptor,
        origin: FrameChangeOrigin
    ) throws -> PlacementSession {
        var updated = session
        switch origin {
        case .userInteractionEnded:
            do {
                let placement = try PlacementGeometry.capture(
                    windowFrame: frame,
                    visibleFrame: display.visibleFrame
                )
                updated.recordUserPlacement(placement, on: display.identity)
            } catch let error as PlacementError {
                throw PlacementStateError.invalidGeometry(error)
            }
        case .system:
            updated.recordSystemPresentation(on: display.identity)
        }
        return updated
    }

    /// Updates only transient presentation state for a topology snapshot. Frame
    /// planning remains the responsibility of the complete-layout planner.
    public static func reconcilePresentation(
        session: PlacementSession,
        displays: [DisplayDescriptor],
        primaryDisplay: DisplayIdentity
    ) throws -> PlacementSession {
        guard !displays.isEmpty else {
            var updated = session
            updated.awaitDisplay()
            return updated
        }
        let displaysByIdentity = try validatedDisplays(displays)
        guard displaysByIdentity[primaryDisplay] != nil else {
            throw PlacementStateError.primaryDisplayUnavailable(primaryDisplay)
        }
        var updated = session
        updated.recordSystemPresentation(on: primaryDisplay)
        return updated
    }

    /// Reconcile saved placement against the current menu-bar primary display.
    ///
    /// A placement previously recorded for the primary display wins. Otherwise
    /// the home placement supplies the size and relative position. System
    /// reconciliation never changes durable placement records or `homeDisplay`.
    public static func reconcileTopology(
        session: PlacementSession,
        displays: [DisplayDescriptor],
        primaryDisplay: DisplayIdentity,
        gridSpacing: GridSpacing = .noSnap
    ) throws -> PlacementTransition {
        guard !displays.isEmpty else {
            var updated = session
            updated.awaitDisplay()
            return PlacementTransition(session: updated, directive: nil)
        }
        let displaysByIdentity = try validatedDisplays(displays)
        guard let homePlacement = session.placements[session.homeDisplay] else {
            throw PlacementStateError.missingHomePlacement(session.homeDisplay)
        }

        guard let primary = displaysByIdentity[primaryDisplay] else {
            throw PlacementStateError.primaryDisplayUnavailable(primaryDisplay)
        }
        let targetPlacement = session.placements[primaryDisplay] ?? homePlacement
        let restored = try projectToPrimary(
            targetPlacement,
            visibleFrame: primary.visibleFrame,
            gridSpacing: gridSpacing
        )
        var updated = session
        updated.recordSystemPresentation(on: primary.identity)
        let reason: PlacementDirectiveReason
        if primary.identity != session.homeDisplay {
            reason = .followPrimaryDisplay
        } else {
            reason = switch session.presentation {
            case .active:
                .refreshHomeGeometry
            case .temporarilyDisplaced, .awaitingDisplay:
                .restoreReturnedHome
            }
        }
        return PlacementTransition(
            session: updated,
            directive: PlacementDirective(
                targetDisplay: primary.identity,
                frame: restored,
                reason: reason
            )
        )
    }

    private static func validatedDisplays(
        _ displays: [DisplayDescriptor]
    ) throws -> [DisplayIdentity: DisplayDescriptor] {
        var result: [DisplayIdentity: DisplayDescriptor] = [:]
        for display in displays {
            guard result.updateValue(display, forKey: display.identity) == nil else {
                throw PlacementStateError.duplicateDisplayIdentity(display.identity)
            }
        }
        return result
    }

    private static func projectToPrimary(
        _ placement: DisplayPlacementEntry,
        visibleFrame: CGRect,
        gridSpacing: GridSpacing
    ) throws -> CGRect {
        do {
            let projected = try PrimaryDisplayLayout.projectTopLeft(
                frame: placement.absoluteFrame,
                from: placement.referenceVisibleFrame,
                to: visibleFrame
            )
            let projectedPlacement = try PlacementGeometry.capture(
                windowFrame: projected,
                visibleFrame: visibleFrame
            )
            return try PlacementGeometry.restore(
                record: projectedPlacement,
                currentVisibleFrame: visibleFrame,
                gridSpacing: gridSpacing
            )
        } catch let error as PrimaryDisplayLayoutError {
            throw PlacementStateError.invalidPrimaryLayout(error)
        } catch let error as PlacementError {
            throw PlacementStateError.invalidGeometry(error)
        }
    }

}
