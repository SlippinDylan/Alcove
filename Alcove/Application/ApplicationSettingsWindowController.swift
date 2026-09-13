import AppKit
import ServiceManagement

@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}

struct ApplicationMetadata: Equatable {
    let name: String
    let version: String
    let build: String
    let copyright: String

    init(infoDictionary: [String: Any]) {
        name = infoDictionary["CFBundleName"] as? String ?? "Alcove"
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "—"
        build = infoDictionary["CFBundleVersion"] as? String ?? "—"
        copyright = infoDictionary["NSHumanReadableCopyright"] as? String ?? ""
    }

    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    var versionAndBuild: String {
        "\(version) (\(build))"
    }
}

@MainActor
final class ApplicationSettingsWindowController: NSWindowController {
    private(set) var settingsViewController: ApplicationSettingsViewController
    private(set) var categoryItems: [ApplicationSettingsViewController.Category: NSToolbarItem] = [:]
    private let settingsToolbar = NSToolbar(identifier: "application-settings")

    init(
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController(),
        metadata: ApplicationMetadata = ApplicationMetadata(),
        applicationIcon: NSImage = NSApplication.shared.applicationIconImage
    ) {
        let settingsViewController = ApplicationSettingsViewController(
            launchAtLoginController: launchAtLoginController,
            metadata: metadata,
            applicationIcon: applicationIcon
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

    func selectCategory(_ category: ApplicationSettingsViewController.Category) {
        settingsToolbar.selectedItemIdentifier = category.toolbarItemIdentifier
        settingsViewController.selectCategory(category)
    }

    func present() {
        guard let window else { return }
        window.center()
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
        settingsToolbar.selectedItemIdentifier = ApplicationSettingsViewController.Category.general
            .toolbarItemIdentifier
    }
}

extension ApplicationSettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ApplicationSettingsViewController.Category.allCases.map(\.toolbarItemIdentifier)
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
        guard let category = ApplicationSettingsViewController.Category(
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
        guard let category = ApplicationSettingsViewController.Category(rawValue: sender.tag) else {
            return
        }
        selectCategory(category)
    }
}

@MainActor
final class ApplicationSettingsViewController: NSViewController {
    enum Category: Int, CaseIterable {
        case general
        case about

        var title: String {
            switch self {
            case .general:
                NSLocalizedString("application.settings.general", comment: "General settings category")
            case .about:
                NSLocalizedString("application.settings.about", comment: "About settings category")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .about: "info.circle"
            }
        }

        var toolbarItemIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier("application-settings.\(rawValue)")
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

    private let launchAtLoginController: any LaunchAtLoginControlling
    private let metadata: ApplicationMetadata
    private let applicationIcon: NSImage
    private(set) var selectedCategory = Category.general
    private(set) var contentSeparator = NSBox()
    private(set) var contentStack = NSStackView()

    init(
        launchAtLoginController: any LaunchAtLoginControlling,
        metadata: ApplicationMetadata,
        applicationIcon: NSImage
    ) {
        self.launchAtLoginController = launchAtLoginController
        self.metadata = metadata
        self.applicationIcon = applicationIcon
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
        contentStack.setContentHuggingPriority(.required, for: .vertical)
        contentStack.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentSeparator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentSeparator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentSeparator.topAnchor.constraint(equalTo: root.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: contentSeparator.bottomAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
        ])
        view = root
        showCategory(selectedCategory)
    }

    func selectCategory(_ category: Category) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        showCategory(category)
    }

    private func showCategory(_ category: Category) {
        contentStack.arrangedSubviews.forEach { arrangedView in
            contentStack.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }
        switch category {
        case .general:
            showGeneralSettings()
        case .about:
            showAbout()
        }
    }

    private func showGeneralSettings() {
        let launchAtLoginSwitch = NSSwitch()
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(changeLaunchAtLogin(_:))
        launchAtLoginSwitch.identifier = NSUserInterfaceItemIdentifier(
            "application-settings.launch-at-login"
        )
        launchAtLoginSwitch.state = launchAtLoginController.isEnabled ? .on : .off
        launchAtLoginSwitch.setAccessibilityLabel(NSLocalizedString(
            "application.settings.launch_at_login",
            comment: "Launch at login setting"
        ))

        let row = settingRow(
            title: NSLocalizedString(
                "application.settings.launch_at_login",
                comment: "Launch at login setting"
            ),
            control: launchAtLoginSwitch
        )
        addSection(
            title: NSLocalizedString(
                "application.settings.startup",
                comment: "Startup settings section"
            ),
            card: ApplicationSettingsCardView(rows: [row])
        )
    }

    private func showAbout() {
        let iconView = NSImageView(image: applicationIcon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityLabel(metadata.name)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 112),
            iconView.heightAnchor.constraint(equalToConstant: 112),
        ])

        let nameLabel = NSTextField(labelWithString: metadata.name)
        nameLabel.font = .systemFont(ofSize: 30, weight: .bold)
        nameLabel.alignment = .center

        let versionBadge = VersionBadgeView(text: metadata.versionAndBuild)

        let copyrightLabel = NSTextField(wrappingLabelWithString: metadata.copyright)
        copyrightLabel.font = .systemFont(ofSize: 12)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center
        copyrightLabel.maximumNumberOfLines = 2

        let aboutStack = NSStackView(views: [iconView, nameLabel, versionBadge, copyrightLabel])
        aboutStack.orientation = .vertical
        aboutStack.alignment = .centerX
        aboutStack.spacing = 10
        aboutStack.setCustomSpacing(20, after: versionBadge)

        let container = NSView()
        container.addSubview(aboutStack)
        aboutStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(container)
        NSLayoutConstraint.activate([
            aboutStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            aboutStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            aboutStack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            aboutStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            container.heightAnchor.constraint(equalTo: view.heightAnchor, constant: -37),
        ])
        container.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func settingRow(title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .left
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 12
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
    }

    private func addSection(title: String, card: ApplicationSettingsCardView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .left

        let header = NSView()
        header.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),
        ])
        contentStack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        contentStack.setCustomSpacing(6, after: header)
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    @objc private func changeLaunchAtLogin(_ sender: NSSwitch) {
        do {
            try launchAtLoginController.setEnabled(sender.state == .on)
            sender.state = launchAtLoginController.isEnabled ? .on : .off
        } catch {
            sender.state = launchAtLoginController.isEnabled ? .on : .off
            presentLaunchAtLoginError(error)
        }
    }

    private func presentLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(
            "application.settings.launch_at_login_error",
            comment: "Launch at login error title"
        )
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

@MainActor
private final class ApplicationSettingsCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    init(rows: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        let stack = NSStackView(views: rows)
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
private final class VersionBadgeView: NSView {
    override var wantsUpdateLayer: Bool { true }

    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        identifier = NSUserInterfaceItemIdentifier("application-settings.version-badge")
        setAccessibilityLabel(text)

        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: label.intrinsicContentSize.width + 18, height: 22)
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        }
    }
}
