import AlcoveCore
import Foundation

struct PortalEnvelopeV11DTO: Codable, Equatable {
    static let currentVersion = 11

    let version: Int
    let portals: [PortalV11DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV11DTO.init)
    }
}

struct PortalV11DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID?
    let placement: PlacementRecordDTO
    let iconSize: Double
    let backgroundStyle: String
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
        case iconSize = "icon_size"
        case backgroundStyle = "background_style"
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
        iconSize = Double(portal.iconSize.rawValue)
        backgroundStyle = portal.backgroundStyle.rawValue
        columns = portal.gridCapacity.columns
        rows = portal.gridCapacity.rows
        isPinned = portal.isPinned
        sortOrder = portal.sortOrder.rawValue
        tint = portal.tint.rawValue
    }

    func domainValue() throws -> Portal {
        guard let iconSize = IconSize(rawValue: CGFloat(iconSize)) else {
            throw PortalStoreMappingError.invalidIconSize(self.iconSize)
        }
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw PortalStoreMappingError.invalidBackgroundStyle(self.backgroundStyle)
        }
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

struct PortalEnvelopeV10DTO: Codable, Equatable {
    static let currentVersion = 10

    let version: Int
    let portals: [PortalV10DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV10DTO.init)
    }
}

struct PortalV10DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID?
    let placement: PlacementRecordDTO
    let iconSize: Double
    let backgroundStyle: String
    let columns: Int
    let rows: Int
    let isPinned: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case iconSize = "icon_size"
        case backgroundStyle = "background_style"
        case columns
        case rows
        case isPinned = "is_pinned"
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = portal.selectedTabID?.rawValue
        placement = PlacementRecordDTO(portal.placement)
        iconSize = Double(portal.iconSize.rawValue)
        backgroundStyle = portal.backgroundStyle.rawValue
        columns = portal.gridCapacity.columns
        rows = portal.gridCapacity.rows
        isPinned = portal.isPinned
    }

    func domainValue() throws -> Portal {
        guard let iconSize = IconSize(rawValue: CGFloat(iconSize)) else {
            throw PortalStoreMappingError.invalidIconSize(self.iconSize)
        }
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw PortalStoreMappingError.invalidBackgroundStyle(self.backgroundStyle)
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
            isPinned: isPinned
        )
    }
}

struct PortalEnvelopeV9DTO: Codable, Equatable {
    static let currentVersion = 9

    let version: Int
    let portals: [PortalV9DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV9DTO.init)
    }
}

struct PortalV9DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID?
    let placement: PlacementRecordDTO
    let iconLayoutMode: String
    let iconSize: Double
    let textSize: Double
    let backgroundStyle: String
    let columns: Int
    let rows: Int
    let isPinned: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case iconLayoutMode = "icon_layout_mode"
        case iconSize = "icon_size"
        case textSize = "text_size"
        case backgroundStyle = "background_style"
        case columns
        case rows
        case isPinned = "is_pinned"
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = portal.selectedTabID?.rawValue
        placement = PlacementRecordDTO(portal.placement)
        switch portal.iconLayout {
        case .fixed:
            iconLayoutMode = "fixed"
        }
        iconSize = Double(portal.iconSize.rawValue)
        textSize = Double(portal.textSize)
        backgroundStyle = portal.backgroundStyle.rawValue
        columns = portal.gridCapacity.columns
        rows = portal.gridCapacity.rows
        isPinned = portal.isPinned
    }

    func domainValue() throws -> Portal {
        let iconLayout = try legacyIconLayout(
            mode: iconLayoutMode,
            iconSize: iconSize,
            textSize: textSize
        )
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw PortalStoreMappingError.invalidBackgroundStyle(self.backgroundStyle)
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
            iconLayout: iconLayout,
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity,
            isPinned: isPinned
        )
    }
}

struct PortalEnvelopeV8DTO: Codable, Equatable {
    static let currentVersion = 8

    let version: Int
    let portals: [PortalV8DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV8DTO.init)
    }
}

