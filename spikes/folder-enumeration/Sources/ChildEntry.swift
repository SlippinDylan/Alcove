// ChildEntry.swift — Phase 0.5C1 background directory enumeration
// Typed immutable immediate-child entry. No recursive traversal.

import Foundation

/// A single immediate child of an enumerated directory.
///
/// Identity is derived from the standardized file URL. Metadata is read from
/// `URLResourceValues` at construction time; failures throw rather than
/// silently dropping the entry.
struct ChildEntry: Identifiable, Sendable, Hashable, CustomStringConvertible {
    /// Stable identity derived from the standardized file URL.
    let id: String

    /// The file URL of this child.
    let url: URL

    /// Display name from `resourceValues(forKeys:)`.
    let name: String

    /// `true` when `isDirectoryKey` reports a directory.
    let isDirectory: Bool

    /// `true` when `isHiddenKey` reports a hidden file.
    let isHidden: Bool

    /// Builds an entry from the given URL by reading resource values.
    ///
    /// Throws when `resourceValues` cannot be read, preserving the underlying
    /// `NSError` domain and code for diagnostics.
    init(url: URL) throws {
        let resourceValues = try url.resourceValues(
            forKeys: [.nameKey, .isDirectoryKey, .isHiddenKey]
        )
        self.id = url.standardizedFileURL.path
        self.url = url
        self.name = resourceValues.name ?? url.lastPathComponent
        self.isDirectory = resourceValues.isDirectory ?? false
        self.isHidden = resourceValues.isHidden ?? false
    }

    var description: String {
        let kind = isDirectory ? "dir" : "file"
        let hidden = isHidden ? " [hidden]" : ""
        return "\(name) (\(kind)\(hidden))"
    }
}
