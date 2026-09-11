// DisplayPlacement.swift
// Alcove — AppKit display identity and topology boundary.
//
// This file keeps NSScreen and CoreGraphics lookup outside AlcoveCore. The
// snapshot intentionally does not expose NSScreen ordering as an identity.

import AppKit
import CoreGraphics
import Foundation

import AlcoveCore

public enum DisplaySnapshotError: Error, Sendable, Equatable {
    case noScreensAvailable
    case missingPrimaryScreen
    case missingDisplayID
    case nonNumericDisplayID
    case invalidDisplayIDValue
    case unavailableDisplayUUID(CGDirectDisplayID)
    case duplicateDisplayIdentity(DisplayIdentity)
    case primaryDisplayUnavailable(DisplayIdentity)
    case invalidVisibleFrame(DisplayIdentity)
    case nonFiniteLegacyFrame
    case nonFiniteIntersectionArea
    case captureFailed(String)
}

/// A complete topology snapshot suitable for placement reconciliation.
///
/// `primaryDisplay` is captured explicitly from `NSScreen.main`; consumers
/// must not infer it from the order of `NSScreen.screens`.
public struct DisplaySnapshot: Sendable, Equatable {
    public let displays: [DisplayDescriptor]
    public let primaryDisplay: DisplayIdentity
    public let primaryDescriptor: DisplayDescriptor

    public init(
        displays: [DisplayDescriptor],
        primaryDisplay: DisplayIdentity
    ) throws {
        guard !displays.isEmpty else {
            throw DisplaySnapshotError.noScreensAvailable
        }

        var identities = Set<DisplayIdentity>()
        for display in displays {
            guard display.visibleFrame.hasFinitePositiveSize else {
                throw DisplaySnapshotError.invalidVisibleFrame(display.identity)
            }
            guard identities.insert(display.identity).inserted else {
                throw DisplaySnapshotError.duplicateDisplayIdentity(display.identity)
            }
        }
        guard let primaryDescriptor = displays.first(where: { $0.identity == primaryDisplay }) else {
            throw DisplaySnapshotError.primaryDisplayUnavailable(primaryDisplay)
        }

        self.displays = displays
        self.primaryDisplay = primaryDisplay
        self.primaryDescriptor = primaryDescriptor
    }

    /// Captures all current displays and their canonical CoreGraphics UUIDs.
    @MainActor
    public static func capture() throws -> DisplaySnapshot {
        guard let mainScreen = NSScreen.main else {
            throw DisplaySnapshotError.missingPrimaryScreen
        }

        let primaryDisplay = try identity(for: mainScreen)
        let displays = try NSScreen.screens.map(descriptor(for:))
        return try DisplaySnapshot(
            displays: displays,
            primaryDisplay: primaryDisplay
        )
    }

    /// Captures the current topology while preserving an explicit error value
    /// for notification-driven callers.
    @MainActor
    public static func captureResult() -> Result<DisplaySnapshot, DisplaySnapshotError> {
        do {
            return .success(try capture())
        } catch let error as DisplaySnapshotError {
            return .failure(error)
        } catch {
            return .failure(.captureFailed(error.localizedDescription))
        }
    }

    public func display(with identity: DisplayIdentity) -> DisplayDescriptor? {
        displays.first { $0.identity == identity }
    }

    @MainActor
    private static func descriptor(for screen: NSScreen) throws -> DisplayDescriptor {
        DisplayDescriptor(
            identity: try identity(for: screen),
            visibleFrame: screen.visibleFrame
        )
    }

    @MainActor
    private static func identity(for screen: NSScreen) throws -> DisplayIdentity {
        let displayID = try DisplayIdentityLookup.displayID(from: screen.deviceDescription)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            throw DisplaySnapshotError.unavailableDisplayUUID(displayID)
        }
        return DisplayIdentity(rawValue: DisplayIdentityLookup.format(uuid.takeRetainedValue()))
    }
}

/// Resolves a legacy, display-unscoped portal frame to a screen identity.
///
/// The display with the largest positive overlap wins. Frames outside every
/// visible frame belong to the explicit primary display. Equal overlap first
/// prefers the primary display and then uses the UUID string as a stable tie
/// breaker, so the result never depends on NSScreen array ordering.
public enum LegacyFrameDisplayResolver {
    public static func resolve(
        frame: CGRect,
        in snapshot: DisplaySnapshot
    ) throws -> DisplayDescriptor {
        guard frame.hasFiniteComponents else {
            throw DisplaySnapshotError.nonFiniteLegacyFrame
        }

        var selected: (display: DisplayDescriptor, area: CGFloat)?
        for display in snapshot.displays {
            let intersection = frame.intersection(display.visibleFrame)
            guard !intersection.isNull,
                  intersection.width > 0,
                  intersection.height > 0 else {
                continue
            }

            let area = intersection.width * intersection.height
            guard area.isFinite else {
                throw DisplaySnapshotError.nonFiniteIntersectionArea
            }

            guard let current = selected else {
                selected = (display, area)
                continue
            }

            if area > current.area || (
                area == current.area
                    && isPreferred(display, over: current.display, primary: snapshot.primaryDisplay)
            ) {
                selected = (display, area)
            }
        }

        return selected?.display ?? snapshot.primaryDescriptor
    }

