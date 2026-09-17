import AlcoveCore
import CoreGraphics
import Foundation

/// A validated, portable snapshot decoded from Alcove's public layout-backup format.
struct AlcoveLayoutBackup: Equatable, Sendable {
    let global: AlcoveLayoutBackupGlobal
    let portals: [AlcoveLayoutBackupPortal]
}

struct AlcoveLayoutBackupGlobal: Equatable, Sendable {
    let iconSize: IconSize
    let backgroundStyle: PortalBackgroundStyle
    let spacing: PortalSpacing
    let cornerRadius: PortalCornerRadius
    let shadowEnabled: Bool

    init(
        iconSize: IconSize,
        backgroundStyle: PortalBackgroundStyle,
        spacing: PortalSpacing,
        cornerRadius: PortalCornerRadius,
        shadowEnabled: Bool
    ) {
        self.iconSize = iconSize
        self.backgroundStyle = backgroundStyle
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.shadowEnabled = shadowEnabled
    }
}

struct AlcoveLayoutBackupPortal: Equatable, Sendable {
    let id: PortalID
    let sortOrder: PortalSortOrder
    let tint: PortalTint
    let isPinned: Bool
    let normalizedAnchor: NormalizedAnchor
    let size: CGSize
    let gridCapacity: GridCapacity
    let folderURLs: [URL]
    let selectedFolderIndex: Int?
}

enum AlcoveLayoutBackupError: LocalizedError, Equatable {
    case malformedData
    case invalidFormat(String)
    case unsupportedVersion(Int)
    case invalidIconSize(Double)
    case invalidBackgroundStyle(String)
    case invalidSpacing(Int)
    case invalidCornerRadius(Int)
    case invalidPortalID(String)
    case duplicatePortalID(UUID)
    case invalidSortOrder(String)
    case invalidTint(String)
    case invalidAnchor(x: Double, y: Double)
    case invalidSize(width: Double, height: Double)
    case invalidGridCapacity(columns: Int, rows: Int)
    case invalidSelectedFolderIndex(Int?)
    case tooManyFolders(maximum: Int)
    case invalidFolderPath(String)

    var errorDescription: String? {
        switch self {
        case .malformedData:
            NSLocalizedString(
                "application.settings.backup.error.malformed",
                comment: "Malformed layout backup error"
            )
        case .invalidFormat:
            NSLocalizedString(
                "application.settings.backup.error.format",
                comment: "Wrong layout backup format error"
            )
        case .unsupportedVersion(let version):
            String(
                format: NSLocalizedString(
                    "application.settings.backup.error.version",
                    comment: "Unsupported layout backup version error"
                ),
                version
            )
        case .tooManyFolders(let maximum):
            String(
                format: NSLocalizedString(
                    "application.settings.backup.error.folder_limit",
                    comment: "Layout backup folder limit error"
                ),
                maximum
            )
        default:
            NSLocalizedString(
                "application.settings.backup.error.invalid_data",
                comment: "Invalid layout backup data error"
            )
        }
    }
}

/// Encodes and validates the stable, user-facing Alcove layout-backup format.
enum AlcoveLayoutBackupCodec {
    static let format = "com.alcove.layout-backup"
    static let currentVersion = 1

