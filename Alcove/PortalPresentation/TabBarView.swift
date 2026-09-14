import AlcoveCore
import AppKit

private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(
        format: NSLocalizedString(key, comment: ""),
        locale: Locale.current,
        arguments: arguments
    )
}

enum PortalRemovalConfirmationGeometry {
    static func centeredOrigin(windowSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
    }
}

struct PortalCapsuleMetrics: Equatable {
    let tabWidth: CGFloat
    let height: CGFloat
    let controlSize: NSControl.ControlSize

    init(iconSize: IconSize) {
        switch iconSize {
        case .small:
            tabWidth = 76
            height = 26
            controlSize = .small
        case .large:
            tabWidth = 92
            height = 30
            controlSize = .large
        default:
            tabWidth = 84
            height = 28
            controlSize = .regular
        }
    }
}

@MainActor
final class TabBarView: NSView {
    var onSelect: ((FolderTabID) -> Void)?
    var onClose: ((FolderTabID) -> Void)?
    var onAdd: (() -> Void)?
    var onMoveTab: ((FolderTabID, Int) -> Void)?
    var onRemovePortal: (() -> Void)?
    var onSetPinned: ((Bool) -> Void)?
    var onSetSortOrder: ((PortalSortOrder) -> Void)?
    var onSetTint: ((PortalTint) -> Void)?
    var onNavigateBack: (() -> Void)?
    var removalConfirmationPresenter: ((NSWindow?, @escaping (Bool) -> Void) -> Void) = {
        window, completion in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(
            "portal.remove.confirm.title",
            comment: "Remove portal confirmation title"
        )
        alert.informativeText = NSLocalizedString(
            "portal.remove.confirm.detail",
            comment: "Remove portal confirmation detail"
        )
        alert.addButton(withTitle: NSLocalizedString(
            "portal.remove.confirm.action",
            comment: "Remove portal confirmation action"
        ))
        alert.addButton(withTitle: NSLocalizedString("action.cancel", comment: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.layout()
        if let visibleFrame = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            alert.window.setFrameOrigin(PortalRemovalConfirmationGeometry.centeredOrigin(
                windowSize: alert.window.frame.size,
                visibleFrame: visibleFrame
            ))
        }
        completion(alert.runModal() == .alertFirstButtonReturn)
    }

    private(set) var scrollView = NSScrollView()
    private let stackView = NSStackView()
    private(set) var managementButton = NSButton()
    private(set) var backButton = PortalFlatCapsuleButton()
    private(set) var managementMenu: NSMenu?
    private(set) var settingsWindowController: PortalSettingsWindowController?
    private(set) var isUsingScrollableTabStrip = true
    private var actionTargets: [TabActionTarget] = []
    private var portal: Portal?
    private var capsuleMetrics = PortalCapsuleMetrics(iconSize: .medium)
    private var shouldRevealSelectedTab = false

    private(set) var tabOrder: [FolderTabID] = []
    private(set) var selectedTabID: FolderTabID?
    private(set) var tabButtons: [FolderTabID: PortalTabButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    override func layout() {
        super.layout()
        let backButtonWidth = backButton.isHidden ? 0 : backButton.fittingSize.width + 16
        let reservedSideWidth = max(52, backButtonWidth)
        let maximumGroupWidth = max(1, bounds.width - reservedSideWidth * 2)
        let fittingSize = stackView.fittingSize
        let needsScrolling = fittingSize.width > maximumGroupWidth
        isUsingScrollableTabStrip = needsScrolling
        scrollView.hasHorizontalScroller = needsScrolling
        let groupWidth = min(fittingSize.width, maximumGroupWidth)
        scrollView.frame = NSRect(
            x: bounds.midX - groupWidth / 2,
            y: 0,
            width: groupWidth,
            height: max(1, bounds.height)
        )
        let viewportSize = scrollView.contentSize
        stackView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: max(viewportSize.width, fittingSize.width),
                height: max(viewportSize.height, fittingSize.height)
            )
        )
        if shouldRevealSelectedTab {
            stackView.layoutSubtreeIfNeeded()
            if needsScrolling, let selectedTabID, let selectedButton = tabButtons[selectedTabID] {
                scrollView.contentView.scrollToVisible(selectedButton.frame)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            shouldRevealSelectedTab = false
        }
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
        capsuleMetrics = PortalCapsuleMetrics(iconSize: portal.iconSize)
        backButton.apply(metrics: capsuleMetrics)
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
        shouldRevealSelectedTab = true
        settingsWindowController?.update(portal)
        needsLayout = true
    }

    func updateNavigation(canGoBack: Bool) {
        backButton.isHidden = !canGoBack
        needsLayout = true
    }

    private func configureView() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 2

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.hasHorizontalScroller = true
        scrollView.horizontalScroller?.controlSize = .mini
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = stackView

        addSubview(scrollView)

        backButton.title = NSLocalizedString("portal.navigation.back", comment: "Back")
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        backButton.imagePosition = .imageLeading
        backButton.imageHugsTitle = true
        backButton.target = self
        backButton.action = #selector(navigateBack)
        backButton.apply(metrics: capsuleMetrics)
        backButton.setAccessibilityLabel(
            NSLocalizedString("portal.navigation.back", comment: "Back")
        )
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.isHidden = true
        addSubview(backButton)

        managementButton.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: nil
        )
        managementButton.imageScaling = .scaleProportionallyDown
        managementButton.imagePosition = .imageOnly
        managementButton.isBordered = false
        managementButton.target = self
        managementButton.action = #selector(showManagementMenu)
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
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            managementButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            managementButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            managementButton.widthAnchor.constraint(equalToConstant: 30),
            managementButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @objc private func navigateBack() {
        onNavigateBack?()
    }

