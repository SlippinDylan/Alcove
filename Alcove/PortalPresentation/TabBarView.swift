import AlcoveCore
import AppKit

private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(
        format: NSLocalizedString(key, comment: ""),
        locale: Locale.current,
        arguments: arguments
    )
}

@MainActor
final class TabBarView: NSView {
    var onSelect: ((FolderTabID) -> Void)?
    var onClose: ((FolderTabID) -> Void)?
    var onAdd: (() -> Void)?
    var onSetBackgroundStyle: ((PortalBackgroundStyle) -> Void)?
    var onSetIconSize: ((IconSize) -> Void)?
    var onMoveTab: ((FolderTabID, Int) -> Void)?
    var onRemovePortal: (() -> Void)?
    var onSetPinned: ((Bool) -> Void)?

    private(set) var scrollView = NSScrollView()
    private let stackView = NSStackView()
    private(set) var managementButton = NSButton()
    private(set) var pinButton = NSButton()
    private(set) var settingsWindowController: PortalSettingsWindowController?
    private var actionTargets: [TabActionTarget] = []
    private var portal: Portal?

    private(set) var tabOrder: [FolderTabID] = []
    private(set) var selectedTabID: FolderTabID?
    private(set) var tabButtons: [FolderTabID: PortalTabButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    override func layout() {
        super.layout()
        let reservedSideWidth: CGFloat = 52
        let maximumGroupWidth = max(1, bounds.width - reservedSideWidth * 2)
        let groupWidth = min(stackView.fittingSize.width, maximumGroupWidth)
        let tabFrame = NSRect(
            x: bounds.midX - groupWidth / 2,
            y: 6,
            width: groupWidth,
            height: max(1, bounds.height - 12)
        )
        scrollView.frame = tabFrame

        let viewportSize = scrollView.contentSize
        let fittingSize = stackView.fittingSize
        stackView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: max(viewportSize.width, fittingSize.width),
                height: max(viewportSize.height, fittingSize.height)
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateManagementButtonAppearance()
    }

    func configure(with portal: Portal) {
        update(with: portal)
    }

    func update(with portal: Portal) {
        self.portal = portal
        updatePinButton(for: portal)
        tabOrder = portal.tabs.map(\.id)
        selectedTabID = portal.selectedTabID
        tabButtons.removeAll(keepingCapacity: true)
        actionTargets.removeAll(keepingCapacity: true)

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for tab in portal.tabs {
            stackView.addArrangedSubview(
                makeTabButton(for: tab, selected: tab.id == portal.selectedTabID)
            )
        }
        stackView.frame = NSRect(origin: .zero, size: stackView.fittingSize)
        settingsWindowController?.update(portal)
        needsLayout = true
    }

    private func configureView() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 2

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.horizontalScroller?.controlSize = .mini
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = stackView

        addSubview(scrollView)

        pinButton.imageScaling = .scaleProportionallyDown
        pinButton.imagePosition = .imageOnly
        pinButton.isBordered = false
        pinButton.target = self
        pinButton.action = #selector(togglePinned)
        pinButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pinButton)

