import AlcoveCore
import AppKit

@MainActor
final class PortalSettingsFolderListView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    static let pasteboardType = NSPasteboard.PasteboardType(
        "com.dylanwang.Alcove.portal-settings-folder"
    )

    private let tabs: [FolderTab]
    private let onRemove: (FolderTabID) -> Void
    private let onMove: (FolderTabID, Int) -> Void
    private(set) var tableView = NSTableView()

    init(
        tabs: [FolderTab],
        onRemove: @escaping (FolderTabID) -> Void,
        onMove: @escaping (FolderTabID, Int) -> Void
    ) {
        self.tabs = tabs
        self.onRemove = onRemove
        self.onMove = onMove
        super.init(frame: .zero)

        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = false
        hasHorizontalScroller = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 36
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.registerForDraggedTypes([Self.pasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask([], forLocal: false)
        tableView.dataSource = self
        tableView.delegate = self
        documentView = tableView
        heightAnchor.constraint(
            equalToConstant: max(CGFloat(tabs.count) * tableView.rowHeight, 6)
        ).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tabs.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        PortalSettingsFolderCellView(
            tab: tabs[row],
            showsSeparator: row < tabs.count - 1,
            onRemove: onRemove
        )
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(tabs[row].id.rawValue.uuidString, forType: Self.pasteboardType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard draggedFolderID(from: info) != nil else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let id = draggedFolderID(from: info),
              let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else {
            return false
        }
        var targetIndex = min(max(row, 0), tabs.count)
        if targetIndex > sourceIndex {
            targetIndex -= 1
        }
        guard targetIndex != sourceIndex else { return false }
        onMove(id, targetIndex)
        return true
    }

    private func draggedFolderID(from info: any NSDraggingInfo) -> FolderTabID? {
        guard let value = info.draggingPasteboard.string(forType: Self.pasteboardType),
              let rawValue = UUID(uuidString: value),
              tabs.contains(where: { $0.id.rawValue == rawValue }) else {
            return nil
        }
        return FolderTabID(rawValue: rawValue)
    }
}

@MainActor
private final class PortalSettingsFolderCellView: NSTableCellView {
    private let onRemove: (FolderTabID) -> Void
    private let tabID: FolderTabID

    init(
        tab: FolderTab,
        showsSeparator: Bool,
        onRemove: @escaping (FolderTabID) -> Void
    ) {
        self.onRemove = onRemove
        tabID = tab.id
        super.init(frame: .zero)

        let folderIcon = NSImageView()
        folderIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        folderIcon.contentTintColor = .secondaryLabelColor
        folderIcon.translatesAutoresizingMaskIntoConstraints = false

        let pathLabel = NSTextField(
            labelWithString: (tab.folderURL.path as NSString).abbreviatingWithTildeInPath
        )
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        let dragIndicator = PortalSettingsDragIndicatorView()
        dragIndicator.translatesAutoresizingMaskIntoConstraints = false

        let removeButton = NSButton()
        removeButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.contentTintColor = .systemRed
        removeButton.target = self
        removeButton.action = #selector(removeFolder)
        removeButton.toolTip = NSLocalizedString(
            "portal.settings.remove_folder_action",
            comment: "Remove folder"
        )
        removeButton.setAccessibilityLabel(removeButton.toolTip)
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(folderIcon)
        addSubview(pathLabel)
        addSubview(dragIndicator)
        addSubview(removeButton)
        if showsSeparator {
            let separator = NSBox()
            separator.boxType = .separator
            separator.identifier = NSUserInterfaceItemIdentifier(
                "portal-settings.folder-row-separator"
            )
            separator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(separator)
            NSLayoutConstraint.activate([
                separator.leadingAnchor.constraint(equalTo: leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: trailingAnchor),
                separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            folderIcon.leadingAnchor.constraint(equalTo: leadingAnchor),
            folderIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            folderIcon.widthAnchor.constraint(equalToConstant: 18),
            folderIcon.heightAnchor.constraint(equalToConstant: 18),
            pathLabel.leadingAnchor.constraint(equalTo: folderIcon.trailingAnchor, constant: 8),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            dragIndicator.leadingAnchor.constraint(greaterThanOrEqualTo: pathLabel.trailingAnchor, constant: 8),
            dragIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            dragIndicator.widthAnchor.constraint(equalToConstant: 24),
            dragIndicator.heightAnchor.constraint(equalToConstant: 24),
            removeButton.leadingAnchor.constraint(equalTo: dragIndicator.trailingAnchor, constant: 4),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func removeFolder() {
        onRemove(tabID)
    }
}

@MainActor
private final class PortalSettingsDragIndicatorView: NSImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        contentTintColor = .secondaryLabelColor
        toolTip = NSLocalizedString(
            "portal.settings.reorder_folder",
            comment: "Reorder folder by dragging"
        )
        setAccessibilityElement(true)
        setAccessibilityLabel(toolTip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
