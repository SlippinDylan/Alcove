import AlcoveCore
import Foundation

protocol PortalStoring: Sendable {
    func load() async throws -> [Portal]
    func save(_ portals: [Portal]) async throws
}

actor PortalStore: PortalStoring {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Alcove/portals.json")

    private let url: URL
    private let fileSystem: any PortalStoreFileSystem

    init(
        url: URL = PortalStore.defaultURL,
        fileSystem: any PortalStoreFileSystem = FoundationPortalStoreFileSystem()
    ) {
        self.url = url
        self.fileSystem = fileSystem
    }

    func load() async throws -> [Portal] {
        guard fileSystem.fileExists(at: url) else { return [] }

        let data: Data
        do {
            data = try fileSystem.readData(at: url)
        } catch let error as NSError {
            throw PortalStoreError.readFailed(
                url: url,
                metadata: PortalStoreErrorMetadata(error)
            )
        }

        let envelope: PortalEnvelopeDTO
        do {
            envelope = try JSONDecoder().decode(PortalEnvelopeDTO.self, from: data)
        } catch let error as NSError {
            throw PortalStoreError.corruptedFile(
                url: url,
                metadata: PortalStoreErrorMetadata(error)
            )
        }
        guard envelope.version == PortalEnvelopeDTO.currentVersion else {
            throw PortalStoreError.unsupportedVersion(envelope.version)
        }

        var portals: [Portal] = []
        var portalIDs = Set<PortalID>()
        portals.reserveCapacity(envelope.portals.count)
        for (index, dto) in envelope.portals.enumerated() {
            do {
                let portal = try dto.domainValue()
                guard portalIDs.insert(portal.id).inserted else {
                    throw PortalStoreError.duplicatePortalID(
                        index: index,
                        id: portal.id.rawValue
                    )
                }
                portals.append(portal)
            } catch let error as PortalStoreError {
                throw error
            } catch {
                throw PortalStoreError.invalidPortal(
                    index: index,
                    reason: String(describing: error)
                )
            }
        }
        return portals
    }

    func save(_ portals: [Portal]) async throws {
        var portalIDs = Set<PortalID>()
        for (index, portal) in portals.enumerated() {
            guard portalIDs.insert(portal.id).inserted else {
                throw PortalStoreError.duplicatePortalID(
                    index: index,
                    id: portal.id.rawValue
                )
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(PortalEnvelopeDTO(portals: portals))
        data.append(0x0a)

        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".portals-\(UUID().uuidString).tmp"
        )

        do {
            try fileSystem.createDirectory(at: directory)
            try fileSystem.writeData(data, to: temporaryURL)
            if fileSystem.fileExists(at: url) {
                try fileSystem.replaceItem(at: url, with: temporaryURL)
            } else {
                try fileSystem.moveItem(at: temporaryURL, to: url)
            }
        } catch let writeError as NSError {
            guard fileSystem.fileExists(at: temporaryURL) else {
                throw PortalStoreError.writeFailed(
                    url: url,
                    metadata: PortalStoreErrorMetadata(writeError)
                )
            }
            do {
                try fileSystem.removeItem(at: temporaryURL)
            } catch let cleanupError as NSError {
                throw PortalStoreError.writeAndCleanupFailed(
                    url: url,
                    write: PortalStoreErrorMetadata(writeError),
                    cleanup: PortalStoreErrorMetadata(cleanupError)
                )
            }
            throw PortalStoreError.writeFailed(
                url: url,
                metadata: PortalStoreErrorMetadata(writeError)
            )
        }
    }
}
