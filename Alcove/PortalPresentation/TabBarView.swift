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
    var onMoveTab: ((FolderTabID, PortalTabMoveDirection) -> Void)?
    var onRemovePortal: (() -> Void)?
    var onSetPinned: ((Bool) -> Void)?

    private(set) var groupBackdropView = PortalTabGroupBackdropView()
    let groupMaterialView: PortalChromeMaterialView
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
        groupMaterialView = PortalChromeMaterialView(
            contentView: NSView(),
            role: .controlGroup
        )
        super.init(frame: frameRect)
        configureView()
    }

    override func layout() {
        super.layout()
        let reservedSideWidth: CGFloat = 52
        let maximumGroupWidth = max(1, bounds.width - reservedSideWidth * 2)
        let groupWidth = min(stackView.fittingSize.width + 16, maximumGroupWidth)
        let groupFrame = NSRect(
            x: bounds.midX - groupWidth / 2,
            y: 2,
            width: groupWidth,
            height: max(1, bounds.height - 4)
        )
        groupBackdropView.frame = groupFrame
        groupMaterialView.frame = groupFrame
        groupMaterialView.materialView?.frame = groupMaterialView.bounds
        scrollView.frame = groupFrame.insetBy(dx: 8, dy: 3)

        let viewportSize = scrollView.contentSize
        let fittingSize = stackView.fittingSize
        stackView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: max(viewportSize.width, fittingSize.width),
                height: max(viewportSize.height, fittingSize.height)
            )
        )
        groupMaterialView.layoutSubtreeIfNeeded()
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

        addSubview(groupMaterialView)
        addSubview(groupBackdropView)
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
            onMoveFolder: { [weak self] id, direction in self?.onMoveTab?(id, direction) },
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
    private var portal: Portal

    init(
        portal: Portal,
        onAddFolder: @escaping () -> Void,
        onCloseFolder: @escaping (FolderTabID) -> Void,
        onMoveFolder: @escaping (FolderTabID, PortalTabMoveDirection) -> Void,
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 544),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = settingsViewController
        window.setContentSize(NSSize(width: 400, height: 544))
        window.title = NSLocalizedString("portal.settings.title", comment: "Portal settings title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        shouldCascadeWindows = false
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
    }

    private var portal: Portal
    private let onAddFolder: () -> Void
    private let onCloseFolder: (FolderTabID) -> Void
    private let onMoveFolder: (FolderTabID, PortalTabMoveDirection) -> Void
    private let onSetIconSize: (IconSize) -> Void
    private let onSetBackgroundStyle: (PortalBackgroundStyle) -> Void
    private let onRemovePortal: () -> Void
    private(set) var selectedCategory = Category.folders
    private(set) var categoryButtons: [Category: PortalSettingsCategoryButton] = [:]
    private(set) var separatorView = NSBox()
    private let scrollView = NSScrollView()
    private let contentStack = PortalSettingsContentStackView()
    private var actionTargets: [PortalSettingsActionTarget] = []

    init(
        portal: Portal,
        onAddFolder: @escaping () -> Void,
        onCloseFolder: @escaping (FolderTabID) -> Void,
        onMoveFolder: @escaping (FolderTabID, PortalTabMoveDirection) -> Void,
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
        let navigationView = NSView()
        navigationView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(navigationView)

        let buttons = Category.allCases.map { category in
            let button = PortalSettingsCategoryButton(category: category)
            button.target = self
            button.action = #selector(selectCategory(_:))
            button.tag = category.rawValue
            categoryButtons[category] = button
            return button
        }
        let navigationStack = NSStackView(views: buttons)
        navigationStack.orientation = .horizontal
        navigationStack.alignment = .centerY
        navigationStack.spacing = 12
        navigationStack.translatesAutoresizingMaskIntoConstraints = false
        navigationView.addSubview(navigationStack)

        separatorView.boxType = .separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(separatorView)

        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 14
        contentStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        contentStack.frame = NSRect(x: 0, y: 0, width: 400, height: 460)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.documentView = contentStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            navigationView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            navigationView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            navigationView.topAnchor.constraint(equalTo: root.topAnchor),
            navigationView.heightAnchor.constraint(equalToConstant: 64),
            navigationStack.centerXAnchor.constraint(equalTo: navigationView.centerXAnchor),
            navigationStack.centerYAnchor.constraint(equalTo: navigationView.centerYAnchor),
            separatorView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separatorView.topAnchor.constraint(equalTo: navigationView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separatorView.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        updateCategoryButtons()
        showCategory(selectedCategory)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let viewport = scrollView.contentSize
        let height = max(viewport.height, contentStack.fittingSize.height)
        contentStack.frame = NSRect(x: 0, y: 0, width: viewport.width, height: height)
    }

    func update(_ portal: Portal) {
        self.portal = portal
        guard isViewLoaded else { return }
        showCategory(selectedCategory)
    }

    @objc private func selectCategory(_ sender: NSButton) {
        guard let category = Category(rawValue: sender.tag) else { return }
        selectedCategory = category
        updateCategoryButtons()
        showCategory(category)
    }

    private func updateCategoryButtons() {
        for (category, button) in categoryButtons {
            button.setSelected(category == selectedCategory)
        }
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func actionButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.alignment = .left
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        return button
    }

    private func styleRow(title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return row
    }

    private func showCategory(_ category: Category) {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        actionTargets.removeAll(keepingCapacity: true)

        switch category {
        case .folders:
            contentStack.addArrangedSubview(sectionLabel(
                NSLocalizedString("portal.settings.folders", comment: "Folders section")
            ))
            var folderRows = portal.tabs.enumerated().map { index, tab in
                folderRow(tab: tab, index: index, count: portal.tabs.count)
            }
            folderRows.append(actionButton(
                title: NSLocalizedString("portal.settings.add_folder", comment: "Add folder"),
                symbol: "folder.badge.plus",
                action: #selector(addFolder)
            ))
            contentStack.addArrangedSubview(PortalSettingsCardView(rows: folderRows))
            contentStack.addArrangedSubview(sectionLabel(
                NSLocalizedString("portal.settings.panel", comment: "Panel settings section")
            ))
            let removeButton = actionButton(
                title: NSLocalizedString("portal.settings.remove_portal", comment: "Remove portal"),
                symbol: "trash",
                action: #selector(removePortal)
            )
            removeButton.contentTintColor = .systemRed
            contentStack.addArrangedSubview(PortalSettingsCardView(rows: [removeButton]))
        case .style:
            contentStack.addArrangedSubview(sectionLabel(
                NSLocalizedString("portal.settings.icon_size", comment: "Icon size section")
            ))
            contentStack.addArrangedSubview(PortalSettingsCardView(rows: [
                styleRow(
                    title: NSLocalizedString("portal.settings.size", comment: "Size setting"),
                    control: iconSizeSlider()
                ),
            ]))
            contentStack.addArrangedSubview(sectionLabel(
                NSLocalizedString("portal.settings.appearance", comment: "Appearance section")
            ))
            contentStack.addArrangedSubview(PortalSettingsCardView(rows: [
                styleRow(
                    title: NSLocalizedString(
                        "portal.settings.background",
                        comment: "Background setting"
                    ),
                    control: backgroundSlider()
                ),
            ]))
        }
        view.needsLayout = true
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

    private func folderRow(tab: FolderTab, index: Int, count: Int) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let label = NSTextField(labelWithString: tab.folderURL.lastPathComponent)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let moveUp = iconActionButton(
            symbol: "chevron.up",
            label: NSLocalizedString("portal.settings.move_up", comment: "Move folder up"),
            enabled: index > 0
        ) { [onMoveFolder] in
            onMoveFolder(tab.id, .up)
        }
        let moveDown = iconActionButton(
            symbol: "chevron.down",
            label: NSLocalizedString("portal.settings.move_down", comment: "Move folder down"),
            enabled: index < count - 1
        ) { [onMoveFolder] in
            onMoveFolder(tab.id, .down)
        }
        let remove = iconActionButton(
            symbol: "trash",
            label: NSLocalizedString("portal.settings.remove_folder_action", comment: "Remove folder"),
            enabled: true
        ) { [onCloseFolder] in
            onCloseFolder(tab.id)
        }
        remove.contentTintColor = .systemRed

        let row = NSStackView(views: [icon, label, moveUp, moveDown, remove])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return row
    }

    private func iconActionButton(
        symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let target = PortalSettingsActionTarget(action: action)
        actionTargets.append(target)
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.target = target
        button.action = #selector(PortalSettingsActionTarget.performAction(_:))
        button.isEnabled = enabled
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
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
private final class PortalSettingsContentStackView: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
final class PortalSettingsCategoryButton: NSButton {
    let category: PortalSettingsViewController.Category

    init(category: PortalSettingsViewController.Category) {
        self.category = category
        super.init(frame: .zero)
        title = category.title
        image = NSImage(
            systemSymbolName: category.symbol,
            accessibilityDescription: category.title
        )
        imagePosition = .imageAbove
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        widthAnchor.constraint(equalToConstant: 68).isActive = true
        heightAnchor.constraint(equalToConstant: 56).isActive = true
        setAccessibilityLabel(category.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setSelected(_ selected: Bool) {
        state = selected ? .on : .off
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentTintColor = state == .on ? .controlAccentColor : .secondaryLabelColor
            layer?.backgroundColor = state == .on
                ? NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
                : NSColor.clear.cgColor
        }
    }
}

@MainActor
private final class PortalSettingsActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction(_ sender: Any?) {
        action()
    }
}

@MainActor
private final class PortalSettingsCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    init(rows: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12

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
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor
                .withAlphaComponent(0.68)
                .cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        }
    }
}

@MainActor
final class PortalTabGroupBackdropView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 999
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor
                .withAlphaComponent(0.55)
                .cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.separatorColor.cgColor
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