        managementButton.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: nil
        )
        managementButton.imageScaling = .scaleProportionallyDown
        managementButton.imagePosition = .imageOnly
        managementButton.isBordered = false
        managementButton.target = self
        managementButton.action = #selector(showSettingsWindow)
        managementButton.setAccessibilityLabel(
            NSLocalizedString("portal.settings.label", comment: "Portal settings")
        )
        managementButton.setAccessibilityHelp(
            NSLocalizedString(
                "portal.settings.help",
                comment: "Portal settings accessibility help"
            )
        )
        managementButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(managementButton)
        updateManagementButtonAppearance()

        NSLayoutConstraint.activate([
            pinButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 30),
            pinButton.heightAnchor.constraint(equalToConstant: 30),
            managementButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            managementButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            managementButton.widthAnchor.constraint(equalToConstant: 30),
            managementButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func makeTabButton(for tab: FolderTab, selected: Bool) -> PortalTabButton {
        let button = PortalTabButton(title: tab.folderURL.lastPathComponent)
        button.setAccessibilityRole(.radioButton)
        button.setSelected(selected)
        button.setAccessibilityLabel(localizedFormat(
            "portal.tab.select",
            tab.folderURL.lastPathComponent
        ))
        button.setAccessibilityHelp(
            NSLocalizedString("portal.tab.switch.help", comment: "Switch folder tab help")
        )

        let target = TabActionTarget(action: .select(tab.id), owner: self)
        button.target = target
        button.action = #selector(TabActionTarget.performAction(_:))
        actionTargets.append(target)
        tabButtons[tab.id] = button
        return button
    }

    private func updateManagementButtonAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            managementButton.contentTintColor = activeLabelColor
            pinButton.contentTintColor = activeLabelColor
        }
    }

    private var activeLabelColor: NSColor {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .white
            : .black
    }

    @objc private func showSettingsWindow() {
        guard let portal else { return }
        let controller = settingsWindowController ?? makeSettingsWindowController(for: portal)
        settingsWindowController = controller
        controller.update(portal)
        controller.present(on: window?.screen)
    }

    @objc private func togglePinned() {
        guard let portal else { return }
        onSetPinned?(!portal.isPinned)
    }

    private func updatePinButton(for portal: Portal) {
        let title = portal.isPinned
            ? NSLocalizedString("portal.pin.unpin", comment: "Unpin a portal")
            : NSLocalizedString("portal.pin.pin", comment: "Pin a portal")
        pinButton.image = NSImage(
            systemSymbolName: portal.isPinned ? "pin.fill" : "pin",
            accessibilityDescription: nil
        )
        pinButton.setAccessibilityLabel(title)
        pinButton.setAccessibilityHelp(
            portal.isPinned
                ? NSLocalizedString(
                    "portal.pin.unpin.help",
                    comment: "Accessibility help for unpinning a portal"
                )
                : NSLocalizedString(
                    "portal.pin.pin.help",
                    comment: "Accessibility help for pinning a portal"
                )
        )
        pinButton.toolTip = title
    }

    private func makeSettingsWindowController(
        for portal: Portal
    ) -> PortalSettingsWindowController {
        PortalSettingsWindowController(
            portal: portal,
            onAddFolder: { [weak self] in self?.onAdd?() },
            onCloseFolder: { [weak self] id in self?.onClose?(id) },
            onMoveFolder: { [weak self] id, index in self?.onMoveTab?(id, index) },
            onSetIconSize: { [weak self] size in self?.onSetIconSize?(size) },
            onSetBackgroundStyle: { [weak self] style in
                self?.onSetBackgroundStyle?(style)
            },
            onRemovePortal: { [weak self] in self?.onRemovePortal?() }
        )
    }

    func closeSettingsWindow() {
        settingsWindowController?.close()
    }

    fileprivate func selectTab(_ id: FolderTabID) {
        guard tabButtons[id] != nil else { return }
        onSelect?(id)
    }

}

@MainActor
final class PortalSettingsWindowController: NSWindowController {
    private(set) var settingsViewController: PortalSettingsViewController
    private(set) var categoryItems: [PortalSettingsViewController.Category: NSToolbarItem] = [:]
    private let settingsToolbar = NSToolbar(identifier: "portal-settings")
    private var portal: Portal

    init(
        portal: Portal,
        onAddFolder: @escaping () -> Void,
        onCloseFolder: @escaping (FolderTabID) -> Void,
        onMoveFolder: @escaping (FolderTabID, Int) -> Void,
        onSetIconSize: @escaping (IconSize) -> Void,
        onSetBackgroundStyle: @escaping (PortalBackgroundStyle) -> Void,
        onRemovePortal: @escaping () -> Void
    ) {
        self.portal = portal
        let settingsViewController = PortalSettingsViewController(
            portal: portal,
            onAddFolder: onAddFolder,
            onCloseFolder: onCloseFolder,
            onMoveFolder: onMoveFolder,
            onSetIconSize: onSetIconSize,
            onSetBackgroundStyle: onSetBackgroundStyle,
            onRemovePortal: onRemovePortal
        )
        self.settingsViewController = settingsViewController
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = settingsViewController
        window.setContentSize(NSSize(width: 400, height: 450))
        window.title = ""
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        shouldCascadeWindows = false
        configureToolbar(for: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(_ portal: Portal) {
        guard self.portal != portal else { return }
        self.portal = portal
        settingsViewController.update(portal)
    }

    func selectCategory(_ category: PortalSettingsViewController.Category) {
        settingsToolbar.selectedItemIdentifier = category.toolbarItemIdentifier
        settingsViewController.selectCategory(category)
    }

    func present(on screen: NSScreen?) {
        guard let window else { return }
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let visibleFrame {
            window.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.midX - window.frame.width / 2,
                    y: visibleFrame.midY - window.frame.height / 2
                )
            )
        } else {
            window.center()
        }
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureToolbar(for window: NSWindow) {
        settingsToolbar.delegate = self
        settingsToolbar.displayMode = .iconAndLabel
        settingsToolbar.allowsUserCustomization = false
        settingsToolbar.autosavesConfiguration = false
        window.toolbarStyle = .preference
        window.toolbar = settingsToolbar
        window.titlebarSeparatorStyle = .none
        settingsToolbar.selectedItemIdentifier = PortalSettingsViewController.Category.folders
            .toolbarItemIdentifier
    }

}

extension PortalSettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PortalSettingsViewController.Category.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let category = PortalSettingsViewController.Category(
            toolbarItemIdentifier: itemIdentifier
        ) else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = category.title
        item.paletteLabel = category.title
        item.toolTip = category.title
        item.image = NSImage(
            systemSymbolName: category.symbol,
            accessibilityDescription: category.title
        )?.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        item.target = self
        item.action = #selector(selectToolbarCategory(_:))
        item.tag = category.rawValue
        item.isBordered = false
        categoryItems[category] = item
        return item
    }

    @objc private func selectToolbarCategory(_ sender: NSToolbarItem) {
        guard let category = PortalSettingsViewController.Category(rawValue: sender.tag) else {
            return
        }
        selectCategory(category)
    }
}