    static func encode(
        portals: [Portal],
        appearance: PortalAppearancePreferences,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Data {
        let homeDirectory = try validatedHomeDirectory(homeDirectory)
        let dto = LayoutBackupDTO(
            format: format,
            version: currentVersion,
            global: LayoutBackupGlobalDTO(appearance),
            portals: try portals.map { try LayoutBackupPortalDTO($0, homeDirectory: homeDirectory) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(dto)
    }

    static func decode(
        _ data: Data,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> AlcoveLayoutBackup {
        let decoder = JSONDecoder()
        let header: LayoutBackupHeaderDTO
        do {
            header = try decoder.decode(LayoutBackupHeaderDTO.self, from: data)
        } catch {
            throw AlcoveLayoutBackupError.malformedData
        }
        guard header.format == format else {
            throw AlcoveLayoutBackupError.invalidFormat(header.format)
        }
        guard header.version == currentVersion else {
            throw AlcoveLayoutBackupError.unsupportedVersion(header.version)
        }

        let dto: LayoutBackupDTO
        do {
            dto = try decoder.decode(LayoutBackupDTO.self, from: data)
        } catch {
            throw AlcoveLayoutBackupError.malformedData
        }

        let homeDirectory = try validatedHomeDirectory(homeDirectory)
        let global = try dto.global.domainValue()
        var portalIDs = Set<UUID>()
        let portals = try dto.portals.map { portalDTO in
            let portal = try portalDTO.domainValue(homeDirectory: homeDirectory)
            guard portalIDs.insert(portal.id.rawValue).inserted else {
                throw AlcoveLayoutBackupError.duplicatePortalID(portal.id.rawValue)
            }
            return portal
        }
        return AlcoveLayoutBackup(global: global, portals: portals)
    }

    private static func validatedHomeDirectory(_ url: URL) throws -> URL {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw AlcoveLayoutBackupError.invalidFolderPath(url.absoluteString)
        }
        return url.standardizedFileURL
    }
}

private struct LayoutBackupHeaderDTO: Decodable {
    let format: String
    let version: Int
}

private struct LayoutBackupDTO: Codable {
    let format: String
    let version: Int
    let global: LayoutBackupGlobalDTO
    let portals: [LayoutBackupPortalDTO]
}

private struct LayoutBackupGlobalDTO: Codable {
    let iconSize: Double
    let backgroundStyle: String
    let spacing: Int
    let cornerRadius: Int
    let shadowEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case iconSize = "icon_size"
        case backgroundStyle = "background_style"
        case spacing
        case cornerRadius = "corner_radius"
        case shadowEnabled = "shadow_enabled"
    }

    init(_ appearance: PortalAppearancePreferences) {
        iconSize = Double(appearance.iconSize.rawValue)
        backgroundStyle = appearance.backgroundStyle.rawValue
        spacing = appearance.spacing.rawValue
        cornerRadius = appearance.cornerRadius.rawValue
        shadowEnabled = appearance.shadowEnabled
    }

    func domainValue() throws -> AlcoveLayoutBackupGlobal {
        let validIconSizes: [IconSize] = [.small, .medium, .large]
        guard iconSize.isFinite,
              let iconSize = validIconSizes.first(where: { Double($0.rawValue) == iconSize }) else {
            throw AlcoveLayoutBackupError.invalidIconSize(iconSize)
        }
        guard let backgroundStyle = PortalBackgroundStyle(rawValue: backgroundStyle) else {
            throw AlcoveLayoutBackupError.invalidBackgroundStyle(self.backgroundStyle)
        }
        guard let spacing = PortalSpacing(rawValue: spacing) else {
            throw AlcoveLayoutBackupError.invalidSpacing(self.spacing)
        }
        guard let cornerRadius = PortalCornerRadius(rawValue: cornerRadius) else {
            throw AlcoveLayoutBackupError.invalidCornerRadius(self.cornerRadius)
        }
        return AlcoveLayoutBackupGlobal(
            iconSize: iconSize,
            backgroundStyle: backgroundStyle.normalizedSelection,
            spacing: spacing.normalizedSelection,
            cornerRadius: cornerRadius,
            shadowEnabled: shadowEnabled
        )
    }
}

private struct LayoutBackupPortalDTO: Codable {
    let id: String
    let sortOrder: String
    let tint: String
    let isPinned: Bool
    let normalizedAnchor: LayoutBackupAnchorDTO
    let size: LayoutBackupSizeDTO
    let gridCapacity: LayoutBackupGridCapacityDTO
    let folders: [LayoutBackupFolderPathDTO]
    let selectedFolderIndex: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case sortOrder = "sort_order"
        case tint
        case isPinned = "is_pinned"
        case normalizedAnchor = "normalized_anchor"
        case size
        case gridCapacity = "grid_capacity"
        case folders
        case selectedFolderIndex = "selected_folder_index"
    }

    init(_ portal: Portal, homeDirectory: URL) throws {
        id = portal.id.rawValue.uuidString.lowercased()
        sortOrder = portal.sortOrder.rawValue
        tint = portal.tint.rawValue
        isPinned = portal.isPinned
        normalizedAnchor = LayoutBackupAnchorDTO(portal.placement.homeEntry.normalizedAnchor)
        size = LayoutBackupSizeDTO(portal.placement.homeEntry.preferredSize)
        gridCapacity = LayoutBackupGridCapacityDTO(portal.gridCapacity)
        folders = try portal.tabs.map {
            try LayoutBackupFolderPathDTO(folderURL: $0.folderURL, homeDirectory: homeDirectory)
        }
        selectedFolderIndex = portal.selectedTabID.flatMap { selectedID in
            portal.tabs.firstIndex(where: { $0.id == selectedID })
        }
    }

    func domainValue(homeDirectory: URL) throws -> AlcoveLayoutBackupPortal {
        guard let uuid = UUID(uuidString: id) else {
            throw AlcoveLayoutBackupError.invalidPortalID(id)
        }
        guard let sortOrder = PortalSortOrder(rawValue: sortOrder) else {
            throw AlcoveLayoutBackupError.invalidSortOrder(self.sortOrder)
        }
        guard let tint = PortalTint(rawValue: tint) else {
            throw AlcoveLayoutBackupError.invalidTint(self.tint)
        }
        let anchor = try normalizedAnchor.domainValue()
        let size = try size.domainValue()
        let gridCapacity = try gridCapacity.domainValue()
        let folderURLs = try folders.map { try $0.domainValue(homeDirectory: homeDirectory) }
        guard folderURLs.count <= Portal.maximumTabCount else {
            throw AlcoveLayoutBackupError.tooManyFolders(
                maximum: Portal.maximumTabCount
            )
        }
        if folderURLs.isEmpty {
            guard selectedFolderIndex == nil else {
                throw AlcoveLayoutBackupError.invalidSelectedFolderIndex(selectedFolderIndex)
            }
        } else {
            guard let selectedFolderIndex, folderURLs.indices.contains(selectedFolderIndex) else {
                throw AlcoveLayoutBackupError.invalidSelectedFolderIndex(selectedFolderIndex)
            }
        }
        return AlcoveLayoutBackupPortal(
            id: PortalID(rawValue: uuid),
            sortOrder: sortOrder,
            tint: tint,
            isPinned: isPinned,
            normalizedAnchor: anchor,
            size: size,
            gridCapacity: gridCapacity,
            folderURLs: folderURLs,
            selectedFolderIndex: selectedFolderIndex
        )
    }
}

private struct LayoutBackupAnchorDTO: Codable {
    let x: Double
    let y: Double

