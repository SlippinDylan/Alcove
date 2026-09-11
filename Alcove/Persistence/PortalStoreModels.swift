import AlcoveCore
import Foundation

struct PortalEnvelopeVersionDTO: Decodable {
    let version: Int
}

struct PortalEnvelopeV2DTO: Codable, Equatable {
    static let currentVersion = 2

    let version: Int
    let portals: [PortalV2DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV2DTO.init)
    }
}

struct PortalV2DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID
    let placement: PlacementRecordDTO
    let iconSize: Double

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case iconSize = "icon_size"
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = portal.selectedTabID.rawValue
        placement = PlacementRecordDTO(portal.placement)
        iconSize = Double(portal.iconSize.rawValue)
    }

    func domainValue() throws -> Portal {
        guard let iconSize = IconSize(rawValue: CGFloat(iconSize)) else {
            throw PortalStoreMappingError.invalidIconSize(self.iconSize)
        }
        return try Portal(
            id: PortalID(rawValue: id),
            tabs: try tabs.map { try $0.domainValue() },
            selectedTabID: FolderTabID(rawValue: selectedTabID),
            placement: try placement.domainValue(),
            iconSize: iconSize
        )
    }
}

struct PortalEnvelopeV1DTO: Decodable {
    let version: Int
    let portals: [PortalV1DTO]
}

struct PortalV1DTO: Decodable {
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

    func domainValue(display: DisplayDescriptor) throws -> Portal {
        guard let iconSize = IconSize(rawValue: CGFloat(iconSize)) else {
            throw PortalStoreMappingError.invalidIconSize(self.iconSize)
        }
        return try Portal(
            id: PortalID(rawValue: id),
            tabs: try tabs.map { try $0.domainValue() },
            selectedTabID: FolderTabID(rawValue: selectedTabID),
            placement: PlacementRecord(
                frame: try frame.domainValue(label: "frame"),
                display: display
            ),
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

    func domainValue() throws -> FolderTab {
        guard folderPath.hasPrefix("/") else {
            throw PortalStoreMappingError.invalidFolderPath(folderPath)
        }
        return FolderTab(
            id: FolderTabID(rawValue: id),
            folderURL: URL(fileURLWithPath: folderPath)
        )
    }
}

struct PlacementRecordDTO: Codable, Equatable {
    let framesByDisplay: [String: DisplayPlacementEntryDTO]
    let homeDisplay: String

    enum CodingKeys: String, CodingKey {
        case framesByDisplay = "frames_by_display"
        case homeDisplay = "home_display"
    }

    init(_ placement: PlacementRecord) {
        framesByDisplay = Dictionary(
            uniqueKeysWithValues: placement.framesByDisplay.map { identity, entry in
                (identity.rawValue, DisplayPlacementEntryDTO(entry))
            }
        )
        homeDisplay = placement.homeDisplay.rawValue
    }

    func domainValue() throws -> PlacementRecord {
        let mappedHomeDisplay = try Self.displayIdentity(homeDisplay)
        var mapped: [DisplayIdentity: DisplayPlacementEntry] = [:]
        for (rawIdentity, entry) in framesByDisplay {
            let identity = try Self.displayIdentity(rawIdentity)
            guard mapped.updateValue(try entry.domainValue(), forKey: identity) == nil else {
                throw PortalStoreMappingError.duplicateDisplayIdentity(identity.rawValue)
            }
        }
        return try PlacementRecord(
            framesByDisplay: mapped,
            homeDisplay: mappedHomeDisplay
        )
    }

    private static func displayIdentity(_ rawValue: String) throws -> DisplayIdentity {
        guard let uuid = UUID(uuidString: rawValue) else {
            throw PortalStoreMappingError.invalidDisplayIdentity(rawValue)
        }
        return DisplayIdentity(rawValue: uuid.uuidString.lowercased())
    }
}

struct DisplayPlacementEntryDTO: Codable, Equatable {
    let absoluteFrame: FrameDTO
    let referenceVisibleFrame: FrameDTO
    let preferredSize: SizeDTO
    let normalizedAnchor: NormalizedAnchorDTO

    enum CodingKeys: String, CodingKey {
        case absoluteFrame = "absolute_frame"
        case referenceVisibleFrame = "reference_visible_frame"
        case preferredSize = "preferred_size"
        case normalizedAnchor = "normalized_anchor"
    }

    init(_ entry: DisplayPlacementEntry) {
        absoluteFrame = FrameDTO(entry.absoluteFrame)
        referenceVisibleFrame = FrameDTO(entry.referenceVisibleFrame)
        preferredSize = SizeDTO(entry.preferredSize)
        normalizedAnchor = NormalizedAnchorDTO(entry.normalizedAnchor)
    }

    func domainValue() throws -> DisplayPlacementEntry {
        DisplayPlacementEntry(
            absoluteFrame: try absoluteFrame.domainValue(label: "absolute_frame"),
            referenceVisibleFrame: try referenceVisibleFrame.domainValue(
                label: "reference_visible_frame"
            ),
            preferredSize: try preferredSize.domainValue(),
            normalizedAnchor: try normalizedAnchor.domainValue()
        )
    }
}

struct NormalizedAnchorDTO: Codable, Equatable {
    let x: Double
    let y: Double

    init(_ anchor: NormalizedAnchor) {
        x = anchor.x
        y = anchor.y
    }

    func domainValue() throws -> NormalizedAnchor {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw PortalStoreMappingError.invalidNormalizedAnchor(x: x, y: y)
        }
        return try NormalizedAnchor(x: x, y: y)
    }
}

struct SizeDTO: Codable, Equatable {
    let width: Double
    let height: Double

    init(_ size: CGSize) {
        width = Double(size.width)
        height = Double(size.height)
    }

    func domainValue() throws -> CGSize {
        guard width.isFinite, height.isFinite, width >= 0, height >= 0 else {
            throw PortalStoreMappingError.invalidSize(width: width, height: height)
        }
        return CGSize(width: width, height: height)
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

    func domainValue(label: String) throws -> CGRect {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0
        else {
            throw PortalStoreMappingError.invalidFrame(label)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

enum PortalStoreMappingError: Error, Equatable {
    case invalidIconSize(Double)
    case invalidFolderPath(String)
    case invalidDisplayIdentity(String)
    case duplicateDisplayIdentity(String)
    case invalidNormalizedAnchor(x: Double, y: Double)
    case invalidSize(width: Double, height: Double)
    case invalidFrame(String)
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
    case legacyDisplayResolutionFailed(index: Int, reason: String)
    case migrationBackupConflict(url: URL)
    case invalidPortal(index: Int, reason: String)
    case duplicatePortalID(index: Int, id: UUID)
    case writeFailed(url: URL, metadata: PortalStoreErrorMetadata)
    case writeAndCleanupFailed(
        url: URL,
        write: PortalStoreErrorMetadata,
        cleanup: PortalStoreErrorMetadata
    )
}
