import AlcoveCore
import Foundation

struct PortalEnvelopeV12DTO: Codable, Equatable {
    static let currentVersion = 12

    let version: Int
    let portals: [PortalV12DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV12DTO.init)
    }
}

struct PortalV12DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID?
    let placement: PlacementRecordDTO
    let columns: Int
    let rows: Int
    let isPinned: Bool
    let sortOrder: String
    let tint: String

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case columns
        case rows
        case isPinned = "is_pinned"
        case sortOrder = "sort_order"
        case tint
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = portal.selectedTabID?.rawValue
        placement = PlacementRecordDTO(portal.placement)
        columns = portal.gridCapacity.columns
        rows = portal.gridCapacity.rows
        isPinned = portal.isPinned
        sortOrder = portal.sortOrder.rawValue
        tint = portal.tint.rawValue
    }

    func domainValue(
        iconSize: IconSize,
        backgroundStyle: PortalBackgroundStyle
    ) throws -> Portal {
        guard let sortOrder = PortalSortOrder(rawValue: sortOrder) else {
            throw PortalStoreMappingError.invalidSortOrder(self.sortOrder)
        }
        guard let tint = PortalTint(rawValue: tint) else {
            throw PortalStoreMappingError.invalidTint(self.tint)
        }
        let gridCapacity: GridCapacity
        do {
            gridCapacity = try GridCapacity(columns: columns, rows: rows)
        } catch {
            throw PortalStoreMappingError.invalidGridCapacity(columns: columns, rows: rows)
        }
        return try Portal(
            id: PortalID(rawValue: id),
            tabs: try tabs.map { try $0.domainValue() },
            selectedTabID: selectedTabID.map(FolderTabID.init(rawValue:)),
            placement: try placement.domainValue(),
            iconSize: iconSize,
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity,
            isPinned: isPinned,
            sortOrder: sortOrder,
            tint: tint
        )
    }
}
