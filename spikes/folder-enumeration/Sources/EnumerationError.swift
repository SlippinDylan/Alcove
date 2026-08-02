// EnumerationError.swift — Phase 0.5C1 background directory enumeration

import Foundation

/// Typed errors for directory enumeration with path and POSIX evidence where available.
enum EnumerationError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The target path does not exist. Retains the POSIX errno.
    case missingPath(path: String, code: Int32)

    /// The target exists but is not a directory. Retains the POSIX errno when available.
    case notADirectory(path: String, code: Int32)
    case pathOpenFailed(path: String, code: Int32)
    case pathMetadataFailed(path: String, code: Int32)
    case validationCloseFailed(path: String, code: Int32)
    case validationAndCloseFailed(path: String, metadataCode: Int32, closeCode: Int32)

    /// `FileManager.contentsOfDirectory` failed. Retains the Cocoa domain and code
    /// for downstream mapping (e.g. permission denied / TCC).
    case enumerationFailed(path: String, domain: String, code: Int, description: String)

    /// Per-item metadata (`resourceValues`) could not be read. The failed item is
    /// omitted while accessible siblings remain in the snapshot.
    case itemMetadataFailed(path: String, domain: String, code: Int, description: String)

    /// The request was cancelled before the result could be accepted.
    case cancelled
    case workerTimedOut
    case workerBoundaryViolation
    case generationExhausted

    var description: String {
        switch self {
        case .missingPath(let path, let code):
            return "Missing path: \(path) (errno \(code))"
        case .notADirectory(let path, let code):
            return "Not a directory: \(path) (errno \(code))"
        case .pathOpenFailed(let path, let code):
            return "Failed to open \(path): errno \(code)"
        case .pathMetadataFailed(let path, let code):
            return "Failed to inspect \(path): errno \(code)"
        case .validationCloseFailed(let path, let code):
            return "Failed to close validation descriptor for \(path): errno \(code)"
        case .validationAndCloseFailed(let path, let metadataCode, let closeCode):
            return "Failed to inspect \(path) (errno \(metadataCode)) and close its validation descriptor (errno \(closeCode))"
        case .enumerationFailed(let path, let domain, let code, let description):
            return "Enumeration failed for \(path): [\(domain) \(code)] \(description)"
        case .itemMetadataFailed(let path, let domain, let code, let description):
            return "Item metadata failed for \(path): [\(domain) \(code)] \(description)"
        case .cancelled:
            return "Enumeration request was cancelled"
        case .workerTimedOut:
            return "Timed out waiting for background enumeration"
        case .workerBoundaryViolation:
            return "Enumeration did not run on the configured background queue"
        case .generationExhausted:
            return "Enumeration generation counter is exhausted"
        }
    }
}