struct PortalV8DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID?
    let placement: PlacementRecordDTO
    let iconLayoutMode: String
    let iconSize: Double
    let textSize: Double
    let backgroundStyle: String
    let columns: Int
    let rows: Int
    let isPinned: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case iconLayoutMode = "icon_layout_mode"
        case iconSize = "icon_size"
        case textSize = "text_size"
        case backgroundStyle = "background_style"
        case columns
        case rows
        case isPinned = "is_pinned"
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = portal.selectedTabID?.rawValue
        placement = PlacementRecordDTO(portal.placement)
        switch portal.iconLayout {
        case .fixed:
            iconLayoutMode = "fixed"
        }
        iconSize = Double(portal.iconSize.rawValue)
        textSize = Double(portal.textSize)
        backgroundStyle = portal.backgroundStyle.rawValue
        columns = portal.gridCapacity.columns
        rows = portal.gridCapacity.rows
        isPinned = portal.isPinned
    }

    func domainValue() throws -> Portal {
        let iconLayout = try legacyIconLayout(
            mode: iconLayoutMode,
            iconSize: iconSize,
            textSize: textSize
        )
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw PortalStoreMappingError.invalidBackgroundStyle(self.backgroundStyle)
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
            iconLayout: iconLayout,
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity,
            isPinned: isPinned
        )
    }
}

struct PortalEnvelopeV7DTO: Codable, Equatable {
    static let currentVersion = 7

    let version: Int
    let portals: [PortalV7DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV7DTO.init)
    }
}

struct PortalV7DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID?
    let placement: PlacementRecordDTO
    let iconLayoutMode: String
    let iconSize: Double
    let textSize: Double
    let backgroundStyle: String
    let columns: Int
    let rows: Int
    let isPinned: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case iconLayoutMode = "icon_layout_mode"
        case iconSize = "icon_size"
        case textSize = "text_size"
        case backgroundStyle = "background_style"
        case columns
        case rows
        case isPinned = "is_pinned"
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = portal.selectedTabID?.rawValue
        placement = PlacementRecordDTO(portal.placement)
        switch portal.iconLayout {
        case .fixed:
            iconLayoutMode = "fixed"
        }
        iconSize = Double(portal.iconSize.rawValue)
        textSize = Double(portal.textSize)
        backgroundStyle = portal.backgroundStyle.rawValue
        columns = portal.gridCapacity.columns
        rows = portal.gridCapacity.rows
        isPinned = portal.isPinned
    }

    func domainValue() throws -> Portal {
        let iconLayout = try legacyIconLayout(
            mode: iconLayoutMode,
            iconSize: iconSize,
            textSize: textSize
        )
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw PortalStoreMappingError.invalidBackgroundStyle(self.backgroundStyle)
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
            iconLayout: iconLayout,
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity,
            isPinned: isPinned
        )
    }
}

struct PortalEnvelopeV6DTO: Codable, Equatable {
    static let currentVersion = 6

    let version: Int
    let portals: [PortalV6DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV6DTO.init)
    }
}

struct PortalV6DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID?
    let placement: PlacementRecordDTO
    let iconLayoutMode: String
    let iconSize: Double
    let textSize: Double
    let backgroundStyle: String
    let columns: Int
    let rows: Int

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case iconLayoutMode = "icon_layout_mode"
        case iconSize = "icon_size"
        case textSize = "text_size"
        case backgroundStyle = "background_style"
        case columns
        case rows
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = portal.selectedTabID?.rawValue
        placement = PlacementRecordDTO(portal.placement)
        switch portal.iconLayout {
        case .fixed:
            iconLayoutMode = "fixed"
        }
        iconSize = Double(portal.iconSize.rawValue)
        textSize = Double(portal.textSize)
        backgroundStyle = portal.backgroundStyle.rawValue
        columns = portal.gridCapacity.columns
        rows = portal.gridCapacity.rows
    }

    func domainValue() throws -> Portal {
        let iconLayout = try legacyIconLayout(
            mode: iconLayoutMode,
            iconSize: iconSize,
            textSize: textSize
        )
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw PortalStoreMappingError.invalidBackgroundStyle(self.backgroundStyle)
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
            iconLayout: iconLayout,
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity,
            isPinned: false
        )
    }
}

