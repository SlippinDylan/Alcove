import AlcoveCore
import AppKit

@MainActor
final class TabBarView: NSView {
    var onSelect: ((FolderTabID) -> Void)?
    var onClose: ((FolderTabID) -> Void)?
    var onAdd: (() -> Void)?

    private(set) var scrollView = NSScrollView()
    private let stackView = NSStackView()
    private var actionTargets: [TabActionTarget] = []

    private(set) var tabOrder: [FolderTabID] = []
    private(set) var selectedTabID: FolderTabID?
    private(set) var tabButtons: [FolderTabID: NSButton] = [:]
    private(set) var closeButtons: [FolderTabID: NSButton] = [:]
    private(set) var addButton: NSButton?

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
        closeButtons.removeAll(keepingCapacity: true)
        addButton = nil
        actionTargets.removeAll(keepingCapacity: true)

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for tab in portal.tabs {
            let tabItem = makeTabItem(for: tab, selected: tab.id == portal.selectedTabID)
            stackView.addArrangedSubview(tabItem)
        }

        let addButton = makeAddButton()
        self.addButton = addButton
        stackView.addArrangedSubview(addButton)
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

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeTabItem(for tab: FolderTab, selected: Bool) -> NSView {
        let container = NSView()
        let selectionButton = NSButton(title: tab.folderURL.lastPathComponent, target: nil, action: nil)
        selectionButton.setButtonType(.toggle)
        selectionButton.bezelStyle = .texturedRounded
        selectionButton.state = selected ? .on : .off
        selectionButton.setAccessibilityLabel("Select \(tab.folderURL.lastPathComponent)")
        selectionButton.setAccessibilityHelp("Switch to this folder tab")
        selectionButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "×", target: nil, action: nil)
        closeButton.bezelStyle = .inline
        closeButton.setAccessibilityLabel("Close \(tab.folderURL.lastPathComponent)")
        closeButton.setAccessibilityHelp("Close this folder tab")
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let selectTarget = TabActionTarget(action: .select(tab.id), owner: self)
        selectionButton.target = selectTarget
        selectionButton.action = #selector(TabActionTarget.performAction(_:))

        let closeTarget = TabActionTarget(action: .close(tab.id), owner: self)
        closeButton.target = closeTarget
        closeButton.action = #selector(TabActionTarget.performAction(_:))
        actionTargets.append(contentsOf: [selectTarget, closeTarget])

        container.addSubview(selectionButton)
        container.addSubview(closeButton)
        NSLayoutConstraint.activate([
            selectionButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            selectionButton.topAnchor.constraint(equalTo: container.topAnchor),
            selectionButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            closeButton.leadingAnchor.constraint(equalTo: selectionButton.trailingAnchor, constant: 2),
            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: selectionButton.centerYAnchor),
        ])

        tabButtons[tab.id] = selectionButton
        closeButtons[tab.id] = closeButton
        return container
    }

    private func makeAddButton() -> NSButton {
        let addButton = NSButton(title: "+", target: nil, action: nil)
        addButton.bezelStyle = .texturedRounded
        addButton.setAccessibilityLabel("Add tab")
        addButton.setAccessibilityHelp("Choose another folder for this portal")

        let addTarget = TabActionTarget(action: .add, owner: self)
        addButton.target = addTarget
        addButton.action = #selector(TabActionTarget.performAction(_:))
        actionTargets.append(addTarget)
        return addButton
    }

    fileprivate func selectTab(_ id: FolderTabID) {
        guard tabButtons[id] != nil else {
            return
        }
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

    @objc func performAction(_ sender: NSButton) {
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
