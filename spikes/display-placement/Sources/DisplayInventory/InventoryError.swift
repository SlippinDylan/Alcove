// InventoryError.swift
// Alcove Spike 0.2B — Explicit error type for display inventory operations.
//
// Disposable spike code, not production AlcoveCore.

import Foundation

/// Errors produced by display inventory capture and encoding.
public enum InventoryError: Error, Sendable, Equatable {
    /// `NSScreenNumber` key is missing from the device description.
    case missingDisplayID
    /// `NSScreenNumber` value is not a numeric type.
    case nonNumericDisplayID
    /// `NSScreenNumber` cannot be represented exactly as `UInt32`.
    case invalidDisplayIDValue
    /// JSON encoding failed.
    case encodingFailed(String)
}