struct PortalEnvelopeV5DTO: Codable, Equatable {
    static let currentVersion = 5

    let version: Int
    let portals: [PortalV5DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV5DTO.init)
    }
}

struct PortalV5DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID
    let placement: PlacementRecordDTO
    let iconLayoutMode: String
    let iconSize: Double
    let textSize: Double
    let backgroundStyle: String
    let columns: Int
    let rows: Int

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case iconLayoutMode = "icon_layout_mode"
        case iconSize = "icon_size"
        case textSize = "text_size"
        case backgroundStyle = "background_style"
        case columns
        case rows
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = legacySelectedTabID(in: portal)
        placement = PlacementRecordDTO(portal.placement)
        switch portal.iconLayout {
        case .fixed:
            iconLayoutMode = "fixed"
        }
        iconSize = Double(portal.iconSize.rawValue)
        textSize = Double(portal.textSize)
        backgroundStyle = portal.backgroundStyle.rawValue
        columns = portal.gridCapacity.columns
        rows = portal.gridCapacity.rows
    }

    func domainValue() throws -> Portal {
        let iconLayout = try mappedIconLayout()
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw PortalStoreMappingError.invalidBackgroundStyle(self.backgroundStyle)
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
            selectedTabID: FolderTabID(rawValue: selectedTabID),
            placement: try placement.domainValue(),
            iconLayout: iconLayout,
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity
        )
    }

    private func mappedIconLayout() throws -> PortalIconLayout {
        try legacyIconLayout(
            mode: iconLayoutMode,
            iconSize: iconSize,
            textSize: textSize
        )
    }
}

struct PortalEnvelopeV4DTO: Codable, Equatable {
    static let currentVersion = 4

    let version: Int
    let portals: [PortalV4DTO]

    init(portals: [Portal]) {
        version = Self.currentVersion
        self.portals = portals.map(PortalV4DTO.init)
    }
}

struct PortalV4DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID
    let placement: PlacementRecordDTO
    let iconLayoutMode: String
    let iconSize: Double
    let textSize: Double
    let backgroundStyle: String

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case iconLayoutMode = "icon_layout_mode"
        case iconSize = "icon_size"
        case textSize = "text_size"
        case backgroundStyle = "background_style"
    }

    init(_ portal: Portal) {
        id = portal.id.rawValue
        tabs = portal.tabs.map(FolderTabDTO.init)
        selectedTabID = legacySelectedTabID(in: portal)
        placement = PlacementRecordDTO(portal.placement)
        switch portal.iconLayout {
        case .fixed:
            iconLayoutMode = "fixed"
        }
        iconSize = Double(portal.iconSize.rawValue)
        textSize = Double(portal.textSize)
        backgroundStyle = portal.backgroundStyle.rawValue
    }

    func domainValue() throws -> Portal {
        let iconLayout = try legacyIconLayout(
            mode: iconLayoutMode,
            iconSize: iconSize,
            textSize: textSize
        )
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw PortalStoreMappingError.invalidBackgroundStyle(self.backgroundStyle)
        }
        let placement = try placement.domainValue()
        return try Portal(
            id: PortalID(rawValue: id),
            tabs: try tabs.map { try $0.domainValue() },
            selectedTabID: FolderTabID(rawValue: selectedTabID),
            placement: placement,
            iconLayout: iconLayout,
            backgroundStyle: backgroundStyle,
            gridCapacity: migratedGridCapacity(
                from: placement.homeEntry.absoluteFrame,
                iconLayout: iconLayout
            )
        )
    }
}

struct PortalEnvelopeV3DTO: Codable, Equatable {
    static let currentVersion = 3

    let version: Int
    let portals: [PortalV3DTO]
}

struct PortalV3DTO: Codable, Equatable {
    let id: UUID
    let tabs: [FolderTabDTO]
    let selectedTabID: UUID
    let placement: PlacementRecordDTO
    let iconSize: Double
    let backgroundStyle: String

