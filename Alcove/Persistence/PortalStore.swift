import AlcoveCore
import Foundation

protocol PortalStoring: Sendable {
    func load() async throws -> [Portal]
    func save(_ portals: [Portal]) async throws
}

protocol LegacyDisplayResolving: Sendable {
    func resolveDisplay(forLegacyFrame frame: CGRect) throws -> DisplayDescriptor
}

struct UnavailableLegacyDisplayResolver: LegacyDisplayResolving {
    func resolveDisplay(forLegacyFrame frame: CGRect) throws -> DisplayDescriptor {
        throw LegacyDisplayResolutionError.unavailable
    }
}

enum LegacyDisplayResolutionError: Error, Equatable {
    case unavailable
}

actor PortalStore: PortalStoring {
    static let defaultURL = URL.applicationSupportDirectory
        .appendingPathComponent("Alcove", isDirectory: true)
        .appendingPathComponent("portals.json", isDirectory: false)

    private let url: URL
    private let fileSystem: any PortalStoreFileSystem
    private let legacyDisplayResolver: any LegacyDisplayResolving

    init(
        url: URL = PortalStore.defaultURL,
        fileSystem: any PortalStoreFileSystem = FoundationPortalStoreFileSystem(),
        legacyDisplayResolver: any LegacyDisplayResolving = UnavailableLegacyDisplayResolver()
    ) {
        self.url = url
        self.fileSystem = fileSystem
        self.legacyDisplayResolver = legacyDisplayResolver
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

        let version: Int
        do {
            version = try JSONDecoder().decode(PortalEnvelopeVersionDTO.self, from: data).version
        } catch let error as NSError {
            throw PortalStoreError.corruptedFile(
                url: url,
                metadata: PortalStoreErrorMetadata(error)
            )
        }
        switch version {
        case 1:
            try preserveLegacyBackup(data, version: 1)
            let portals = try migrateLegacyPortals(try loadV1(from: data))
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV2DTO.currentVersion:
            try preserveLegacyBackup(data, version: 2)
            let portals = try migrateLegacyPortals(try loadV2(from: data))
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV3DTO.currentVersion:
            try preserveLegacyBackup(data, version: 3)
            let portals = try migrateLegacyPortals(try loadV3(from: data))
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV4DTO.currentVersion:
            try preserveLegacyBackup(data, version: 4)
            let portals = try migrateLegacyPortals(try loadV4(from: data))
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV5DTO.currentVersion:
            try preserveLegacyBackup(data, version: 5)
            let portals = try migrateLegacyPortals(try loadV5(from: data))
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV6DTO.currentVersion:
            try preserveLegacyBackup(data, version: 6)
            let portals = try migrateLegacyPortals(try loadV6(from: data))
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV7DTO.currentVersion:
            try preserveLegacyBackup(data, version: 7)
            let portals = try migrateLegacyPortals(try loadV7(from: data))
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV8DTO.currentVersion:
            try preserveLegacyBackup(data, version: 8)
            let portals = try migrateLegacyPortals(try loadV8(from: data))
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV9DTO.currentVersion:
            try preserveLegacyBackup(data, version: 9)
            let portals = try migrateLegacyPortals(try loadV9(from: data))
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV10DTO.currentVersion:
            try preserveLegacyBackup(data, version: 10)
            let portals = try loadV10(from: data)
            try writeCurrentVersion(portals)
            return portals
        case PortalEnvelopeV11DTO.currentVersion:
            return try loadV11(from: data)
        default:
            throw PortalStoreError.unsupportedVersion(version)
        }
    }

    private func loadV2(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV2DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV7(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV7DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV8(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV8DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV9(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV9DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV10(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV10DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV11(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV11DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV3(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV3DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV4(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV4DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV5(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV5DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV6(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV6DTO = try decodeEnvelope(from: data)
        return try mapPortals(envelope.portals) { try $0.domainValue() }
    }

    private func loadV1(from data: Data) throws -> [Portal] {
        let envelope: PortalEnvelopeV1DTO = try decodeEnvelope(from: data)
        var portals: [Portal] = []
        var portalIDs = Set<PortalID>()
        portals.reserveCapacity(envelope.portals.count)
        for (index, dto) in envelope.portals.enumerated() {
            do {
                let frame = try dto.frame.domainValue(label: "frame")
                let display: DisplayDescriptor
                do {
                    display = try legacyDisplayResolver.resolveDisplay(
                        forLegacyFrame: frame
                    )
                } catch {
                    throw PortalStoreError.legacyDisplayResolutionFailed(
                        index: index,
                        reason: String(describing: error)
                    )
                }
                let portal = try dto.domainValue(display: display)
                try insert(portal, at: index, into: &portals, ids: &portalIDs)
            } catch let error as PortalStoreError {
                throw error
            } catch {
                throw invalidPortalError(index: index, error: error)
            }
        }
        return portals
    }

    private func decodeEnvelope<Envelope: Decodable>(from data: Data) throws -> Envelope {
        do {
            return try JSONDecoder().decode(Envelope.self, from: data)
        } catch let error as NSError {
            throw PortalStoreError.corruptedFile(
                url: url,
                metadata: PortalStoreErrorMetadata(error)
            )
        }
    }

    private func mapPortals<DTO>(
        _ dtos: [DTO],
        mapping: (DTO) throws -> Portal
    ) throws -> [Portal] {
        var portals: [Portal] = []
        var portalIDs = Set<PortalID>()
        portals.reserveCapacity(dtos.count)
        for (index, dto) in dtos.enumerated() {
            do {
                let portal = try mapping(dto)
                try insert(portal, at: index, into: &portals, ids: &portalIDs)
            } catch let error as PortalStoreError {
                throw error
            } catch {
                throw invalidPortalError(index: index, error: error)
            }
        }
        return portals
    }

    private func insert(
        _ portal: Portal,
        at index: Int,
        into portals: inout [Portal],
        ids: inout Set<PortalID>
    ) throws {
        guard ids.insert(portal.id).inserted else {
            throw PortalStoreError.duplicatePortalID(
                index: index,
                id: portal.id.rawValue
            )
        }
        portals.append(portal)
    }

    private func migrateLegacyPortals(_ portals: [Portal]) throws -> [Portal] {
        return try portals.enumerated().map { index, portal in
            do {
                let metrics = GridMetrics(
                    iconSize: portal.iconSize,
                    labelFontSize: portal.textSize
                )
                let gridSize = metrics.contentSize(for: portal.gridCapacity)
                let targetSize = CGSize(
                    width: gridSize.width,
                    height: gridSize.height + PortalLayoutMetrics.chromeHeight
                )
                return try adjustingPortalGeometry(
                    portal,
                    adjustingWidthBy: targetSize.width - portal.frame.width,
                    adjustingHeightBy: targetSize.height - portal.frame.height,
                    isPinned: portal.isPinned
                )
            } catch {
                throw invalidPortalError(index: index, error: error)
            }
        }
    }

    private func adjustingPortalGeometry(
        _ portal: Portal,
        adjustingWidthBy widthDelta: CGFloat,
        adjustingHeightBy heightDelta: CGFloat,
        isPinned: Bool
    ) throws -> Portal {
        let framesByDisplay = try Dictionary(
            uniqueKeysWithValues: portal.placement.framesByDisplay.map { display, entry in
                let visibleFrame = entry.referenceVisibleFrame
                let frame = try PlacementGeometry.restore(
                    record: entry,
                    currentVisibleFrame: visibleFrame
                )
                let width = min(
                    visibleFrame.width,
                    max(1, frame.width + widthDelta)
                )
                let height = min(
                    visibleFrame.height,
                    max(1, frame.height + heightDelta)
                )
                let origin = CGPoint(
                    x: min(
                        max(frame.maxX - width, visibleFrame.minX),
                        visibleFrame.maxX - width
                    ),
                    y: min(
                        max(frame.maxY - height, visibleFrame.minY),
                        visibleFrame.maxY - height
                    )
                )
                let adjustedFrame = CGRect(
                    origin: origin,
                    size: CGSize(width: width, height: height)
                )
                return (
                    display,
                    try PlacementGeometry.capture(
                        windowFrame: adjustedFrame,
                        visibleFrame: visibleFrame
                    )
                )
            }
        )
        return try Portal(
            id: portal.id,
            tabs: portal.tabs,
            selectedTabID: portal.selectedTabID,
            placement: PlacementRecord(
                framesByDisplay: framesByDisplay,
                homeDisplay: portal.placement.homeDisplay
            ),
            iconLayout: portal.iconLayout,
            backgroundStyle: portal.backgroundStyle,
            gridCapacity: portal.gridCapacity,
            isPinned: isPinned,
            sortOrder: portal.sortOrder,
            tint: portal.tint
        )
    }

    private func invalidPortalError(index: Int, error: Error) -> PortalStoreError {
        PortalStoreError.invalidPortal(
            index: index,
            reason: String(describing: error)
        )
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

        try writeCurrentVersion(portals)
    }

    private func writeCurrentVersion(_ portals: [Portal]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(PortalEnvelopeV11DTO(portals: portals))
        data.append(0x0a)
        try writeAtomically(data, to: url)
    }

    private func preserveLegacyBackup(_ data: Data, version: Int) throws {
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("portals.v\(version).json.bak")
        if fileSystem.fileExists(at: backupURL) {
            let existing: Data
            do {
                existing = try fileSystem.readData(at: backupURL)
            } catch let error as NSError {
                throw PortalStoreError.readFailed(
                    url: backupURL,
                    metadata: PortalStoreErrorMetadata(error)
                )
            }
            guard existing == data else {
                throw PortalStoreError.migrationBackupConflict(url: backupURL)
            }
            return
        }
        try writeAtomically(data, to: backupURL)
    }

    private func writeAtomically(_ data: Data, to destinationURL: URL) throws {
        let directory = destinationURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".portals-\(UUID().uuidString).tmp"
        )

        do {
            try fileSystem.createDirectory(at: directory)
            try fileSystem.writeData(data, to: temporaryURL)
            if fileSystem.fileExists(at: destinationURL) {
                try fileSystem.replaceItem(at: destinationURL, with: temporaryURL)
            } else {
                try fileSystem.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch let writeError as NSError {
            guard fileSystem.fileExists(at: temporaryURL) else {
                throw PortalStoreError.writeFailed(
                    url: destinationURL,
                    metadata: PortalStoreErrorMetadata(writeError)
                )
            }
            do {
                try fileSystem.removeItem(at: temporaryURL)
            } catch let cleanupError as NSError {
                throw PortalStoreError.writeAndCleanupFailed(
                    url: destinationURL,
                    write: PortalStoreErrorMetadata(writeError),
                    cleanup: PortalStoreErrorMetadata(cleanupError)
                )
            }
            throw PortalStoreError.writeFailed(
                url: destinationURL,
                metadata: PortalStoreErrorMetadata(writeError)
            )
        }
    }
}
