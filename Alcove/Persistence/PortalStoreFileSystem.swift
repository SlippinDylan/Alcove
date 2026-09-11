import Foundation

protocol PortalStoreFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func readData(at url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func replaceItem(at destinationURL: URL, with sourceURL: URL) throws
    func removeItem(at url: URL) throws
}

struct FoundationPortalStoreFileSystem: PortalStoreFileSystem {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func replaceItem(at destinationURL: URL, with sourceURL: URL) throws {
        _ = try FileManager.default.replaceItemAt(
            destinationURL,
            withItemAt: sourceURL,
            backupItemName: nil,
            options: []
        )
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
