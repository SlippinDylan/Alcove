import Foundation

/// The metadata for one already-enumerated directory entry.
///
/// Construction deliberately accepts metadata as values; directory enumeration and resource-value
/// reads belong to infrastructure outside AlcoveCore.
public struct FileItem: Identifiable, Sendable, Hashable {
    public let id: FileIdentity
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isHidden: Bool
    public let contentModificationDate: Date?
    public let creationDate: Date?

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isHidden: Bool,
        contentModificationDate: Date? = nil,
        creationDate: Date? = nil
    ) {
        let standardizedURL = url.standardizedFileURL
        id = FileIdentity(url: standardizedURL)
        self.url = standardizedURL
        self.name = name
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.contentModificationDate = contentModificationDate
        self.creationDate = creationDate
    }
}
