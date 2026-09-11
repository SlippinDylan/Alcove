import AlcoveCore
import Foundation

struct PortalEnvelopeDTO: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let portals: [PortalDTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalDTO.init)
    }
}

struct PortalDTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID
    let frame: FrameDTO
    let iconSize: Double

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case frame
        case iconSize = "icon_size"
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = portal.selectedTabID.rawValue
        frame = FrameDTO(portal.frame)
        iconSize = Double(portal.iconSize.rawValue)
    }

    func domainValue() throws -> Portal {
        guard let iconSize = IconSize(rawValue: CGFloat(iconSize)) else {
            throw PortalStoreMappingError.invalidIconSize(self.iconSize)
        }
        return try Portal(
            id: PortalID(rawValue: id),
            tabs: tabs.map { $0.domainValue() },
            selectedTabID: FolderTabID(rawValue: selectedTabID),
            frame: frame.cgRect,
            iconSize: iconSize
        )
    }
}

struct FolderTabDTO: Codable, Equatable {
    let id: UUID
    let folderPath: String

    enum CodingKeys: String, CodingKey {
        case id
        case folderPath = "folder_path"
    }

    init(_ tab: FolderTab) {
        id = tab.id.rawValue
        folderPath = tab.folderURL.path
    }

    func domainValue() -> FolderTab {
        FolderTab(
            id: FolderTabID(rawValue: id),
            folderURL: URL(fileURLWithPath: folderPath)
        )
    }
}

struct FrameDTO: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ frame: CGRect) {
        x = Double(frame.origin.x)
        y = Double(frame.origin.y)
        width = Double(frame.width)
        height = Double(frame.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum PortalStoreMappingError: Error, Equatable {
    case invalidIconSize(Double)
}

struct PortalStoreErrorMetadata: Equatable, Sendable {
    let domain: String
    let code: Int

    init(_ error: NSError) {
        domain = error.domain
        code = error.code
    }
}

enum PortalStoreError: Error, Equatable, Sendable {
    case readFailed(url: URL, metadata: PortalStoreErrorMetadata)
    case corruptedFile(url: URL, metadata: PortalStoreErrorMetadata)
    case unsupportedVersion(Int)
    case invalidPortal(index: Int, reason: String)
    case writeFailed(url: URL, metadata: PortalStoreErrorMetadata)
    case writeAndCleanupFailed(
        url: URL,
        write: PortalStoreErrorMetadata,
        cleanup: PortalStoreErrorMetadata
    )
}
