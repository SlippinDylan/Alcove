// FolderObservationRecord.swift — Phase 0.5A DispatchSource directory observer
// Typed observation record delivered by the folder observer.

import Dispatch
import Foundation

/// Represents a single observation event from the directory observer.
///
/// DispatchSource directory notifications report directory-level changes,
/// not which specific child was affected. The event mask may contain
/// multiple flags when the kernel coalesces rapid operations.
struct FolderObservationRecord: Sendable {
    /// The raw event flags received from DispatchSource, stored as UInt
    /// because `DispatchSource.FileSystemEvent` is not `Sendable`.
    let rawEventMask: UInt

    /// Monotonic timestamp (in seconds) when the event was delivered.
    let timestamp: Double

    /// The generation at which this record was captured.
    /// Records from a previous generation are stale and must be discarded.
    let generation: UInt64

    /// Human-readable description of the observed flags.
    var eventDescription: String {
        var parts: [String] = []
        if rawEventMask & DispatchSource.FileSystemEvent.write.rawValue != 0 {
            parts.append("write")
        }
        if rawEventMask & DispatchSource.FileSystemEvent.rename.rawValue != 0 {
            parts.append("rename")
        }
        if rawEventMask & DispatchSource.FileSystemEvent.delete.rawValue != 0 {
            parts.append("delete")
        }
        if rawEventMask & DispatchSource.FileSystemEvent.revoke.rawValue != 0 {
            parts.append("revoke")
        }
        if parts.isEmpty {
            parts.append("unknown(0x\(String(rawEventMask, radix: 16)))")
        }
        return parts.joined(separator: "|")
    }
}
