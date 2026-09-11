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
    case nonFiniteFrame
    case nonPositiveFrameSize
}

/// The UI-free durable state for one portal.
///
/// Tab array order is creation order. It is intentionally the only ordering representation.
public struct Portal: Identifiable, Equatable, Sendable {
    public let id: PortalID
    public private(set) var tabs: [FolderTab]
    public private(set) var selectedTabID: FolderTabID
    public private(set) var frame: CGRect
    public private(set) var iconSize: IconSize

    /// Creates the one-tab portal state used by the first persistence schema.
    public init(
        id: PortalID = PortalID(),
        folderURL: URL,
        frame: CGRect,
        iconSize: IconSize = .medium
    ) throws {
        let tab = FolderTab(folderURL: folderURL)
        try self.init(
            id: id,
            tabs: [tab],
            selectedTabID: tab.id,
            frame: frame,
            iconSize: iconSize
        )
    }

    /// Restores a fully validated portal state from persistence infrastructure.
    public init(
        id: PortalID = PortalID(),
        tabs: [FolderTab],
        selectedTabID: FolderTabID,
        frame: CGRect,
        iconSize: IconSize = .medium
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

        try Self.validate(frame)

        self.id = id
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.frame = frame
        self.iconSize = iconSize
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

    /// Replaces the portal frame after validating it for persistence.
    public mutating func updateFrame(_ frame: CGRect) throws {
        try Self.validate(frame)
        self.frame = frame
    }

    /// Replaces the app-owned icon-size preference.
    public mutating func updateIconSize(_ iconSize: IconSize) {
        self.iconSize = iconSize
    }

    private static func validate(_ frame: CGRect) throws {
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite
        else {
            throw PortalError.nonFiniteFrame
        }
        guard frame.width > 0, frame.height > 0 else {
            throw PortalError.nonPositiveFrameSize
        }
    }
}
