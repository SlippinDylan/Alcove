import AlcoveCore
import AppKit

func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
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
            tabWidth = 56
            height = 26
            controlSize = .small
        case .large:
            tabWidth = 72
            height = 30
            controlSize = .large
        default:
            tabWidth = 64
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
        if let visibleFrame = window?.screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame {
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
    private var actionTargets: [TabActionTarget] = []
    private var portal: Portal?
    private var capsuleMetrics = PortalCapsuleMetrics(iconSize: .medium)

    private(set) var tabOrder: [FolderTabID] = []
    private(set) var selectedTabID: FolderTabID?
    private(set) var tabButtons: [FolderTabID: PortalTabButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    override func layout() {
        super.layout()
        let backButtonWidth = backButton.fittingSize.width + 16
        let reservedSideWidth = max(52, backButtonWidth)
        let maximumGroupWidth = max(1, bounds.width - reservedSideWidth * 2)
        let buttons = Array(tabButtons.values)
        guard !buttons.isEmpty else {
            scrollView.isHidden = true
            scrollView.frame = .zero
            return
        }
        scrollView.isHidden = false
        buttons.forEach { $0.setFixedWidth(capsuleMetrics.tabWidth) }
        var fittingSize = stackView.fittingSize
        if fittingSize.width > maximumGroupWidth, !buttons.isEmpty {
            let horizontalInsets = stackView.edgeInsets.left + stackView.edgeInsets.right
            let compressedWidth = max(
                1,
                (maximumGroupWidth - horizontalInsets) / CGFloat(buttons.count)
            )
            buttons.forEach { $0.setFixedWidth(compressedWidth) }
            fittingSize = stackView.fittingSize
        }
        let groupWidth = min(fittingSize.width, maximumGroupWidth)
        scrollView.frame = NSRect(
            x: bounds.midX - groupWidth / 2,
            y: bounds.midY - fittingSize.height / 2,
            width: groupWidth,
            height: fittingSize.height
        )
        let viewportSize = scrollView.contentSize
        stackView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: viewportSize.width,
                height: viewportSize.height
            )
        )
        scrollView.contentView.scroll(to: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTabGroupAppearance()
        updateManagementButtonAppearance()
    }

    func configure(with portal: Portal) {
        update(with: portal)
    }

    func update(with portal: Portal) {
        self.portal = portal
        capsuleMetrics = PortalCapsuleMetrics(iconSize: portal.iconSize)
        backButton.apply(metrics: capsuleMetrics)
        stackView.layer?.cornerRadius = (capsuleMetrics.height + 4) / 2
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

    func updateNavigation(canGoBack: Bool) {
        backButton.isHidden = !canGoBack
        needsLayout = true
    }

    private func configureView() {
        // The scroll view owns the document frame. Prevent an intermediate zero-width
        // autoresizing constraint from conflicting with NSStackView's arranged-subview constraints.
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        stackView.wantsLayer = true
        stackView.layer?.masksToBounds = true
        stackView.layer?.shadowOpacity = 0
        updateTabGroupAppearance()

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
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

    private func updateTabGroupAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            stackView.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
            stackView.layer?.borderWidth = 0.5
            stackView.layer?.borderColor = NSColor.separatorColor.cgColor
            stackView.layer?.shadowOpacity = 0
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

    func selectTab(_ id: FolderTabID) {
        guard tabButtons[id] != nil else { return }
        onSelect?(id)
    }

}
