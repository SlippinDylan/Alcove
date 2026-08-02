// ScreenRecord.swift
// Alcove Spike 0.2B — Display inventory snapshot DTO.
//
// Codable record for a single screen's diagnostic properties.
// Key ordering is deterministic because the struct uses synthesized Codable.
// Disposable spike code, not production AlcoveCore.

import CoreGraphics
import Foundation

/// Diagnostic snapshot of one `NSScreen` at capture time.
///
/// All fields are value types and `Sendable`. The `arrayIndex` records the
/// position within `NSScreen.screens` at capture time; callers must not
/// assume this index is stable across captures.
public struct ScreenRecord: Codable, Sendable, Equatable {
    /// Position within `NSScreen.screens` at capture time.
    public let arrayIndex: Int
    /// Localized display name from `NSScreen.localizedName`.
    public let localizedName: String
    /// `CGDirectDisplayID` extracted from `NSScreen.deviceDescription`.
    public let displayID: CGDirectDisplayID?
    /// Canonical UUID string from `CGDisplayCreateUUIDFromDisplayID`, or an
    /// explicit error/unavailable state.
    public let uuidResult: UUIDResult
    /// Absolute frame in points (`NSScreen.frame`).
    public let frame: CGRect
    /// Visible frame in points (`NSScreen.visibleFrame`), accounting for
    /// menu bar and Dock.
    public let visibleFrame: CGRect
    /// Backing scale factor (`NSScreen.backingScaleFactor`).
    public let backingScaleFactor: Double
    /// Whether this screen is `NSScreen.main` at capture time.
    public let isMainScreen: Bool

    public init(
        arrayIndex: Int,
        localizedName: String,
        displayID: CGDirectDisplayID?,
        uuidResult: UUIDResult,
        frame: CGRect,
        visibleFrame: CGRect,
        backingScaleFactor: Double,
        isMainScreen: Bool
    ) {
        self.arrayIndex = arrayIndex
        self.localizedName = localizedName
        self.displayID = displayID
        self.uuidResult = uuidResult
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.isMainScreen = isMainScreen
    }
}

/// Result of `CGDisplayCreateUUIDFromDisplayID` for one display.
///
/// Explicitly models both success and failure states rather than
/// hiding errors behind an optional.
public enum UUIDResult: Codable, Sendable, Equatable {
    /// A canonical UUID string was obtained.
    case available(String)
    /// `CGDisplayCreateUUIDFromDisplayID` returned nil.
    case unavailable
    /// The `NSScreenNumber` key was missing or had an unexpected type.
    case extractionError(String)
}
