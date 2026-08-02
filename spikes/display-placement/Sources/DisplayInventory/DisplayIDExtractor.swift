// DisplayIDExtractor.swift
// Alcove Spike 0.2B — Testable CGDirectDisplayID extraction from NSScreen.
//
// Provides a pure function for extracting the display ID from a device
// description dictionary without force casts.
// Disposable spike code, not production AlcoveCore.

import AppKit
import CoreGraphics
import Foundation

/// Extracts `CGDirectDisplayID` from an `NSScreen` device description
/// dictionary without force casts.
///
/// The device description stores the display ID as `NSNumber` under the
/// `NSDeviceDescriptionKey("NSScreenNumber")` key. This function checks
/// both key presence and numeric type before conversion.
///
/// - Parameter deviceDescription: The screen's `deviceDescription`.
/// - Returns: The display ID, or an explicit error.
public func extractDisplayID(
    from deviceDescription: [NSDeviceDescriptionKey: Any]
) -> Result<CGDirectDisplayID, InventoryError> {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let value = deviceDescription[key] else {
        return .failure(.missingDisplayID)
    }
    guard let number = value as? NSNumber else {
        return .failure(.nonNumericDisplayID)
    }
    guard CFGetTypeID(number) == CFNumberGetTypeID() else {
        return .failure(.nonNumericDisplayID)
    }
    let numericValue = number.doubleValue
    guard numericValue.isFinite,
          numericValue.rounded(FloatingPointRoundingRule.towardZero) == numericValue,
          numericValue >= 0,
          numericValue <= Double(UInt32.max) else {
        return .failure(.invalidDisplayIDValue)
    }
    return .success(CGDirectDisplayID(UInt32(numericValue)))
}
