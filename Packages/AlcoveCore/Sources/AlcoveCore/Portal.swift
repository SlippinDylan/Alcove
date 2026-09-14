import CoreGraphics
import Foundation

/// The durable identity of one portal.
public struct PortalID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }
}

/// The durable identity of one folder tab within a portal.
public struct FolderTabID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }
}

/// A mapped folder. Folder eligibility is validated at the selection boundary outside AlcoveCore.
public struct FolderTab: Identifiable, Hashable, Sendable {
    public let id: FolderTabID
    public let folderURL: URL

    public init(id: FolderTabID = FolderTabID(), folderURL: URL) {
        self.id = id
        self.folderURL = folderURL.standardizedFileURL
    }
}

public enum PortalTabMoveDirection: Equatable, Sendable {
    case up
    case down
}

/// Errors raised when a portal operation would violate durable portal state.
public enum PortalError: Error, Equatable, Sendable {
    case selectionWithoutTabs(FolderTabID)
    case missingSelectedTab
    case duplicateTabID(FolderTabID)
    case maximumTabCountExceeded(Int)
    case selectedTabNotFound(FolderTabID)
    case tabNotFound(FolderTabID)
    case cannotMoveTab(FolderTabID, PortalTabMoveDirection)
    case cannotRemoveLastTab
    case invalidPlacement(PlacementRecordError)
}

public enum PlacementRecordError: Error, Equatable, Sendable {
    case missingHomePlacement(DisplayIdentity)
    case invalidEntry(DisplayIdentity, PlacementError)
    case nonPositiveFrameSize(DisplayIdentity)
    case nonPositivePreferredSize(DisplayIdentity)
}

/// Durable user-confirmed placement history for one portal.
public struct PlacementRecord: Equatable, Sendable {
    public private(set) var framesByDisplay: [DisplayIdentity: DisplayPlacementEntry]
    public private(set) var homeDisplay: DisplayIdentity
    private var homePlacement: DisplayPlacementEntry

    public var homeEntry: DisplayPlacementEntry { homePlacement }

    public init(
        framesByDisplay: [DisplayIdentity: DisplayPlacementEntry],
        homeDisplay: DisplayIdentity
    ) throws {
        guard let homePlacement = framesByDisplay[homeDisplay] else {
            throw PlacementRecordError.missingHomePlacement(homeDisplay)
        }
        for (display, entry) in framesByDisplay {
            try Self.validate(entry, on: display)
        }
        self.framesByDisplay = framesByDisplay
        self.homeDisplay = homeDisplay
        self.homePlacement = homePlacement
    }

    public init(frame: CGRect, display: DisplayDescriptor) throws {
        let entry = try Self.capture(frame: frame, display: display)
        guard frame.width > 0, frame.height > 0 else {
            throw PlacementRecordError.nonPositiveFrameSize(display.identity)
        }
        framesByDisplay = [display.identity: entry]
        homeDisplay = display.identity
        homePlacement = entry
    }

    /// Records a placement only after the caller has classified the frame change as user-driven.
    public mutating func recordUserPlacement(
        frame: CGRect,
        display: DisplayDescriptor
    ) throws {
        let entry = try Self.capture(frame: frame, display: display)
        guard frame.width > 0, frame.height > 0 else {
            throw PlacementRecordError.nonPositiveFrameSize(display.identity)
        }
        framesByDisplay[display.identity] = entry
        homeDisplay = display.identity
        homePlacement = entry
    }

    private static func capture(
        frame: CGRect,
        display: DisplayDescriptor
    ) throws -> DisplayPlacementEntry {
        do {
            return try PlacementGeometry.capture(
                windowFrame: frame,
                visibleFrame: display.visibleFrame
            )
        } catch let error as PlacementError {
            throw PlacementRecordError.invalidEntry(display.identity, error)
        }
    }

    private static func validate(
        _ entry: DisplayPlacementEntry,
        on display: DisplayIdentity
    ) throws {
        guard entry.absoluteFrame.width > 0, entry.absoluteFrame.height > 0 else {
            throw PlacementRecordError.nonPositiveFrameSize(display)
        }
        guard entry.preferredSize.width > 0, entry.preferredSize.height > 0 else {
            throw PlacementRecordError.nonPositivePreferredSize(display)
        }
        do {
            _ = try PlacementGeometry.restore(
                record: entry,
                currentVisibleFrame: entry.referenceVisibleFrame
            )
        } catch let error as PlacementError {
            throw PlacementRecordError.invalidEntry(display, error)
        }
    }
}

