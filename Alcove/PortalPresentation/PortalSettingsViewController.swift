import AlcoveCore
import AppKit

@MainActor
final class PortalSettingsViewController: NSViewController {
    enum Category: Int, CaseIterable {
        case general
        case folders
        case style

        var title: String {
            switch self {
            case .general:
                NSLocalizedString("portal.settings.general", comment: "General settings category")
            case .folders:
                NSLocalizedString("portal.settings.folders", comment: "Folders settings category")
            case .style:
                NSLocalizedString("portal.settings.style", comment: "Style settings category")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .folders: "folder"
            case .style: "paintpalette"
            }
        }

        var toolbarItemIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier("portal-settings.\(rawValue)")
        }

        init?(toolbarItemIdentifier: NSToolbarItem.Identifier) {
            guard let category = Self.allCases.first(where: {
                $0.toolbarItemIdentifier == toolbarItemIdentifier
            }) else {
                return nil
            }
            self = category
        }
    }

    private var portal: Portal
    private let onAddFolder: () -> Void
    private let onCloseFolder: (FolderTabID) -> Void
    private let onMoveFolder: (FolderTabID, Int) -> Void
    private let onSetSortOrder: (PortalSortOrder) -> Void
    private let onSetTint: (PortalTint) -> Void
    private(set) var selectedCategory = Category.general
    private(set) var contentSeparator = NSBox()
    private(set) var scrollView = NSScrollView()
    private(set) var contentStack: NSStackView = PortalSettingsContentStackView()
    private(set) var folderListView: PortalSettingsFolderListView?
    private(set) var addFolderButton: NSButton?
    private(set) var sortOptionButtons: [NSButton] = []
    private(set) var tintOptionButtons: [PortalTintSwatchButton] = []
    private let documentView = PortalSettingsDocumentView()

    init(
        portal: Portal,
        onAddFolder: @escaping () -> Void,
        onCloseFolder: @escaping (FolderTabID) -> Void,
        onMoveFolder: @escaping (FolderTabID, Int) -> Void,
        onSetSortOrder: @escaping (PortalSortOrder) -> Void,
        onSetTint: @escaping (PortalTint) -> Void
    ) {
        self.portal = portal
        self.onAddFolder = onAddFolder
        self.onCloseFolder = onCloseFolder
        self.onMoveFolder = onMoveFolder
        self.onSetSortOrder = onSetSortOrder
        self.onSetTint = onSetTint
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView()
        root.userInterfaceLayoutDirection = .leftToRight

        contentSeparator.boxType = .separator
        contentSeparator.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentSeparator)

        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.distribution = .fill
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.frame = NSRect(x: 0, y: 0, width: 400, height: 1)
        documentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 12),
        ])
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            contentSeparator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentSeparator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentSeparator.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentSeparator.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        showCategory(selectedCategory)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSettingsContent()
    }

    func update(_ portal: Portal) {
        self.portal = portal
        guard isViewLoaded else { return }
        showCategory(selectedCategory)
    }

    func selectCategory(_ category: Category) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        showCategory(category)
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .left
        return label
    }

    private func actionButton(
        title: String,
        symbol: String?,
        bezelColor: NSColor,
        hasDestructiveAction: Bool = false,
        controlSize: NSControl.ControlSize = .small,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
        }
        button.bezelStyle = .glass
        button.tintProminence = .primary
        button.borderShape = .capsule
        button.controlSize = controlSize
        button.bezelColor = bezelColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.alternateSelectedControlTextColor,
            ]
        )
        button.hasDestructiveAction = hasDestructiveAction
        button.userInterfaceLayoutDirection = .leftToRight
        return button
    }

    private func preferenceIntroduction(title: String, detail: String) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return labels
    }

    private func addSection(
        title: String,
        accessory: NSView? = nil,
        card: PortalSettingsCardView
    ) {
        let label = sectionLabel(title)
        let header = NSView()
        header.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        var constraints = [
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ]
        if let accessory {
            header.addSubview(accessory)
            accessory.translatesAutoresizingMaskIntoConstraints = false
            constraints += [
                accessory.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
                accessory.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
                accessory.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            ]
        } else {
            constraints.append(label.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -10))
        }
        NSLayoutConstraint.activate(constraints)
        contentStack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        contentStack.setCustomSpacing(6, after: header)
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        contentStack.setCustomSpacing(18, after: card)
    }

    private func showCategory(_ category: Category) {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        folderListView = nil
        addFolderButton = nil
        sortOptionButtons = []
        tintOptionButtons = []

        switch category {
        case .general:
            addSection(
                title: NSLocalizedString("portal.settings.sorting", comment: "Sorting section"),
                card: PortalSettingsCardView(rows: [
                    preferenceIntroduction(
                        title: NSLocalizedString("portal.sort.title", comment: "Sort order"),
                        detail: NSLocalizedString(
                            "portal.settings.sort.description",
                            comment: "Sort order description"
                        )
                    ),
                    makeSortOptions(),
                ])
            )
        case .folders:
            let folderContent: NSView
            if portal.tabs.isEmpty {
                folderContent = PortalSettingsEmptyFolderRowView()
            } else {
                let folderListView = PortalSettingsFolderListView(
                    tabs: portal.tabs,
                    onRemove: onCloseFolder,
                    onMove: onMoveFolder
                )
                self.folderListView = folderListView
                folderContent = folderListView
            }
            let addButton = actionButton(
                title: NSLocalizedString("portal.settings.add_folder", comment: "Add folder"),
                symbol: "folder.badge.plus",
                bezelColor: .controlAccentColor,
                controlSize: .regular,
                action: #selector(addFolder)
            )
            let limitDescription = localizedFormat(
                "portal.settings.folder_limit",
                Portal.maximumTabCount
            )
            addButton.isEnabled = portal.tabs.count < Portal.maximumTabCount
            addButton.toolTip = limitDescription
            addButton.setAccessibilityHelp(limitDescription)
            addFolderButton = addButton
            let limitRow = preferenceIntroduction(
                title: localizedFormat(
                    "portal.settings.folder_count",
                    portal.tabs.count,
                    Portal.maximumTabCount
                ),
                detail: limitDescription
            )
            limitRow.identifier = NSUserInterfaceItemIdentifier(
                "portal-settings.folder-limit"
            )
            addSection(
                title: NSLocalizedString("portal.settings.folders", comment: "Folders section"),
                accessory: addButton,
                card: PortalSettingsCardView(rows: [limitRow, folderContent])
            )
        case .style:
            addSection(
                title: NSLocalizedString("portal.settings.appearance", comment: "Appearance section"),
                card: PortalSettingsCardView(rows: [
                    preferenceIntroduction(
                        title: NSLocalizedString("portal.settings.tint", comment: "Panel tint"),
                        detail: NSLocalizedString(
                            "portal.settings.tint.description",
                            comment: "Panel tint description"
                        )
                    ),
                    makeTintOptions(),
                ])
            )
        }
        layoutSettingsContent()
    }

    private func makeSortOptions() -> NSStackView {
        sortOptionButtons = PortalSortOrder.allCases.enumerated().map { index, sortOrder in
            let button = NSButton(
                radioButtonWithTitle: sortOrderTitle(sortOrder),
                target: self,
                action: #selector(changeSortOrder(_:))
            )
            button.tag = index
            button.state = sortOrder == portal.sortOrder ? .on : .off
            button.setAccessibilityRole(.radioButton)
            button.identifier = NSUserInterfaceItemIdentifier(
                "portal-settings.sort-order.\(sortOrder.rawValue)"
            )
            return button
        }
        let options = NSStackView(views: sortOptionButtons)
        options.orientation = .horizontal
        options.alignment = .centerY
        options.distribution = .fillEqually
        options.spacing = 8
        options.edgeInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        return options
    }

    private func makeTintOptions() -> NSStackView {
        tintOptionButtons = PortalTint.allCases.enumerated().map { index, tint in
            let button = PortalTintSwatchButton(
                tint: tint,
                title: tintTitle(tint),
                target: self,
                action: #selector(changeTint(_:))
            )
            button.tag = index
            button.setSelected(tint == portal.tint)
            return button
        }
        let options = NSStackView(views: tintOptionButtons)
        options.orientation = .horizontal
        options.alignment = .centerY
        options.distribution = .equalSpacing
        options.spacing = 8
        options.edgeInsets = NSEdgeInsets(top: 7, left: 2, bottom: 7, right: 2)
        return options
    }

    func reorderFolder(_ id: FolderTabID, to targetIndex: Int) {
        guard let sourceIndex = portal.tabs.firstIndex(where: { $0.id == id }),
              portal.tabs.indices.contains(targetIndex),
              sourceIndex != targetIndex else {
            return
        }
        onMoveFolder(id, targetIndex)
    }

    private func layoutSettingsContent() {
        let verticalInset: CGFloat = 12
        let viewportWidth = scrollView.contentSize.width
        guard viewportWidth > 0 else { return }

        documentView.frame.size.width = viewportWidth
        documentView.layoutSubtreeIfNeeded()
        let contentHeight = contentStack.fittingSize.height
        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: viewportWidth,
            height: contentHeight + verticalInset * 2
        )
        documentView.layoutSubtreeIfNeeded()
    }

    @objc private func addFolder() {
        guard portal.tabs.count < Portal.maximumTabCount else { return }
        onAddFolder()
    }

    @objc private func changeSortOrder(_ sender: NSButton) {
        guard PortalSortOrder.allCases.indices.contains(sender.tag) else { return }
        sortOptionButtons.forEach { $0.state = $0 === sender ? .on : .off }
        onSetSortOrder(PortalSortOrder.allCases[sender.tag])
    }

    @objc private func changeTint(_ sender: PortalTintSwatchButton) {
        guard PortalTint.allCases.indices.contains(sender.tag) else { return }
        tintOptionButtons.forEach { $0.setSelected($0 === sender) }
        onSetTint(PortalTint.allCases[sender.tag])
    }

    private func sortOrderTitle(_ sortOrder: PortalSortOrder) -> String {
        switch sortOrder {
        case .name: NSLocalizedString("portal.sort.name", comment: "Sort by name")
        case .modificationDate:
            NSLocalizedString("portal.sort.modification_date", comment: "Sort by modification date")
        case .creationDate:
            NSLocalizedString("portal.sort.creation_date", comment: "Sort by creation date")
        }
    }

    private func tintTitle(_ tint: PortalTint) -> String {
        switch tint {
        case .default: NSLocalizedString("portal.tint.default", comment: "Default tint")
        case .red: NSLocalizedString("portal.tint.red", comment: "Red tint")
        case .orange: NSLocalizedString("portal.tint.orange", comment: "Orange tint")
        case .yellow: NSLocalizedString("portal.tint.yellow", comment: "Yellow tint")
        case .green: NSLocalizedString("portal.tint.green", comment: "Green tint")
        case .blue: NSLocalizedString("portal.tint.blue", comment: "Blue tint")
        case .indigo: NSLocalizedString("portal.tint.indigo", comment: "Indigo tint")
        case .purple: NSLocalizedString("portal.tint.purple", comment: "Purple tint")
        }
    }
}

@MainActor
final class PortalSettingsEmptyFolderRowView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: nil
        ) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor

        let label = NSTextField(labelWithString: NSLocalizedString(
            "portal.settings.folders.empty",
            comment: "Empty folder list guidance"
        ))
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(label.stringValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class PortalSettingsContentStackView: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class PortalSettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
