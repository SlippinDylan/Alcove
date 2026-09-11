import Foundation

/// A stable value identity derived from a standardized local file URL.
public struct FileIdentity: Hashable, Sendable {
    public let path: String

    public init(url: URL) {
        path = url.standardizedFileURL.path
    }
}
