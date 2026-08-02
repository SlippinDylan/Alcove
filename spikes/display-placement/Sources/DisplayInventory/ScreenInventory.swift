// ScreenInventory.swift
// Alcove Spike 0.2B — AppKit-backed display inventory capture.
//
// Captures a snapshot of `NSScreen.screens` and encodes it as deterministic
// JSON. All `NSScreen` access occurs on `MainActor`.
// Disposable spike code, not production AlcoveCore.

import AppKit
import CoreGraphics
import Foundation

/// Captures display inventory from `NSScreen.screens`.
///
/// All methods access `NSScreen` state and must be called on `MainActor`.
@MainActor
public enum ScreenInventory {

    /// Capture a one-time snapshot of all connected screens.
    ///
    /// Each `ScreenRecord` contains the screen's array index, localized name,
    /// display ID, UUID result, frame, visible frame, scale factor, and
    /// whether it is the current main screen.
    ///
    /// Array index is recorded for comparison across snapshots; callers must
    /// not assume ordering is stable.
    public static func capture() -> [ScreenRecord] {
        let screens = NSScreen.screens
        let mainScreen = NSScreen.main
        var records: [ScreenRecord] = []
        records.reserveCapacity(screens.count)

        for (index, screen) in screens.enumerated() {
            let deviceDesc = screen.deviceDescription
            let displayIDResult = extractDisplayID(from: deviceDesc)

            let displayID: CGDirectDisplayID?
            let uuidResult: UUIDResult

            switch displayIDResult {
            case .success(let id):
                displayID = id
                uuidResult = lookupDisplayUUID(id)
            case .failure(let error):
                displayID = nil
                uuidResult = .extractionError(String(describing: error))
            }

            let record = ScreenRecord(
                arrayIndex: index,
                localizedName: screen.localizedName,
                displayID: displayID,
                uuidResult: uuidResult,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                backingScaleFactor: screen.backingScaleFactor,
                isMainScreen: screen == mainScreen
            )
            records.append(record)
        }

        return records
    }

    /// Encode screen records as deterministic, human-readable JSON.
    ///
    /// Uses `.sortedKeys` for stable key ordering and `.prettyPrinted`
    /// for human readability.
    public static func encodeJSON<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            return try encoder.encode(value)
        } catch {
            throw InventoryError.encodingFailed(error.localizedDescription)
        }
    }
}