/// The UI-free durable state for one portal.
///
/// Tab array order is creation order. It is intentionally the only ordering representation.
public struct Portal: Identifiable, Equatable, Sendable {
    public static let maximumTabCount = 4

    public let id: PortalID
    public private(set) var tabs: [FolderTab]
    public private(set) var selectedTabID: FolderTabID?
    public private(set) var placement: PlacementRecord
    public private(set) var iconLayout: PortalIconLayout
    public private(set) var backgroundStyle: PortalBackgroundStyle
    public private(set) var gridCapacity: GridCapacity
    public private(set) var isPinned: Bool
    public private(set) var sortOrder: PortalSortOrder
    public private(set) var tint: PortalTint

    public var frame: CGRect { placement.homeEntry.absoluteFrame }
    public var iconSize: IconSize { iconLayout.iconSize }
    public var textSize: CGFloat { iconLayout.textSize }
    public var selectedTab: FolderTab? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    /// Creates an empty portal that can be mapped to its first folder later.
    public init(
        id: PortalID = PortalID(),
        frame: CGRect,
        display: DisplayDescriptor,
        iconLayout: PortalIconLayout = .fixed(.medium),
        backgroundStyle: PortalBackgroundStyle = .standard,
        gridCapacity: GridCapacity = .minimum,
        isPinned: Bool = false,
        sortOrder: PortalSortOrder = .name,
        tint: PortalTint = .default
    ) throws {
        let placement: PlacementRecord
        do {
            placement = try PlacementRecord(frame: frame, display: display)
        } catch let error as PlacementRecordError {
            throw PortalError.invalidPlacement(error)
        }
        try self.init(
            id: id,
            tabs: [],
            selectedTabID: nil,
            placement: placement,
            iconLayout: iconLayout,
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity,
            isPinned: isPinned,
            sortOrder: sortOrder,
            tint: tint
        )
    }

    /// Creates a one-tab portal with a placement captured on a real display.
    public init(
        id: PortalID = PortalID(),
        folderURL: URL,
        frame: CGRect,
        display: DisplayDescriptor,
        iconSize: IconSize = .medium,
        backgroundStyle: PortalBackgroundStyle = .standard,
        gridCapacity: GridCapacity = .minimum,
        isPinned: Bool = false,
        sortOrder: PortalSortOrder = .name,
        tint: PortalTint = .default
    ) throws {
        try self.init(
            id: id,
            folderURL: folderURL,
            frame: frame,
            display: display,
            iconLayout: .fixed(iconSize),
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity,
            isPinned: isPinned,
            sortOrder: sortOrder,
            tint: tint
        )
    }

    /// Creates a one-tab portal with an explicit icon-layout preference.
    public init(
        id: PortalID = PortalID(),
        folderURL: URL,
        frame: CGRect,
        display: DisplayDescriptor,
        iconLayout: PortalIconLayout,
        backgroundStyle: PortalBackgroundStyle = .standard,
        gridCapacity: GridCapacity = .minimum,
        isPinned: Bool = false,
        sortOrder: PortalSortOrder = .name,
        tint: PortalTint = .default
    ) throws {
        let tab = FolderTab(folderURL: folderURL)
        let placement: PlacementRecord
        do {
            placement = try PlacementRecord(frame: frame, display: display)
        } catch let error as PlacementRecordError {
            throw PortalError.invalidPlacement(error)
        }
        try self.init(
            id: id,
            tabs: [tab],
            selectedTabID: tab.id,
            placement: placement,
            iconLayout: iconLayout,
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity,
            isPinned: isPinned,
            sortOrder: sortOrder,
            tint: tint
        )
    }

    /// Restores a fully validated portal state from persistence infrastructure.
    public init(
        id: PortalID = PortalID(),
        tabs: [FolderTab],
        selectedTabID: FolderTabID?,
        placement: PlacementRecord,
        iconSize: IconSize = .medium,
        backgroundStyle: PortalBackgroundStyle = .standard,
        gridCapacity: GridCapacity = .minimum,
        isPinned: Bool = false,
        sortOrder: PortalSortOrder = .name,
        tint: PortalTint = .default
    ) throws {
        try self.init(
            id: id,
            tabs: tabs,
            selectedTabID: selectedTabID,
            placement: placement,
            iconLayout: .fixed(iconSize),
            backgroundStyle: backgroundStyle,
            gridCapacity: gridCapacity,
            isPinned: isPinned,
            sortOrder: sortOrder,
            tint: tint
        )
    }