@MainActor
final class PortalSettingsViewController: NSViewController {
    enum Category: Int, CaseIterable {
        case folders
        case style

        var title: String {
            switch self {
            case .folders:
                NSLocalizedString("portal.settings.folders", comment: "Folders settings category")
            case .style:
                NSLocalizedString("portal.settings.style", comment: "Style settings category")
            }
        }

        var symbol: String {
            switch self {
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
    private let onSetIconSize: (IconSize) -> Void
    private let onSetBackgroundStyle: (PortalBackgroundStyle) -> Void
    private let onRemovePortal: () -> Void
    private(set) var selectedCategory = Category.folders
    private(set) var contentSeparator = NSBox()
    private(set) var scrollView = NSScrollView()
    private(set) var contentStack: NSStackView = PortalSettingsContentStackView()
    private(set) var folderListView: PortalSettingsFolderListView?
    private let documentView = PortalSettingsDocumentView()

    init(
        portal: Portal,
        onAddFolder: @escaping () -> Void,
        onCloseFolder: @escaping (FolderTabID) -> Void,
        onMoveFolder: @escaping (FolderTabID, Int) -> Void,
        onSetIconSize: @escaping (IconSize) -> Void,
        onSetBackgroundStyle: @escaping (PortalBackgroundStyle) -> Void,
        onRemovePortal: @escaping () -> Void
    ) {
        self.portal = portal
        self.onAddFolder = onAddFolder
        self.onCloseFolder = onCloseFolder
        self.onMoveFolder = onMoveFolder
        self.onSetIconSize = onSetIconSize
        self.onSetBackgroundStyle = onSetBackgroundStyle
        self.onRemovePortal = onRemovePortal
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
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
            button.tintProminence = .primary
            button.borderShape = .capsule
        } else {
            button.bezelStyle = .rounded
        }
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

    private func styleRow(title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .left
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 12
        row.userInterfaceLayoutDirection = .leftToRight
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
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

        switch category {
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
            addSection(
                title: NSLocalizedString("portal.settings.folders", comment: "Folders section"),
                accessory: addButton,
                card: PortalSettingsCardView(rows: [folderContent])
            )
            addSection(
                title: NSLocalizedString("portal.settings.panel", comment: "Panel settings section"),
                card: PortalSettingsCardView(rows: [removePortalRow()])
            )
        case .style:
            break
        }
        layoutSettingsContent()
    }

    private func iconSizeSlider() -> NSSlider {
        let sizes: [IconSize] = [.small, .medium, .large]
        let selectedIndex = sizes.enumerated().min { lhs, rhs in
            abs(lhs.element.rawValue - portal.iconSize.rawValue)
                < abs(rhs.element.rawValue - portal.iconSize.rawValue)
        }?.offset ?? 1
        let slider = discreteSlider(
            identifier: "portal-settings.icon-size",
            value: selectedIndex,
            maximum: sizes.count - 1,
            action: #selector(changeIconSize(_:))
        )
        slider.setAccessibilityLabel(
            NSLocalizedString("portal.settings.icon_size", comment: "Icon size slider")
        )
        slider.setAccessibilityValue(iconSizeTitle(sizes[selectedIndex]))
        return slider
    }

    private func backgroundSlider() -> NSSlider {
        let styles = PortalBackgroundStyle.allCases
        let slider = discreteSlider(
            identifier: "portal-settings.background",
            value: styles.firstIndex(of: portal.backgroundStyle) ?? 2,
            maximum: styles.count - 1,
            action: #selector(changeBackground(_:))
        )
        slider.setAccessibilityLabel(
            NSLocalizedString("portal.settings.background", comment: "Background slider")
        )
        slider.setAccessibilityValue(backgroundStyleTitle(styles[Int(slider.doubleValue)]))
        return slider
    }

    private func discreteSlider(
        identifier: String,
        value: Int,
        maximum: Int,
        action: Selector
    ) -> NSSlider {
        let slider = NSSlider(
            value: Double(value),
            minValue: 0,
            maxValue: Double(maximum),
            target: self,
            action: action
        )
        slider.identifier = NSUserInterfaceItemIdentifier(identifier)
        slider.numberOfTickMarks = maximum + 1
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return slider
    }

    private func removePortalRow() -> NSView {
        let title = NSTextField(labelWithString: NSLocalizedString(
            "portal.settings.remove_portal_title",
            comment: "Remove portal setting title"
        ))
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let detail = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "portal.settings.remove_portal_detail",
            comment: "Remove portal setting detail"
        ))
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = actionButton(
            title: NSLocalizedString("portal.settings.remove_portal", comment: "Remove portal"),
            symbol: nil,
            bezelColor: .systemRed,
            hasDestructiveAction: true,
            action: #selector(removePortal)
        )
        let row = NSStackView(views: [labels, button])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
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
        onAddFolder()
    }