    private static func isPreferred(
        _ candidate: DisplayDescriptor,
        over current: DisplayDescriptor,
        primary: DisplayIdentity
    ) -> Bool {
        if candidate.identity == primary {
            return current.identity != primary
        }
        if current.identity == primary {
            return false
        }
        return candidate.identity.rawValue < current.identity.rawValue
    }
}

struct SystemLegacyDisplayResolver: LegacyDisplayResolving {
    private let snapshotResult: Result<DisplaySnapshot, DisplaySnapshotError>

    @MainActor
    init(
        snapshotProvider: DisplayPlacementObserver.SnapshotProvider = {
            DisplaySnapshot.captureResult()
        }
    ) {
        snapshotResult = snapshotProvider()
    }

    func resolveDisplay(forLegacyFrame frame: CGRect) throws -> DisplayDescriptor {
        try LegacyFrameDisplayResolver.resolve(
            frame: frame,
            in: snapshotResult.get()
        )
    }
}

/// Owns the display-parameter notification registration and always delivers
/// fresh topology results on the main actor.
@MainActor
public final class DisplayPlacementObserver {
    public typealias SnapshotProvider = @MainActor () -> Result<DisplaySnapshot, DisplaySnapshotError>
    public typealias EventHandler = @MainActor (Result<DisplaySnapshot, DisplaySnapshotError>) -> Void

    private let center: NotificationCenter
    private let wakeCenter: NotificationCenter
    private let snapshotProvider: SnapshotProvider
    private let eventHandler: EventHandler
    private var registration: DisplayNotificationRegistration?
    private var generation: UInt64 = 0

    public var isObserving: Bool {
        registration != nil
    }

    public init(
        center: NotificationCenter = .default,
        wakeCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        snapshotProvider: @escaping SnapshotProvider = { DisplaySnapshot.captureResult() },
        eventHandler: @escaping EventHandler
    ) {
        self.center = center
        self.wakeCenter = wakeCenter
        self.snapshotProvider = snapshotProvider
        self.eventHandler = eventHandler
    }

    public func start() {
        guard registration == nil else {
            return
        }

        generation += 1
        let registrationGeneration = generation
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            _ = Task { @MainActor [weak self] in
                guard let self,
                      self.registration != nil,
                      self.generation == registrationGeneration else {
                    return
                }
                self.eventHandler(self.snapshotProvider())
            }
        }
        let screenToken = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil,
            using: handler
        )
        let wakeToken = wakeCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil,
            using: handler
        )
        registration = DisplayNotificationRegistration(
            entries: [
                DisplayNotificationEntry(center: center, token: screenToken),
                DisplayNotificationEntry(center: wakeCenter, token: wakeToken),
            ]
        )
    }

    public func stop() {
        registration = nil
    }

}

private final class DisplayNotificationRegistration {
    private let entries: [DisplayNotificationEntry]

    init(entries: [DisplayNotificationEntry]) {
        self.entries = entries
    }

    deinit {
        for entry in entries {
            entry.center.removeObserver(entry.token)
        }
    }
}

private struct DisplayNotificationEntry {
    let center: NotificationCenter
    let token: any NSObjectProtocol
}

public enum DisplayIdentityLookup {
    public static func displayID(
        from description: [NSDeviceDescriptionKey: Any]
    ) throws -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let value = description[key] else {
            throw DisplaySnapshotError.missingDisplayID
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID() else {
            throw DisplaySnapshotError.nonNumericDisplayID
        }

        let numericValue = number.doubleValue
        guard numericValue.isFinite,
              numericValue.rounded(.towardZero) == numericValue,
              numericValue >= 0,
              numericValue <= Double(UInt32.max) else {
            throw DisplaySnapshotError.invalidDisplayIDValue
        }
        return CGDirectDisplayID(UInt32(numericValue))
    }

    public static func format(_ uuid: CFUUID) -> String {
        let bytes = CFUUIDGetUUIDBytes(uuid)
        return String(
            format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            bytes.byte0, bytes.byte1, bytes.byte2, bytes.byte3,
            bytes.byte4, bytes.byte5,
            bytes.byte6, bytes.byte7,
            bytes.byte8, bytes.byte9,
            bytes.byte10, bytes.byte11, bytes.byte12, bytes.byte13,
            bytes.byte14, bytes.byte15
        )
    }
}

private extension CGRect {
    var hasFiniteComponents: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && width.isFinite
            && height.isFinite
    }

    var hasFinitePositiveSize: Bool {
        hasFiniteComponents && width > 0 && height > 0
    }
}
