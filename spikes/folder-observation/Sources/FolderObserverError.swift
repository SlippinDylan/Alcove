// FolderObserverError.swift — Phase 0.5A DispatchSource directory observer

import Foundation

enum FolderObserverError: Error, Equatable, Sendable, CustomStringConvertible {
    case openFailed(path: String, code: Int32)
    case metadataFailed(path: String, code: Int32)
    case notADirectory(String)
    case alreadyRunning
    case stopped
    case teardownNotRequested
    case teardownTimedOut
    case teardownWaitOnEventQueue
    case descriptorCloseFailed(Int32)

    var description: String {
        switch self {
        case .openFailed(let path, let code):
            return "Failed to open \(path): errno \(code)"
        case .metadataFailed(let path, let code):
            return "Failed to inspect \(path): errno \(code)"
        case .notADirectory(let path):
            return "Not a directory: \(path)"
        case .alreadyRunning:
            return "Observer is already running"
        case .stopped:
            return "Observer is stopped; create a new instance"
        case .teardownNotRequested:
            return "Stop must be requested before waiting for teardown"
        case .teardownTimedOut:
            return "Timed out waiting for observer teardown"
        case .teardownWaitOnEventQueue:
            return "Cannot wait for teardown on the observer event queue"
        case .descriptorCloseFailed(let code):
            return "Failed to close observer descriptor: errno \(code)"
        }
    }
}