    private func makeTabButton(for tab: FolderTab, selected: Bool) -> PortalTabButton {
        let button = PortalTabButton(
            title: tab.folderURL.lastPathComponent,
            metrics: capsuleMetrics
        )
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
        }
    }

    private var activeLabelColor: NSColor {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .white
            : .black
    }

    @objc private func showManagementMenu() {
        let menu = makeManagementMenu()
        managementMenu = menu
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: managementButton.bounds.maxX, y: managementButton.bounds.minY),
            in: managementButton
        )
    }

    func makeManagementMenu() -> NSMenu {
        let menu = NSMenu()
        guard let portal else { return menu }

        let pinItem = NSMenuItem(
            title: portal.isPinned
                ? NSLocalizedString("portal.pin.unpin", comment: "Unpin a portal")
                : NSLocalizedString("portal.pin.pin", comment: "Pin a portal"),
            action: #selector(togglePinned),
            keyEquivalent: ""
        )
        pinItem.target = self
        pinItem.image = NSImage(
            systemSymbolName: portal.isPinned ? "pin.slash" : "pin",
            accessibilityDescription: nil
        )
        menu.addItem(pinItem)

        let sortMenu = NSMenu()
        for (index, sortOrder) in PortalSortOrder.allCases.enumerated() {
            let item = NSMenuItem(
                title: sortOrderTitle(sortOrder),
                action: #selector(selectSortOrder(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = sortOrder == portal.sortOrder ? .on : .off
            sortMenu.addItem(item)
        }
        let sortItem = NSMenuItem(
            title: NSLocalizedString("portal.sort.title", comment: "Sort submenu"),
            action: nil,
            keyEquivalent: ""
        )
        sortItem.submenu = sortMenu
        sortItem.image = NSImage(
            systemSymbolName: "arrow.up.arrow.down",
            accessibilityDescription: nil
        )
        menu.addItem(sortItem)

        let settingsItem = NSMenuItem(
            title: NSLocalizedString("portal.settings.open", comment: "Open panel settings"),
            action: #selector(showSettingsWindow),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: nil
        )
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let removeItem = NSMenuItem(
            title: NSLocalizedString("portal.remove.menu", comment: "Remove portal menu item"),
            action: #selector(confirmPortalRemoval),
            keyEquivalent: ""
        )
        removeItem.target = self
        removeItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(removeItem)
        return menu
    }

    @objc func showSettingsWindow() {
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

    @objc private func selectSortOrder(_ sender: NSMenuItem) {
        guard PortalSortOrder.allCases.indices.contains(sender.tag) else { return }
        onSetSortOrder?(PortalSortOrder.allCases[sender.tag])
    }

    @objc func confirmPortalRemoval() {
        removalConfirmationPresenter(window) { [weak self] confirmed in
            guard confirmed else { return }
            self?.onRemovePortal?()
        }
    }

    private func sortOrderTitle(_ sortOrder: PortalSortOrder) -> String {
        switch sortOrder {
        case .name:
            NSLocalizedString("portal.sort.name", comment: "Sort by name")
        case .modificationDate:
            NSLocalizedString("portal.sort.modification_date", comment: "Sort by modification date")
        case .creationDate:
            NSLocalizedString("portal.sort.creation_date", comment: "Sort by creation date")
        }
    }

    private func makeSettingsWindowController(
        for portal: Portal
    ) -> PortalSettingsWindowController {
        PortalSettingsWindowController(
            portal: portal,
            onAddFolder: { [weak self] in self?.onAdd?() },
            onCloseFolder: { [weak self] id in self?.onClose?(id) },
            onMoveFolder: { [weak self] id, index in self?.onMoveTab?(id, index) },
            onSetSortOrder: { [weak self] order in self?.onSetSortOrder?(order) },
            onSetTint: { [weak self] tint in self?.onSetTint?(tint) }
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
        onSetSortOrder: @escaping (PortalSortOrder) -> Void,
        onSetTint: @escaping (PortalTint) -> Void
    ) {
        self.portal = portal
        let settingsViewController = PortalSettingsViewController(
            portal: portal,
            onAddFolder: onAddFolder,
            onCloseFolder: onCloseFolder,
            onMoveFolder: onMoveFolder,
            onSetSortOrder: onSetSortOrder,
            onSetTint: onSetTint
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
        settingsToolbar.selectedItemIdentifier = PortalSettingsViewController.Category.general
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
            addSection(
                title: NSLocalizedString("portal.settings.folders", comment: "Folders section"),
                accessory: addButton,
                card: PortalSettingsCardView(rows: [folderContent])
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
final class PortalTintSwatchButton: NSButton {
    let tint: PortalTint
    private let optionTitle: String
    private(set) var isOptionSelected = false
    private(set) var swatchView = NSView()
    private(set) var checkmarkView = NSImageView()

    init(tint: PortalTint, title: String, target: AnyObject?, action: Selector?) {
        self.tint = tint
        optionTitle = title
        super.init(frame: .zero)
        self.title = ""
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        isBordered = false
        focusRingType = .none
        identifier = NSUserInterfaceItemIdentifier("portal-settings.tint.\(tint.rawValue)")
        toolTip = title
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)

        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 14
        swatchView.layer?.masksToBounds = true
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatchView)

        checkmarkView.imageScaling = .scaleProportionallyDown
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkmarkView)

        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        NSLayoutConstraint.activate([
            swatchView.centerXAnchor.constraint(equalTo: centerXAnchor),
            swatchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 28),
            swatchView.heightAnchor.constraint(equalToConstant: 28),
            checkmarkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 14),
            checkmarkView.heightAnchor.constraint(equalToConstant: 14),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 30)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setSelected(_ selected: Bool) {
        isOptionSelected = selected
        state = selected ? .on : .off
        setAccessibilitySelected(selected)
        setAccessibilityValue(NSNumber(value: selected))
        checkmarkView.image = selected
            ? NSImage(
                systemSymbolName: "checkmark",
                accessibilityDescription: optionTitle
            )?.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
            : nil
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            swatchView.layer?.backgroundColor = swatchColor.cgColor
            swatchView.layer?.borderWidth = isOptionSelected ? 3 : 1
            swatchView.layer?.borderColor = (isOptionSelected
                ? NSColor.controlAccentColor
                : NSColor.separatorColor).cgColor
            checkmarkView.contentTintColor = checkmarkColor
        }
    }

    private var swatchColor: NSColor {
        let isDarkAppearance = effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua
        let color = tint.resolvedColor(forDarkAppearance: isDarkAppearance)
        return NSColor(
            srgbRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: 1
        )
    }

    private var checkmarkColor: NSColor {
        switch tint {
        case .default, .orange, .yellow, .green:
            .labelColor
        case .red, .blue, .indigo, .purple:
            .white
        }
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
class PortalFlatCapsuleButton: NSButton {
    private var metrics = PortalCapsuleMetrics(iconSize: .medium)
    private var fixedWidth: CGFloat?
    private var pointerInside = false
    private var pointerTrackingArea: NSTrackingArea?
    private(set) var usesSelectedAppearance = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCapsule()
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        configureCapsule()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: fixedWidth ?? super.intrinsicContentSize.width + 20,
            height: metrics.height
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(activationStateDidChange),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(activationStateDidChange),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(activationStateDidChange),
                name: NSApplication.didBecomeActiveNotification,
                object: NSApplication.shared
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(activationStateDidChange),
                name: NSApplication.didResignActiveNotification,
                object: NSApplication.shared
            )
        }
        updateCapsuleAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateCapsuleAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        updateCapsuleAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        updateCapsuleAppearance()
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateCapsuleAppearance(isPressed: flag)
    }

    func apply(metrics: PortalCapsuleMetrics, fixedWidth: CGFloat? = nil) {
        self.metrics = metrics
        self.fixedWidth = fixedWidth
        controlSize = metrics.controlSize
        layer?.cornerRadius = metrics.height / 2
        invalidateIntrinsicContentSize()
        updateCapsuleAppearance()
    }

    func setCapsuleSelected(_ selected: Bool) {
        usesSelectedAppearance = selected
        updateCapsuleAppearance()
    }

    private func configureCapsule() {
        setButtonType(.momentaryPushIn)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = metrics.height / 2
        layer?.shadowOpacity = 0
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        updateCapsuleAppearance()
    }

    @objc private func activationStateDidChange() {
        updateCapsuleAppearance()
    }

    private func updateCapsuleAppearance(isPressed: Bool = false) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isEmphasized = window.map {
                NSApplication.shared.isActive && $0.isKeyWindow
            } ?? true
            let primaryForeground: NSColor = effectiveAppearance.bestMatch(
                from: [.darkAqua, .aqua]
            ) == .darkAqua ? .white : .black
            let baseBackground: NSColor
            let foreground: NSColor
            if usesSelectedAppearance {
                if isEmphasized {
                    baseBackground = .selectedContentBackgroundColor
                } else {
                    baseBackground = NSColor.unemphasizedSelectedContentBackgroundColor.blended(
                        withFraction: 0.10,
                        of: .labelColor
                    ) ?? .unemphasizedSelectedContentBackgroundColor
                }
                foreground = isEmphasized
                    ? .white
                    : .unemphasizedSelectedTextColor
            } else {
                baseBackground = .quaternarySystemFill
                foreground = primaryForeground
            }
            let background: NSColor
            if isPressed {
                background = baseBackground.blended(
                    withFraction: 0.16,
                    of: .labelColor
                ) ?? baseBackground
            } else if pointerInside {
                background = baseBackground.blended(
                    withFraction: 0.08,
                    of: .labelColor
                ) ?? baseBackground
            } else {
                background = baseBackground
            }
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: NSFont.systemFontSize(for: metrics.controlSize),
                        weight: usesSelectedAppearance ? .semibold : .regular
                    ),
                    .foregroundColor: foreground,
                ]
            )
            contentTintColor = foreground
            layer?.backgroundColor = background.cgColor
            layer?.borderWidth = usesSelectedAppearance
                ? (isEmphasized ? 0 : 1)
                : 0.5
            layer?.borderColor = usesSelectedAppearance && !isEmphasized
                ? NSColor.secondaryLabelColor.cgColor
                : NSColor.separatorColor.cgColor
            layer?.shadowOpacity = 0
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

@MainActor
final class PortalTabButton: PortalFlatCapsuleButton {
    private(set) var isTabSelected = false

    init(title: String, metrics: PortalCapsuleMetrics) {
        super.init(title: title)
        toolTip = title
        apply(metrics: metrics, fixedWidth: metrics.tabWidth)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setSelected(_ selected: Bool) {
        let didChange = isTabSelected != selected
        isTabSelected = selected
        setAccessibilitySelected(selected)
        setAccessibilityValue(NSNumber(value: selected))
        setCapsuleSelected(selected)
        if didChange {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
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
