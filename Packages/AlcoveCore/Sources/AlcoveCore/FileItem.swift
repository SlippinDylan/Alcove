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
    public let isPackage: Bool
    public let isSymbolicLink: Bool
    public let isHidden: Bool
    public let contentModificationDate: Date?
    public let creationDate: Date?

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool = false,
        isSymbolicLink: Bool = false,
        isHidden: Bool,
        contentModificationDate: Date? = nil,
        creationDate: Date? = nil
    ) {
        let standardizedURL = url.standardizedFileURL
        id = FileIdentity(url: standardizedURL)
        self.url = standardizedURL
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
        self.isHidden = isHidden
        self.contentModificationDate = contentModificationDate
        self.creationDate = creationDate
    }

    public var isNavigableDirectory: Bool {
        isDirectory && !isPackage && !isSymbolicLink
    }
}
