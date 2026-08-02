// FSEventRecord.swift — Phase 0.5B FSEvents directory observer
// Typed observation record delivered by the FSEvents folder observer.

import CoreServices
import Foundation

/// Represents a single filesystem event from the FSEvents stream.
///
/// FSEvents may coalesce rapid operations and may deliver multiple path
/// records in a single callback. The flags describe evidence about the
/// path, not a guaranteed single operation. A consumer must treat each
/// record as invalidation evidence and re-enumerate rather than infer
/// a specific child operation from the flags alone.
struct FSEventRecord: Sendable {
    /// The filesystem path that this event record reports on.
    let path: String

    /// The FSEvents event ID for this record.
    let eventID: FSEventStreamEventId

    /// The raw event flags from the FSEvents stream.
    let rawFlags: FSEventStreamEventFlags

    /// Human-readable names of the decoded known flags.
    let decodedFlags: [String]

    /// Monotonic timestamp (in seconds) when the record was delivered.
    let timestamp: Double

    /// The registration identity (UUID) of the observer that produced this record.
    let registrationIdentity: UUID

    /// The monotonic generation counter for this registration.
    let generation: UInt64

    /// Identifies the single C callback batch that delivered this record.
    let callbackBatchIdentity: UUID

    /// Comma-separated decoded flag names for display.
    var flagDescription: String {
        decodedFlags.joined(separator: ", ")
    }
}

/// Decodes raw FSEventStreamEventFlags into human-readable flag names.
///
/// Only flags relevant to directory-child observation and root monitoring
/// are decoded. Unknown bits are reported as hex.
func decodeFSEventFlags(_ flags: FSEventStreamEventFlags) -> [String] {
    var names: [String] = []

    if flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
        names.append("MustScanSubDirs")
    }
    if flags & UInt32(kFSEventStreamEventFlagUserDropped) != 0 {
        names.append("UserDropped")
    }
    if flags & UInt32(kFSEventStreamEventFlagKernelDropped) != 0 {
        names.append("KernelDropped")
    }
    if flags & UInt32(kFSEventStreamEventFlagEventIdsWrapped) != 0 {
        names.append("EventIdsWrapped")
    }
    if flags & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 {
        names.append("HistoryDone")
    }
    if flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
        names.append("RootChanged")
    }
    if flags & UInt32(kFSEventStreamEventFlagMount) != 0 {
        names.append("Mount")
    }
    if flags & UInt32(kFSEventStreamEventFlagUnmount) != 0 {
        names.append("Unmount")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
        names.append("ItemCreated")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
        names.append("ItemRemoved")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0 {
        names.append("ItemInodeMetaMod")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
        names.append("ItemRenamed")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
        names.append("ItemModified")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemFinderInfoMod) != 0 {
        names.append("ItemFinderInfoMod")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemChangeOwner) != 0 {
        names.append("ItemChangeOwner")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemXattrMod) != 0 {
        names.append("ItemXattrMod")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 {
        names.append("ItemIsFile")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 {
        names.append("ItemIsDir")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemIsSymlink) != 0 {
        names.append("ItemIsSymlink")
    }

    // Report any remaining unknown bits as hex.
    let knownMask: UInt32 =
        UInt32(kFSEventStreamEventFlagMustScanSubDirs)
        | UInt32(kFSEventStreamEventFlagUserDropped)
        | UInt32(kFSEventStreamEventFlagKernelDropped)
        | UInt32(kFSEventStreamEventFlagEventIdsWrapped)
        | UInt32(kFSEventStreamEventFlagHistoryDone)
        | UInt32(kFSEventStreamEventFlagRootChanged)
        | UInt32(kFSEventStreamEventFlagMount)
        | UInt32(kFSEventStreamEventFlagUnmount)
        | UInt32(kFSEventStreamEventFlagItemCreated)
        | UInt32(kFSEventStreamEventFlagItemRemoved)
        | UInt32(kFSEventStreamEventFlagItemInodeMetaMod)
        | UInt32(kFSEventStreamEventFlagItemRenamed)
        | UInt32(kFSEventStreamEventFlagItemModified)
        | UInt32(kFSEventStreamEventFlagItemFinderInfoMod)
        | UInt32(kFSEventStreamEventFlagItemChangeOwner)
        | UInt32(kFSEventStreamEventFlagItemXattrMod)
        | UInt32(kFSEventStreamEventFlagItemIsFile)
        | UInt32(kFSEventStreamEventFlagItemIsDir)
        | UInt32(kFSEventStreamEventFlagItemIsSymlink)

    let unknownBits = flags & ~knownMask
    if unknownBits != 0 {
        names.append("unknown(0x\(String(unknownBits, radix: 16)))")
    }
    if names.isEmpty {
        names.append("none")
    }
    return names
}
