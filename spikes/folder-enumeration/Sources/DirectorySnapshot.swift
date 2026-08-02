// DirectorySnapshot.swift — Phase 0.5C1 background directory enumeration
// Typed immutable snapshot of a directory's immediate children.

import Foundation

/// An immutable, deterministically sorted snapshot of one directory's immediate children.
///
/// Sort order: directories first, then locale-independent lexical name. This does not
/// claim Finder sort equivalence; it is stable across enumerations of the same
/// directory contents.
struct DirectorySnapshot: Sendable, Equatable, CustomStringConvertible {
    /// The directory path that was enumerated.
    let path: String

    /// The generation at which this snapshot was captured.
    let generation: UInt64

    /// Deterministically sorted immediate children (directories first, then
    /// locale-independent lexical name). No grandchildren appear here.
    let entries: [ChildEntry]

    /// Per-item metadata errors collected during enumeration. Accessible items
    /// are still listed; only unreadable entries appear here.
    let metadataErrors: [EnumerationError]

    /// Total number of immediate children in the snapshot.
    var count: Int { entries.count }

    /// Whether the directory contained no immediate children.
    var isEmpty: Bool { entries.isEmpty }

    var description: String {
        "DirectorySnapshot(\(path), gen=\(generation), \(count) entries, \(metadataErrors.count) errors)"
    }

    /// Builds a snapshot by enumerating `path` with the supplied enumerator.
    ///
    /// Items that throw during `ChildEntry.init` are collected as metadata errors
    /// rather than silently dropped. The final list is sorted deterministically.
    static func enumerate(
        path: String,
        generation: UInt64,
        enumerator: DirectoryEnumerator
    ) throws -> DirectorySnapshot {
        let pathURL = URL(fileURLWithPath: path)
        let childURLs = try enumerator.children(at: pathURL)

        var entries: [ChildEntry] = []
        var errors: [EnumerationError] = []

        for url in childURLs {
            do {
                let entry = try ChildEntry(url: url)
                entries.append(entry)
            } catch let error as NSError {
                errors.append(.itemMetadataFailed(
                    path: url.path,
                    domain: error.domain,
                    code: error.code,
                    description: error.localizedDescription
                ))
            }
        }

        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs.url.path < rhs.url.path
        }

        return DirectorySnapshot(
            path: path,
            generation: generation,
            entries: entries,
            metadataErrors: errors
        )
    }
}
