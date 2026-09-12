import AlcoveCore
import AppKit

@MainActor
final class TabBarView: NSView {
    var onSelect: ((FolderTabID) -> Void)?
    var onClose: ((FolderTabID) -> Void)?
    var onAdd: (() -> Void)?

    private(set) var scrollView = NSScrollView()
    private let stackView = NSStackView()
    private(set) var managementButton = NSButton()
    private(set) var managementMenu = NSMenu()
    private var actionTargets: [TabActionTarget] = []

    private(set) var tabOrder: [FolderTabID] = []
    private(set) var selectedTabID: FolderTabID?
    private(set) var tabButtons: [FolderTabID: NSButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    override func layout() {
        super.layout()
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
        configureManagementMenu(for: portal)
        needsLayout = true
    }

    private func configureView() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 6
        stackView.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.horizontalScroller?.controlSize = .mini
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = stackView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        managementButton.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: "Portal options"
        )
        managementButton.imagePosition = .imageOnly
        applyManagementButtonStyle()
        managementButton.target = self
        managementButton.action = #selector(showManagementMenu)
        managementButton.setAccessibilityLabel("Portal options")
        managementButton.setAccessibilityHelp("Add or close folder tabs")
        managementButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(managementButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: managementButton.leadingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            managementButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            managementButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            managementButton.widthAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func makeTabButton(for tab: FolderTab, selected: Bool) -> NSButton {
        let button = NSButton(title: tab.folderURL.lastPathComponent, target: nil, action: nil)
        button.setButtonType(.toggle)
        applyCapsuleStyle(to: button)
        button.state = selected ? .on : .off
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
        addItem.target = addTarget
        managementMenu.addItem(addItem)
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
        closeItem.target = closeTarget
        managementMenu.addItem(closeItem)
    }

    private func applyCapsuleStyle(to button: NSButton) {
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
            button.borderShape = .capsule
        } else {
            button.bezelStyle = .accessoryBar
        }
    }

    private func applyManagementButtonStyle() {
        if #available(macOS 26.0, *) {
            managementButton.bezelStyle = .glass
            managementButton.borderShape = .circle
        } else {
            managementButton.bezelStyle = .accessoryBarAction
        }
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
}

@MainActor
private final class TabActionTarget: NSObject {
    enum Action {
        case select(FolderTabID)
        case close(FolderTabID)
        case add
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
        }
    }
}
