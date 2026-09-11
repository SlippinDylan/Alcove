import CoreServices
import Foundation

struct ObservedRootIdentity: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
}

enum FSEventsRecoveryAction: String, Encodable, Equatable, Sendable {
    case refreshSnapshot
    case rebuildObservation
}

enum ObservedRootDecision: String, Equatable, Sendable {
    case restartAndEnumerate
    case folderMissing
    case folderReplaced
}

enum FSEventsRecoveryPolicy {
    private static let rebuildMask = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped
            | kFSEventStreamEventFlagRootChanged
    )

    static func action(for flags: FSEventStreamEventFlags) -> FSEventsRecoveryAction {
        flags & rebuildMask == 0 ? .refreshSnapshot : .rebuildObservation
    }

    static func rootDecision(
        expected: ObservedRootIdentity,
        current: ObservedRootIdentity?
    ) -> ObservedRootDecision {
        guard let current else { return .folderMissing }
        return current == expected ? .restartAndEnumerate : .folderReplaced
    }
}
