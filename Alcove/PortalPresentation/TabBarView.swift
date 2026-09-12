import AlcoveCore
import AppKit

@MainActor
final class TabBarView: NSView {
    var onSelect: ((FolderTabID) -> Void)?
    var onClose: ((FolderTabID) -> Void)?
    var onAdd: (() -> Void)?
    var onSetBackgroundStyle: ((PortalBackgroundStyle) -> Void)?
    var onSetIconSize: ((IconSize) -> Void)?
    var onFollowDesktopIconSettings: (() -> Void)?
    var onRemovePortal: (() -> Void)?

    private(set) var groupBackdropView = PortalTabGroupBackdropView()
    let groupMaterialView: PortalChromeMaterialView
    private(set) var scrollView = NSScrollView()
    private let stackView = NSStackView()
    private(set) var managementButton = NSButton()
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

        managementButton.image = NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: nil
        )
        managementButton.imageScaling = .scaleProportionallyDown
        managementButton.imagePosition = .imageOnly
        managementButton.isBordered = false
        managementButton.target = self
        managementButton.action = #selector(showSettingsWindow)
        managementButton.setAccessibilityLabel("Portal settings")
        managementButton.setAccessibilityHelp("Configure folders, style, and portal actions")
        managementButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(managementButton)
        updateManagementButtonAppearance()

        NSLayoutConstraint.activate([
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
        button.setAccessibilityLabel("Select \(tab.folderURL.lastPathComponent)")
        button.setAccessibilityHelp("Switch to this folder tab")

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

    @objc private func showSettingsWindow() {
        guard let portal else { return }
        let controller = settingsWindowController ?? makeSettingsWindowController(for: portal)
        settingsWindowController = controller
        controller.update(portal)
        controller.present(on: window?.screen)
    }

    private func makeSettingsWindowController(
        for portal: Portal
    ) -> PortalSettingsWindowController {
        PortalSettingsWindowController(
            portal: portal,
            onAddFolder: { [weak self] in self?.onAdd?() },
            onCloseFolder: { [weak self] id in self?.onClose?(id) },
            onSetIconSize: { [weak self] size in self?.onSetIconSize?(size) },
            onFollowDesktop: { [weak self] in self?.onFollowDesktopIconSettings?() },
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

private extension PortalBackgroundStyle {
    var menuTitle: String {
        switch self {
        case .highTransparency: "High Transparency"
        case .standard: "Standard"
        case .lowTransparency: "Low Transparency"
        }
    }
}

@MainActor
final class PortalSettingsWindowController: NSWindowController {
    private(set) var tabViewController: NSTabViewController
    private let onAddFolder: () -> Void
    private let onCloseFolder: (FolderTabID) -> Void
    private let onSetIconSize: (IconSize) -> Void
    private let onFollowDesktop: () -> Void
    private let onSetBackgroundStyle: (PortalBackgroundStyle) -> Void
    private let onRemovePortal: () -> Void
    private var portal: Portal

    init(
        portal: Portal,
        onAddFolder: @escaping () -> Void,
        onCloseFolder: @escaping (FolderTabID) -> Void,
        onSetIconSize: @escaping (IconSize) -> Void,
        onFollowDesktop: @escaping () -> Void,
        onSetBackgroundStyle: @escaping (PortalBackgroundStyle) -> Void,
        onRemovePortal: @escaping () -> Void
    ) {
        self.portal = portal
        self.onAddFolder = onAddFolder
        self.onCloseFolder = onCloseFolder
        self.onSetIconSize = onSetIconSize
        self.onFollowDesktop = onFollowDesktop
        self.onSetBackgroundStyle = onSetBackgroundStyle
        self.onRemovePortal = onRemovePortal
        let tabViewController = NSTabViewController()
        tabViewController.tabStyle = .toolbar
        self.tabViewController = tabViewController
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 572),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = tabViewController
        window.title = "Portal Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        shouldCascadeWindows = false
        rebuildTabs()
        window.setFrame(
            NSRect(origin: .zero, size: NSSize(width: 400, height: 572)),
            display: false
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(_ portal: Portal) {
        guard self.portal != portal else { return }
        self.portal = portal
        rebuildTabs()
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

    private func rebuildTabs() {
        let selectedIndex = tabViewController.selectedTabViewItemIndex
        for item in tabViewController.tabViewItems {
            tabViewController.removeTabViewItem(item)
        }
        for category in PortalSettingsViewController.Category.allCases {
            let controller = PortalSettingsViewController(
                portal: portal,
                onAddFolder: onAddFolder,
                onCloseFolder: onCloseFolder,
                onSetIconSize: onSetIconSize,
                onFollowDesktop: onFollowDesktop,
                onSetBackgroundStyle: onSetBackgroundStyle,
                onRemovePortal: { [weak self] in
                    self?.close()
                    self?.onRemovePortal()
                },
                category: category
            )
            let item = NSTabViewItem(viewController: controller)
            item.label = category.title
            item.image = NSImage(
                systemSymbolName: category.symbol,
                accessibilityDescription: category.title
            )
            tabViewController.addTabViewItem(item)
        }
        tabViewController.selectedTabViewItemIndex = min(
            max(0, selectedIndex),
            tabViewController.tabViewItems.count - 1
        )
    }
}

@MainActor
final class PortalSettingsViewController: NSViewController {
    enum Category: Int, CaseIterable {
        case folders
        case style
        case other

        var title: String {
            switch self {
            case .folders: "Folders"
            case .style: "Style"
            case .other: "Other"
            }
        }

        var symbol: String {
            switch self {
            case .folders: "folder"
            case .style: "paintpalette"
            case .other: "ellipsis.circle"
            }
        }
    }

    private let portal: Portal
    private let onAddFolder: () -> Void
    private let onCloseFolder: (FolderTabID) -> Void
    private let onSetIconSize: (IconSize) -> Void
    private let onFollowDesktop: () -> Void
    private let onSetBackgroundStyle: (PortalBackgroundStyle) -> Void
    private let onRemovePortal: () -> Void
    private let category: Category
    private let contentContainer = NSView()

    init(
        portal: Portal,
        onAddFolder: @escaping () -> Void,
        onCloseFolder: @escaping (FolderTabID) -> Void,
        onSetIconSize: @escaping (IconSize) -> Void,
        onFollowDesktop: @escaping () -> Void,
        onSetBackgroundStyle: @escaping (PortalBackgroundStyle) -> Void,
        onRemovePortal: @escaping () -> Void,
        category: Category
    ) {
        self.portal = portal
        self.onAddFolder = onAddFolder
        self.onCloseFolder = onCloseFolder
        self.onSetIconSize = onSetIconSize
        self.onFollowDesktop = onFollowDesktop
        self.onSetBackgroundStyle = onSetBackgroundStyle
        self.onRemovePortal = onRemovePortal
        self.category = category
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            contentContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
        ])
        view = root
        showCategory(category)
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
        return row
    }

    private func showCategory(_ category: Category) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(content)

        switch category {
        case .folders:
            content.addArrangedSubview(sectionLabel("Folders"))
            var folderRows: [NSView] = [actionButton(
                title: "Add Folder…",
                symbol: "folder.badge.plus",
                action: #selector(addFolder)
            )]
            if let selectedTab = portal.selectedTab {
                folderRows.append(actionButton(
                    title: "Remove \(selectedTab.folderURL.lastPathComponent)",
                    symbol: "xmark",
                    action: #selector(closeFolder)
                ))
            }
            content.addArrangedSubview(PortalSettingsCardView(rows: folderRows))
        case .style:
            content.addArrangedSubview(sectionLabel("Icon Size"))
            content.addArrangedSubview(PortalSettingsCardView(rows: [
                styleRow(title: "Size", control: iconSizePopup()),
            ]))
            content.addArrangedSubview(sectionLabel("Appearance"))
            content.addArrangedSubview(PortalSettingsCardView(rows: [
                styleRow(title: "Background", control: backgroundPopup()),
            ]))
        case .other:
            content.addArrangedSubview(sectionLabel("Other"))
            let removeButton = actionButton(
                title: "Remove Portal",
                symbol: "trash",
                action: #selector(removePortal)
            )
            removeButton.contentTintColor = .systemRed
            content.addArrangedSubview(PortalSettingsCardView(rows: [removeButton]))
        }

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentContainer.topAnchor),
        ])
    }

    private func iconSizePopup() -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.identifier = NSUserInterfaceItemIdentifier("portal-settings.icon-size")
        popup.addItems(withTitles: ["Follow Desktop", "Small", "Medium", "Large"])
        switch portal.iconLayout {
        case .followDesktop:
            popup.selectItem(at: 0)
        case .fixed(let size):
            popup.selectItem(at: size == .small ? 1 : size == .large ? 3 : 2)
        }
        popup.target = self
        popup.action = #selector(changeIconSize)
        return popup
    }

    private func backgroundPopup() -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.identifier = NSUserInterfaceItemIdentifier("portal-settings.background")
        popup.addItems(withTitles: PortalBackgroundStyle.allCases.map(\.menuTitle))
        popup.selectItem(at: PortalBackgroundStyle.allCases.firstIndex(of: portal.backgroundStyle) ?? 0)
        popup.target = self
        popup.action = #selector(changeBackground)
        return popup
    }

    @objc private func addFolder() {
        onAddFolder()
    }

    @objc private func closeFolder() {
        guard let selectedTabID = portal.selectedTabID else { return }
        onCloseFolder(selectedTabID)
    }

    @objc private func changeIconSize(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 0: onFollowDesktop()
        case 1: onSetIconSize(.small)
        case 2: onSetIconSize(.medium)
        case 3: onSetIconSize(.large)
        default: return
        }
    }

    @objc private func changeBackground(_ sender: NSPopUpButton) {
        let styles = PortalBackgroundStyle.allCases
        guard styles.indices.contains(sender.indexOfSelectedItem) else { return }
        onSetBackgroundStyle(styles[sender.indexOfSelectedItem])
    }

    @objc private func removePortal() {
        onRemovePortal()
    }
}

@MainActor
private final class PortalSettingsCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    init(rows: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
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
