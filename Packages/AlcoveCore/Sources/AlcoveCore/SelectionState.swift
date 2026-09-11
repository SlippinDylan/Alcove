import Foundation

/// The transient Finder-style selection for one folder tab.
///
/// The grid owns ordering and navigation direction. This state only records identities and uses
/// the ordered snapshot supplied by the grid when it needs to form a range.
public struct SelectionState: Equatable, Sendable {
    public private(set) var selectedIDs: Set<FileIdentity>
    public private(set) var anchorID: FileIdentity?
    public private(set) var focusID: FileIdentity?

    public init() {
        selectedIDs = []
        anchorID = nil
        focusID = nil
    }

    /// Replaces the selection with one item and establishes its range anchor and keyboard focus.
    public mutating func select(_ id: FileIdentity) {
        selectedIDs = [id]
        anchorID = id
        focusID = id
    }

    /// Toggles one item without changing the rest of the selection.
    public mutating func toggle(_ id: FileIdentity, in orderedIDs: [FileIdentity]) {
        if selectedIDs.remove(id) != nil {
            let fallbackID = orderedIDs.first { selectedIDs.contains($0) }
            if anchorID == id {
                anchorID = fallbackID
            }
            if focusID == id {
                focusID = fallbackID
            }
        } else {
            selectedIDs.insert(id)
            anchorID = id
            focusID = id
        }
    }

    /// Replaces the selection with the inclusive range between the anchor and the target.
    public mutating func extendRange(to id: FileIdentity, in orderedIDs: [FileIdentity]) {
        guard let targetIndex = orderedIDs.firstIndex(of: id) else {
            return
        }

        guard let anchorID, let anchorIndex = orderedIDs.firstIndex(of: anchorID) else {
            select(id)
            return
        }

        let lowerBound = min(anchorIndex, targetIndex)
        let upperBound = max(anchorIndex, targetIndex)
        selectedIDs = Set(orderedIDs[lowerBound...upperBound])
        focusID = id
    }

    /// Moves keyboard focus to a UI-selected item.
    public mutating func moveFocus(to id: FileIdentity) {
        select(id)
    }

    /// Extends the selection to a UI-selected keyboard focus target.
    public mutating func extendFocus(to id: FileIdentity, in orderedIDs: [FileIdentity]) {
        extendRange(to: id, in: orderedIDs)
    }

    /// Selects every identity in the current ordered snapshot.
    public mutating func selectAll(_ orderedIDs: [FileIdentity]) {
        selectedIDs = Set(orderedIDs)

        guard let firstID = orderedIDs.first else {
            anchorID = nil
            focusID = nil
            return
        }

        if anchorID.map(selectedIDs.contains) != true {
            anchorID = firstID
        }
        if focusID.map(selectedIDs.contains) != true {
            focusID = firstID
        }
    }

    /// Clears selection, range anchor, and keyboard focus.
    public mutating func clear() {
        selectedIDs = []
        anchorID = nil
        focusID = nil
    }

    /// Removes state for identities no longer present in the current ordered snapshot.
    public mutating func reconcile(with orderedIDs: [FileIdentity]) {
        let currentIDs = Set(orderedIDs)
        selectedIDs.formIntersection(currentIDs)

        if selectedIDs.isEmpty {
            anchorID = nil
            focusID = nil
            return
        }

        let retainedAnchor = anchorID.flatMap { currentIDs.contains($0) ? $0 : nil }
        let retainedFocus = focusID.flatMap { currentIDs.contains($0) ? $0 : nil }
        let fallbackID = orderedIDs.first { selectedIDs.contains($0) }

        anchorID = retainedAnchor ?? retainedFocus ?? fallbackID
        focusID = retainedFocus ?? retainedAnchor ?? fallbackID
    }
}
