// DirectoryEnumerator.swift — Phase 0.5C1 background directory enumeration
// Synchronous immediate-child enumeration using FileManager.

import Foundation

/// Abstraction over `FileManager.contentsOfDirectory` for injection seams.
///
/// Production-like paths use real `FileManager` evidence; test seams may inject
/// controlled behavior (e.g. a slow enumerator for cancellation testing).
struct DirectoryEnumerator: Sendable {
    /// The underlying listing closure.
    let listImmediateChildren: @Sendable (URL) throws -> [URL]

    /// Default enumerator backed by `FileManager.default.contentsOfDirectory`.
    static func defaultManager() -> DirectoryEnumerator {
        DirectoryEnumerator { url in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .isHiddenKey],
                options: [.skipsSubdirectoryDescendants]
            )
        }
    }

    func children(at url: URL) throws -> [URL] {
        do {
            return try listImmediateChildren(url)
        } catch let error as EnumerationError {
            throw error
        } catch let error as NSError {
            throw EnumerationError.enumerationFailed(
                path: url.path,
                domain: error.domain,
                code: error.code,
                description: error.localizedDescription
            )
        }
    }

    /// Validates the target path before enumeration.
    ///
    /// Checks that the path exists and is a directory, mapping failures to
    /// typed errors with POSIX evidence.
    static func validatePath(_ path: String) throws {
        let descriptor = Darwin.open(path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            let capturedError = errno
            if capturedError == ENOENT || capturedError == ENOTDIR {
                throw EnumerationError.missingPath(path: path, code: capturedError)
            }
            throw EnumerationError.pathOpenFailed(path: path, code: capturedError)
        }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            let capturedError = errno
            guard Darwin.close(descriptor) == 0 else {
                throw EnumerationError.validationAndCloseFailed(
                    path: path,
                    metadataCode: capturedError,
                    closeCode: errno
                )
            }
            throw EnumerationError.pathMetadataFailed(path: path, code: capturedError)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFDIR else {
            guard Darwin.close(descriptor) == 0 else {
                throw EnumerationError.validationCloseFailed(path: path, code: errno)
            }
            throw EnumerationError.notADirectory(path: path, code: ENOTDIR)
        }
        guard Darwin.close(descriptor) == 0 else {
            throw EnumerationError.validationCloseFailed(path: path, code: errno)
        }
    }
}