    init(_ anchor: NormalizedAnchor) {
        x = anchor.x
        y = anchor.y
    }

    func domainValue() throws -> NormalizedAnchor {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw AlcoveLayoutBackupError.invalidAnchor(x: x, y: y)
        }
        return try NormalizedAnchor(x: x, y: y)
    }
}

private struct LayoutBackupSizeDTO: Codable {
    let width: Double
    let height: Double

    init(_ size: CGSize) {
        width = Double(size.width)
        height = Double(size.height)
    }

    func domainValue() throws -> CGSize {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw AlcoveLayoutBackupError.invalidSize(width: width, height: height)
        }
        return CGSize(width: width, height: height)
    }
}

private struct LayoutBackupGridCapacityDTO: Codable {
    let columns: Int
    let rows: Int

    init(_ capacity: GridCapacity) {
        columns = capacity.columns
        rows = capacity.rows
    }

    func domainValue() throws -> GridCapacity {
        do {
            return try GridCapacity(columns: columns, rows: rows)
        } catch {
            throw AlcoveLayoutBackupError.invalidGridCapacity(columns: columns, rows: rows)
        }
    }
}

private struct LayoutBackupFolderPathDTO: Codable {
    private enum Kind: String, Codable {
        case homeRelative = "home_relative"
        case absolute
    }

    private let kind: Kind
    let path: String

    init(folderURL: URL, homeDirectory: URL) throws {
        guard folderURL.isFileURL else {
            throw AlcoveLayoutBackupError.invalidFolderPath(folderURL.absoluteString)
        }
        let folderURL = folderURL.standardizedFileURL
        let homeComponents = homeDirectory.pathComponents
        let folderComponents = folderURL.pathComponents
        if folderComponents.starts(with: homeComponents) {
            kind = .homeRelative
            path = folderComponents.dropFirst(homeComponents.count).joined(separator: "/")
        } else {
            kind = .absolute
            path = folderURL.path
        }
    }

    func domainValue(homeDirectory: URL) throws -> URL {
        guard !path.contains("\0") else {
            throw AlcoveLayoutBackupError.invalidFolderPath(path)
        }
        switch kind {
        case .homeRelative:
            let relativeURL = URL(fileURLWithPath: path, relativeTo: homeDirectory)
            let components = NSString(string: path).pathComponents
            guard !NSString(string: path).isAbsolutePath,
                  !components.contains("..") else {
                throw AlcoveLayoutBackupError.invalidFolderPath(path)
            }
            return relativeURL.standardizedFileURL
        case .absolute:
            guard NSString(string: path).isAbsolutePath else {
                throw AlcoveLayoutBackupError.invalidFolderPath(path)
            }
            return URL(fileURLWithPath: path).standardizedFileURL
        }
    }
}
