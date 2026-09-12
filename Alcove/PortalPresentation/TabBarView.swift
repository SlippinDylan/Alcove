import AlcoveCore
import AppKit

@MainActor
final class TabBarView: NSView {
    var onSelect: ((FolderTabID) -> Void)?
    var onClose: ((FolderTabID) -> Void)?
    var onAdd: (() -> Void)?
    var onSetBackgroundStyle: ((PortalBackgroundStyle) -> Void)?

    private(set) var groupBackdropView = PortalTabGroupBackdropView()
    let groupMaterialView: PortalChromeMaterialView
    private(set) var scrollView = NSScrollView()
    private let stackView = NSStackView()
    private(set) var managementButton = NSButton()
    private(set) var managementMenu = NSMenu()
    private var actionTargets: [TabActionTarget] = []

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
        configureManagementMenu(for: portal)
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

        managementButton.title = "•••"
        managementButton.isBordered = false
        managementButton.target = self
        managementButton.action = #selector(showManagementMenu)
        managementButton.setAccessibilityLabel("Portal options")
        managementButton.setAccessibilityHelp("Add or close folder tabs")
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

    private func configureManagementMenu(for portal: Portal) {
        managementMenu.removeAllItems()

        let addTarget = TabActionTarget(action: .add, owner: self)
        actionTargets.append(addTarget)
        let addItem = NSMenuItem(
            title: "Add Folder…",
            action: #selector(TabActionTarget.performAction(_:)),
            keyEquivalent: ""
        )
        addItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addItem.target = addTarget
        managementMenu.addItem(addItem)

        let backgroundMenu = NSMenu(title: "Background")
        for style in PortalBackgroundStyle.allCases {
            let target = TabActionTarget(action: .setBackgroundStyle(style), owner: self)
            actionTargets.append(target)
            let item = NSMenuItem(
                title: style.menuTitle,
                action: #selector(TabActionTarget.performAction(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.state = style == portal.backgroundStyle ? .on : .off
            backgroundMenu.addItem(item)
        }
        let backgroundItem = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        backgroundItem.submenu = backgroundMenu
        managementMenu.addItem(backgroundItem)
        managementMenu.addItem(.separator())

        guard let selectedTab = portal.tabs.first(where: { $0.id == portal.selectedTabID }) else {
            return
        }
        let closeTarget = TabActionTarget(action: .close(selectedTab.id), owner: self)
        actionTargets.append(closeTarget)
        let closeItem = NSMenuItem(
            title: "Close \(selectedTab.folderURL.lastPathComponent)",
            action: #selector(TabActionTarget.performAction(_:)),
            keyEquivalent: ""
        )
        closeItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeItem.target = closeTarget
        managementMenu.addItem(closeItem)
    }

    private func updateManagementButtonAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            managementButton.attributedTitle = NSAttributedString(
                string: "•••",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                    .foregroundColor: activeLabelColor,
                ]
            )
        }
    }

    private var activeLabelColor: NSColor {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .white
            : .black
    }

    @objc private func showManagementMenu() {
        managementMenu.popUp(
            positioning: nil,
            at: NSPoint(x: managementButton.bounds.minX, y: managementButton.bounds.minY),
            in: managementButton
        )
    }

    fileprivate func selectTab(_ id: FolderTabID) {
        guard tabButtons[id] != nil else { return }
        onSelect?(id)
    }

    fileprivate func closeTab(_ id: FolderTabID) {
        onClose?(id)
    }

    fileprivate func addTab() {
        onAdd?()
    }

    fileprivate func setBackgroundStyle(_ backgroundStyle: PortalBackgroundStyle) {
        onSetBackgroundStyle?(backgroundStyle)
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
        case close(FolderTabID)
        case add
        case setBackgroundStyle(PortalBackgroundStyle)
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
        case .close(let id):
            owner?.closeTab(id)
        case .add:
            owner?.addTab()
        case .setBackgroundStyle(let backgroundStyle):
            owner?.setBackgroundStyle(backgroundStyle)
        }
    }
}
