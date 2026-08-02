// FSEventError.swift — Phase 0.5B FSEvents directory observer
// Typed errors for the FSEvents folder observer.

import Foundation

/// Errors produced by the FSEvents folder observer setup and teardown.
enum FSEventError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The path does not exist (stat returned ENOENT).
    case pathNotFound(path: String, code: Int32)
    /// Failed to stat the path.
    case metadataFailed(path: String, code: Int32)
    /// Failed to open the path for validation.
    case openFailed(path: String, code: Int32)
    /// Failed to close the temporary validation descriptor.
    case validationDescriptorCloseFailed(Int32)
    /// The path exists but is not a directory.
    case notADirectory(path: String)
    /// `FSEventStreamCreate` returned nil.
    case streamCreationFailed(path: String)
    /// `FSEventStreamStart` returned false.
    case streamStartFailed
    /// The observer is already running; stop before restarting.
    case alreadyRunning
    /// The observer has been stopped and cannot be restarted.
    case stopped
    /// Must call stop before waiting for teardown.
    case teardownNotRequested
    /// The teardown wait timed out.
    case teardownTimedOut
    /// Cannot wait for teardown on the lifecycle queue (would deadlock).
    case teardownWaitOnLifecycleQueue

    var description: String {
        switch self {
        case .pathNotFound(let path, let code):
            return "Path not found: \(path) (errno \(code))"
        case .metadataFailed(let path, let code):
            return "Failed to inspect \(path): errno \(code)"
        case .openFailed(let path, let code):
            return "Failed to open \(path) for validation: errno \(code)"
        case .validationDescriptorCloseFailed(let code):
            return "Failed to close validation descriptor: errno \(code)"
        case .notADirectory(let path):
            return "Not a directory: \(path)"
        case .streamCreationFailed(let path):
            return "FSEventStreamCreate returned nil for \(path)"
        case .streamStartFailed:
            return "FSEventStreamStart returned false"
        case .alreadyRunning:
            return "Observer is already running"
        case .stopped:
            return "Observer is stopped; create a new instance"
        case .teardownNotRequested:
            return "Stop must be requested before waiting for teardown"
        case .teardownTimedOut:
            return "Timed out waiting for observer teardown"
        case .teardownWaitOnLifecycleQueue:
            return "Cannot wait for teardown on the lifecycle queue"
        }
    }
}