    /// Restores fully validated portal state with an explicit icon-layout preference.
    public init(
        id: PortalID = PortalID(),
        tabs: [FolderTab],
        selectedTabID: FolderTabID?,
        placement: PlacementRecord,
        iconLayout: PortalIconLayout,
        backgroundStyle: PortalBackgroundStyle = .standard,
        gridCapacity: GridCapacity = .minimum,
        isPinned: Bool = false,
        sortOrder: PortalSortOrder = .name,
        tint: PortalTint = .default
    ) throws {
        guard tabs.count <= Self.maximumTabCount else {
            throw PortalError.maximumTabCountExceeded(Self.maximumTabCount)
        }
        var tabIDs = Set<FolderTabID>()
        for tab in tabs {
            guard tabIDs.insert(tab.id).inserted else {
                throw PortalError.duplicateTabID(tab.id)
            }
        }

        if tabs.isEmpty {
            if let selectedTabID {
                throw PortalError.selectionWithoutTabs(selectedTabID)
            }
        } else {
            guard let selectedTabID else {
                throw PortalError.missingSelectedTab
            }
            guard tabIDs.contains(selectedTabID) else {
                throw PortalError.selectedTabNotFound(selectedTabID)
            }
        }

        self.id = id
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.placement = placement
        self.iconLayout = iconLayout
        self.backgroundStyle = backgroundStyle
        self.gridCapacity = gridCapacity
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.tint = tint
    }

    /// Appends a tab without changing the active tab.
    public mutating func appendTab(_ tab: FolderTab) throws {
        guard tabs.count < Self.maximumTabCount else {
            throw PortalError.maximumTabCountExceeded(Self.maximumTabCount)
        }
        guard !tabs.contains(where: { $0.id == tab.id }) else {
            throw PortalError.duplicateTabID(tab.id)
        }

        tabs.append(tab)
        if selectedTabID == nil {
            selectedTabID = tab.id
        }
    }

    /// Appends a new tab without changing the active tab.
    @discardableResult
    public mutating func appendTab(folderURL: URL) throws -> FolderTabID {
        let tab = FolderTab(folderURL: folderURL)
        try appendTab(tab)
        return tab.id
    }

    /// Changes the active tab to an existing tab.
    public mutating func selectTab(_ id: FolderTabID) throws {
        guard tabs.contains(where: { $0.id == id }) else {
            throw PortalError.tabNotFound(id)
        }

        selectedTabID = id
    }

    /// Moves a tab one position while preserving the selected tab identity.
    public mutating func moveTab(
        _ id: FolderTabID,
        toward direction: PortalTabMoveDirection
    ) throws {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            throw PortalError.tabNotFound(id)
        }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = index - 1
        case .down:
            targetIndex = index + 1
        }
        guard tabs.indices.contains(targetIndex) else {
            throw PortalError.cannotMoveTab(id, direction)
        }
        tabs.swapAt(index, targetIndex)
    }

    /// Removes one tab. The final tab is retained so the caller can request portal removal instead.
    public mutating func removeTab(_ id: FolderTabID) throws {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            throw PortalError.tabNotFound(id)
        }
        guard tabs.count > 1 else {
            throw PortalError.cannotRemoveLastTab
        }

        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    /// Records a user-confirmed frame and makes its display the remembered home.
    public mutating func recordUserPlacement(
        frame: CGRect,
        display: DisplayDescriptor
    ) throws {
        do {
            try placement.recordUserPlacement(frame: frame, display: display)
        } catch let error as PlacementRecordError {
            throw PortalError.invalidPlacement(error)
        }
    }

    /// Replaces the app-owned icon-size preference.
    public mutating func updateIconSize(_ iconSize: IconSize) {
        iconLayout = .fixed(iconSize)
    }

    /// Replaces the portal's icon-layout preference.
    public mutating func updateIconLayout(_ iconLayout: PortalIconLayout) {
        self.iconLayout = iconLayout
    }

    /// Replaces the app-owned background appearance preference.
    public mutating func updateBackgroundStyle(_ backgroundStyle: PortalBackgroundStyle) {
        self.backgroundStyle = backgroundStyle
    }

    /// Replaces the visible grid capacity while preserving its current placement.
    public mutating func updateGridCapacity(_ gridCapacity: GridCapacity) {
        self.gridCapacity = gridCapacity
    }

    /// Updates whether user-driven movement and resizing are disabled for this portal.
    public mutating func updatePinned(_ isPinned: Bool) {
        self.isPinned = isPinned
    }

    public mutating func updateSortOrder(_ sortOrder: PortalSortOrder) {
        self.sortOrder = sortOrder
    }

    public mutating func updateTint(_ tint: PortalTint) {
        self.tint = tint
    }
}