    enum CodingKeys: String, CodingKey {
        case id
        case tabs
        case selectedTabID = "selected_tab_id"
        case placement
        case iconSize = "icon_size"
        case backgroundStyle = "background_style"
    }

    func domainValue() throws -> Portal {
        guard let iconSize = IconSize(rawValue: CGFloat(iconSize)) else {
            throw PortalStoreMappingError.invalidIconSize(self.iconSize)
        }
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw PortalStoreMappingError.invalidBackgroundStyle(self.backgroundStyle)
        }
        let placement = try placement.domainValue()
        let iconLayout = PortalIconLayout.fixed(iconSize)
        return try Portal(
            id: PortalID(rawValue: id),
            tabs: try tabs.map { try $0.domainValue() },
            selectedTabID: FolderTabID(rawValue: selectedTabID),
            placement: placement,
            iconLayout: iconLayout,
            backgroundStyle: backgroundStyle,
            gridCapacity: migratedGridCapacity(
                from: placement.homeEntry.absoluteFrame,
                iconLayout: iconLayout
            )
        )
    }
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
        selectedTabID = legacySelectedTabID(in: portal)
        placement = PlacementRecordDTO(portal.placement)
        iconSize = Double(portal.iconSize.rawValue)
    }

    func domainValue() throws -> Portal {
        guard let iconSize = IconSize(rawValue: CGFloat(iconSize)) else {
            throw PortalStoreMappingError.invalidIconSize(self.iconSize)
        }
        let placement = try placement.domainValue()
        let iconLayout = PortalIconLayout.fixed(iconSize)
        return try Portal(
            id: PortalID(rawValue: id),
            tabs: try tabs.map { try $0.domainValue() },
            selectedTabID: FolderTabID(rawValue: selectedTabID),
            placement: placement,
            iconLayout: iconLayout,
            gridCapacity: migratedGridCapacity(
                from: placement.homeEntry.absoluteFrame,
                iconLayout: iconLayout
            )
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
        let frame = try frame.domainValue(label: "frame")
        return try Portal(
            id: PortalID(rawValue: id),
            tabs: try tabs.map { try $0.domainValue() },
            selectedTabID: FolderTabID(rawValue: selectedTabID),
            placement: PlacementRecord(
                frame: frame,
                display: display
            ),
            iconSize: iconSize,
            gridCapacity: migratedGridCapacity(
                from: frame,
                iconLayout: .fixed(iconSize)
            )
        )
    }
}

private func migratedGridCapacity(
    from windowFrame: CGRect,
    iconLayout: PortalIconLayout
) throws -> GridCapacity {
    // Versions 1–4 stored frames produced by the pre-v8/v9 grid metrics.
    try GridMetrics(
        iconSize: iconLayout.iconSize,
        labelFontSize: iconLayout.textSize,
        horizontalSpacing: 12,
        verticalSpacing: 4,
        contentInsets: GridInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    ).nearestCapacity(
        for: CGSize(
            width: windowFrame.width,
            height: windowFrame.height - PortalLayoutMetrics.tabBarHeight
        )
    )
}

private func legacyIconLayout(
    mode: String,
    iconSize rawIconSize: Double,
    textSize _: Double
) throws -> PortalIconLayout {
    guard let iconSize = IconSize(rawValue: CGFloat(rawIconSize)) else {
        throw PortalStoreMappingError.invalidIconSize(rawIconSize)
    }
    switch mode {
    case "fixed":
        return .fixed(iconSize)
    case "follow_desktop":
        return .fixed(nearestIconSizePreset(to: iconSize))
    default:
        throw PortalStoreMappingError.invalidIconLayoutMode(mode)
    }
}

private func nearestIconSizePreset(to iconSize: IconSize) -> IconSize {
    if iconSize.rawValue < 56 { return .small }
    if iconSize.rawValue < 72 { return .medium }
    return .large
}

private func legacySelectedTabID(in portal: Portal) -> UUID {
    guard let selectedTabID = portal.selectedTabID else {
        preconditionFailure("Legacy persistence cannot encode an empty Portal")
    }
    return selectedTabID.rawValue
}
