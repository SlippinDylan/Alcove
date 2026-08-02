// UUIDFormatter.swift
// Alcove Spike 0.2B — UUID string formatting helper.
//
// Converts `CFUUID` from `CGDisplayCreateUUIDFromDisplayID` to a canonical
// UUID string without force casts.
// Disposable spike code, not production AlcoveCore.

import ColorSync
import CoreGraphics
import Foundation

/// Formats a `CFUUID` into a canonical UUID string (lowercase,
/// 8-4-4-4-12 format).
///
/// Uses `CFUUIDGetUUIDBytes` and manual hex formatting to avoid
/// forced Objective-C bridging while producing a deterministic,
/// standard UUID string.
///
/// - Parameter cfUUID: The `CFUUID` from `CGDisplayCreateUUIDFromDisplayID`.
/// - Returns: A canonical UUID string.
public func formatCFUUID(_ cfUUID: CFUUID) -> String {
    let bytes = CFUUIDGetUUIDBytes(cfUUID)
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

/// Looks up the canonical UUID for a display ID.
///
/// Calls `CGDisplayCreateUUIDFromDisplayID` and formats the result.
/// Returns `.unavailable` if the function returns nil (invalid or
/// virtual display).
///
/// - Parameter displayID: The `CGDirectDisplayID`.
/// - Returns: A `UUIDResult` with the formatted string or unavailable state.
public func lookupDisplayUUID(_ displayID: CGDirectDisplayID) -> UUIDResult {
    guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) else {
        return .unavailable
    }
    // `Create` in the function name means the caller owns the returned
    // reference (CF naming convention). `takeRetainedValue()` transfers
    // ownership without a force cast.
    let cfUUID = unmanaged.takeRetainedValue()
    return .available(formatCFUUID(cfUUID))
}
