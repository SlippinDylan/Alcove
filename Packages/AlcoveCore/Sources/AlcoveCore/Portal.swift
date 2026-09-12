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

/// Errors raised when a portal operation would violate durable portal state.
public enum PortalError: Error, Equatable, Sendable {
    case emptyTabs
    case duplicateTabID(FolderTabID)
    case selectedTabNotFound(FolderTabID)
    case tabNotFound(FolderTabID)
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
    public let id: PortalID
    public private(set) var tabs: [FolderTab]
    public private(set) var selectedTabID: FolderTabID
    public private(set) var placement: PlacementRecord
    public private(set) var iconSize: IconSize
    public private(set) var backgroundStyle: PortalBackgroundStyle

    public var frame: CGRect { placement.homeEntry.absoluteFrame }

    /// Creates a one-tab portal with a placement captured on a real display.
    public init(
        id: PortalID = PortalID(),
        folderURL: URL,
        frame: CGRect,
        display: DisplayDescriptor,
        iconSize: IconSize = .medium,
        backgroundStyle: PortalBackgroundStyle = .standard
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
            iconSize: iconSize,
            backgroundStyle: backgroundStyle
        )
    }

    /// Restores a fully validated portal state from persistence infrastructure.
    public init(
        id: PortalID = PortalID(),
        tabs: [FolderTab],
        selectedTabID: FolderTabID,
        placement: PlacementRecord,
        iconSize: IconSize = .medium,
        backgroundStyle: PortalBackgroundStyle = .standard
    ) throws {
        guard !tabs.isEmpty else {
            throw PortalError.emptyTabs
        }

        var tabIDs = Set<FolderTabID>()
        for tab in tabs {
            guard tabIDs.insert(tab.id).inserted else {
                throw PortalError.duplicateTabID(tab.id)
            }
        }

        guard tabIDs.contains(selectedTabID) else {
            throw PortalError.selectedTabNotFound(selectedTabID)
        }

        self.id = id
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.placement = placement
        self.iconSize = iconSize
        self.backgroundStyle = backgroundStyle
    }

    /// Appends a tab without changing the active tab.
    public mutating func appendTab(_ tab: FolderTab) throws {
        guard !tabs.contains(where: { $0.id == tab.id }) else {
            throw PortalError.duplicateTabID(tab.id)
        }

        tabs.append(tab)
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
        self.iconSize = iconSize
    }

    /// Replaces the app-owned background appearance preference.
    public mutating func updateBackgroundStyle(_ backgroundStyle: PortalBackgroundStyle) {
        self.backgroundStyle = backgroundStyle
    }
}