    @objc private func changeIconSize(_ sender: NSSlider) {
        let sizes: [IconSize] = [.small, .medium, .large]
        let index = Int(sender.doubleValue.rounded())
        guard sizes.indices.contains(index) else { return }
        sender.setAccessibilityValue(iconSizeTitle(sizes[index]))
        onSetIconSize(sizes[index])
    }

    @objc private func changeBackground(_ sender: NSSlider) {
        let styles = PortalBackgroundStyle.allCases
        let index = Int(sender.doubleValue.rounded())
        guard styles.indices.contains(index) else { return }
        sender.setAccessibilityValue(backgroundStyleTitle(styles[index]))
        onSetBackgroundStyle(styles[index])
    }

    private func iconSizeTitle(_ iconSize: IconSize) -> String {
        switch iconSize {
        case .small: NSLocalizedString("portal.settings.small", comment: "Small icon size")
        case .medium: NSLocalizedString("portal.settings.medium", comment: "Medium icon size")
        case .large: NSLocalizedString("portal.settings.large", comment: "Large icon size")
        default: NSLocalizedString("portal.settings.medium", comment: "Medium icon size")
        }
    }

    private func backgroundStyleTitle(_ style: PortalBackgroundStyle) -> String {
        switch style {
        case .maximumTransparency:
            NSLocalizedString("portal.settings.maximum_transparency", comment: "Maximum transparency")
        case .highTransparency:
            NSLocalizedString("portal.settings.high_transparency", comment: "High transparency")
        case .standard:
            NSLocalizedString("portal.settings.standard", comment: "Standard background")
        case .lowTransparency:
            NSLocalizedString("portal.settings.low_transparency", comment: "Low transparency")
        case .minimumTransparency:
            NSLocalizedString("portal.settings.minimum_transparency", comment: "Minimum transparency")
        }
    }

    @objc private func removePortal() {
        onRemovePortal()
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

@MainActor
private final class PortalSettingsCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    init(rows: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        setContentHuggingPriority(.required, for: .vertical)

        var arrangedViews: [NSView] = []
        for (index, row) in rows.enumerated() {
            arrangedViews.append(row)
            if index < rows.count - 1 {
                let separator = NSBox()
                separator.boxType = .separator
                arrangedViews.append(separator)
            }
        }
        let stack = NSStackView(views: arrangedViews)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        }
    }

}

@MainActor
final class PortalTabButton: NSButton {
    private(set) var isTabSelected = false

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        setButtonType(.momentaryPushIn)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 14
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 24, height: 28)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setSelected(_ selected: Bool) {
        let didChange = isTabSelected != selected
        isTabSelected = selected
        setAccessibilitySelected(selected)
        setAccessibilityValue(NSNumber(value: selected))
        updateAppearance()
        if didChange {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let foreground = activeLabelColor
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: NSFont.systemFontSize,
                        weight: isTabSelected ? .semibold : .regular
                    ),
                    .foregroundColor: foreground,
                ]
            )
            layer?.backgroundColor = isTabSelected
                ? foreground.withAlphaComponent(0.13).cgColor
                : NSColor.clear.cgColor
            layer?.borderWidth = isTabSelected ? 0.5 : 0
            layer?.borderColor = foreground.withAlphaComponent(0.12).cgColor
        }
    }

    private var activeLabelColor: NSColor {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .white
            : .black
    }
}

@MainActor
private final class TabActionTarget: NSObject {
    enum Action {
        case select(FolderTabID)
    }

    private let action: Action
    private weak var owner: TabBarView?

    init(action: Action, owner: TabBarView) {
        self.action = action
        self.owner = owner
    }

    @objc func performAction(_ sender: Any?) {
        switch action {
        case .select(let id):
            owner?.selectTab(id)
        }
    }
}
