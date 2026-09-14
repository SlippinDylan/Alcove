import AppKit
import AlcoveCore
import ServiceManagement

@MainActor
protocol PanelPositionRepairing: AnyObject {
    func repairPanelPositions() async throws -> Int
}

@MainActor
final class DisabledPanelPositionRepairer: PanelPositionRepairing {
    func repairPanelPositions() async throws -> Int { 0 }
}

enum PortalCornerRadius: Int, CaseIterable, Sendable {
    case none
    case small
    case medium
    case large
    case maximum

    var points: CGFloat {
        switch self {
        case .none: 0
        case .small: 8
        case .medium: 14
        case .large: 20
        case .maximum: 24
        }
    }
}

enum PortalSpacing: Int, CaseIterable, Sendable {
    case minimum
    case small
    case medium
    case large
    case maximum

    var points: CGFloat {
        switch self {
        case .minimum: 4
        case .small: 8
        case .medium: 12
        case .large: 16
        case .maximum: 20
        }
    }
}

struct PortalAppearancePreferences: Equatable, Sendable {
    static let defaults = PortalAppearancePreferences(
        iconSize: .medium,
        backgroundStyle: .standard,
        cornerRadius: .maximum,
        spacing: .medium,
        shadowEnabled: true
    )

    var iconSize: IconSize
    var backgroundStyle: PortalBackgroundStyle
    var cornerRadius: PortalCornerRadius
    var spacing: PortalSpacing
    var shadowEnabled: Bool

    init(
        iconSize: IconSize = .medium,
        backgroundStyle: PortalBackgroundStyle = .standard,
        cornerRadius: PortalCornerRadius,
        spacing: PortalSpacing,
        shadowEnabled: Bool
    ) {
        self.iconSize = iconSize
        self.backgroundStyle = backgroundStyle
        self.cornerRadius = cornerRadius
        self.spacing = spacing
        self.shadowEnabled = shadowEnabled
    }
}

@MainActor
protocol ApplicationPreferencesControlling: AnyObject {
    var portalAppearance: PortalAppearancePreferences { get }
    @discardableResult func setPortalIconSize(_ iconSize: IconSize) -> Bool
    @discardableResult func setPortalBackgroundStyle(_ backgroundStyle: PortalBackgroundStyle) -> Bool
    @discardableResult func setPortalCornerRadius(_ cornerRadius: PortalCornerRadius) -> Bool
    @discardableResult func setPortalSpacing(_ spacing: PortalSpacing) -> Bool
    @discardableResult func setPortalShadowEnabled(_ enabled: Bool) -> Bool
    func replacePortalAppearanceFromImport(_ appearance: PortalAppearancePreferences)
}

@MainActor
final class ApplicationPreferencesController: ApplicationPreferencesControlling {
    private enum Key {
        static let portalIconSize = "portalAppearance.iconSize"
        static let portalBackgroundStyle = "portalAppearance.backgroundStyle"
        static let portalCornerRadius = "portalAppearance.cornerRadius"
        static let portalSpacing = "portalAppearance.spacing"
        static let portalShadowEnabled = "portalAppearance.shadowEnabled"
    }

    private let userDefaults: UserDefaults
    private(set) var portalAppearance: PortalAppearancePreferences
    var onPortalAppearanceChanged: ((PortalAppearancePreferences) -> Bool)?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let defaults = PortalAppearancePreferences.defaults
        userDefaults.register(defaults: [
            Key.portalIconSize: Double(defaults.iconSize.rawValue),
            Key.portalBackgroundStyle: defaults.backgroundStyle.rawValue,
            Key.portalCornerRadius: defaults.cornerRadius.rawValue,
            Key.portalSpacing: defaults.spacing.rawValue,
            Key.portalShadowEnabled: defaults.shadowEnabled,
        ])
        let cornerRadius = PortalCornerRadius(
            rawValue: userDefaults.integer(forKey: Key.portalCornerRadius)
        ) ?? defaults.cornerRadius
        let spacing = PortalSpacing(
            rawValue: userDefaults.integer(forKey: Key.portalSpacing)
        ) ?? defaults.spacing
        let iconSize = IconSize(
            rawValue: CGFloat(userDefaults.double(forKey: Key.portalIconSize))
        ) ?? defaults.iconSize
        let backgroundStyle = userDefaults.string(forKey: Key.portalBackgroundStyle)
            .flatMap(PortalBackgroundStyle.init(rawValue:)) ?? defaults.backgroundStyle
        portalAppearance = PortalAppearancePreferences(
            iconSize: iconSize,
            backgroundStyle: backgroundStyle,
            cornerRadius: cornerRadius,
            spacing: spacing,
            shadowEnabled: userDefaults.bool(forKey: Key.portalShadowEnabled)
        )
    }

    @discardableResult
    func setPortalIconSize(_ iconSize: IconSize) -> Bool {
        guard portalAppearance.iconSize != iconSize else { return true }
        var updatedAppearance = portalAppearance
        updatedAppearance.iconSize = iconSize
        guard onPortalAppearanceChanged?(updatedAppearance) != false else { return false }
        portalAppearance = updatedAppearance
        userDefaults.set(Double(iconSize.rawValue), forKey: Key.portalIconSize)
        return true
    }

    @discardableResult
    func setPortalBackgroundStyle(_ backgroundStyle: PortalBackgroundStyle) -> Bool {
        guard portalAppearance.backgroundStyle != backgroundStyle else { return true }
        var updatedAppearance = portalAppearance
        updatedAppearance.backgroundStyle = backgroundStyle
        guard onPortalAppearanceChanged?(updatedAppearance) != false else { return false }
        portalAppearance = updatedAppearance
        userDefaults.set(backgroundStyle.rawValue, forKey: Key.portalBackgroundStyle)
        return true
    }

    @discardableResult
    func setPortalSpacing(_ spacing: PortalSpacing) -> Bool {
        guard portalAppearance.spacing != spacing else { return true }
        var updatedAppearance = portalAppearance
        updatedAppearance.spacing = spacing
        guard onPortalAppearanceChanged?(updatedAppearance) != false else { return false }
        portalAppearance = updatedAppearance
        userDefaults.set(spacing.rawValue, forKey: Key.portalSpacing)
        return true
    }

    @discardableResult
    func setPortalCornerRadius(_ cornerRadius: PortalCornerRadius) -> Bool {
        guard portalAppearance.cornerRadius != cornerRadius else { return true }
        var updatedAppearance = portalAppearance
        updatedAppearance.cornerRadius = cornerRadius
        guard onPortalAppearanceChanged?(updatedAppearance) != false else { return false }
        portalAppearance = updatedAppearance
        userDefaults.set(cornerRadius.rawValue, forKey: Key.portalCornerRadius)
        return true
    }

    @discardableResult
    func setPortalShadowEnabled(_ enabled: Bool) -> Bool {
        guard portalAppearance.shadowEnabled != enabled else { return true }
        var updatedAppearance = portalAppearance
        updatedAppearance.shadowEnabled = enabled
        guard onPortalAppearanceChanged?(updatedAppearance) != false else { return false }
        portalAppearance = updatedAppearance
        userDefaults.set(enabled, forKey: Key.portalShadowEnabled)
        return true
    }

    /// Persists an already-committed imported appearance without re-entering
    /// the normal change callback and attempting a second layout transaction.
    func replacePortalAppearanceFromImport(_ appearance: PortalAppearancePreferences) {
        portalAppearance = appearance
        userDefaults.set(Double(appearance.iconSize.rawValue), forKey: Key.portalIconSize)
        userDefaults.set(appearance.backgroundStyle.rawValue, forKey: Key.portalBackgroundStyle)
        userDefaults.set(appearance.cornerRadius.rawValue, forKey: Key.portalCornerRadius)
        userDefaults.set(appearance.spacing.rawValue, forKey: Key.portalSpacing)
        userDefaults.set(appearance.shadowEnabled, forKey: Key.portalShadowEnabled)
    }
}

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
        preferencesController: any ApplicationPreferencesControlling = ApplicationPreferencesController(),
        layoutBackupController: any ApplicationLayoutBackupControlling = DisabledApplicationLayoutBackupController(),
        panelPositionRepairer: any PanelPositionRepairing = DisabledPanelPositionRepairer(),
        metadata: ApplicationMetadata = ApplicationMetadata(),
        applicationIcon: NSImage = NSApplication.shared.applicationIconImage
    ) {
        let settingsViewController = ApplicationSettingsViewController(
            launchAtLoginController: launchAtLoginController,
            preferencesController: preferencesController,
            layoutBackupController: layoutBackupController,
            panelPositionRepairer: panelPositionRepairer,
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
        case style
        case advanced
        case about

        var title: String {
            switch self {
            case .general:
                NSLocalizedString("application.settings.general", comment: "General settings category")
            case .style:
                NSLocalizedString("application.settings.style", comment: "Style settings category")
            case .advanced:
                NSLocalizedString("application.settings.advanced", comment: "Advanced settings category")
            case .about:
                NSLocalizedString("application.settings.about", comment: "About settings category")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .style: "paintpalette"
            case .advanced: "slider.horizontal.3"
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
    private let preferencesController: any ApplicationPreferencesControlling
    private let layoutBackupController: any ApplicationLayoutBackupControlling
    private let panelPositionRepairer: any PanelPositionRepairing
    private let metadata: ApplicationMetadata
    private let applicationIcon: NSImage
    private(set) var selectedCategory = Category.general
    private(set) var contentSeparator = NSBox()
    private(set) var contentStack = NSStackView()

    init(
        launchAtLoginController: any LaunchAtLoginControlling,
        preferencesController: any ApplicationPreferencesControlling,
        layoutBackupController: any ApplicationLayoutBackupControlling,
        panelPositionRepairer: any PanelPositionRepairing,
        metadata: ApplicationMetadata,
        applicationIcon: NSImage
    ) {
        self.launchAtLoginController = launchAtLoginController
        self.preferencesController = preferencesController
        self.layoutBackupController = layoutBackupController
        self.panelPositionRepairer = panelPositionRepairer
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
        case .style:
            showStyleSettings()
        case .advanced:
            showAdvancedSettings()
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

    private func showStyleSettings() {
        addSection(
            title: NSLocalizedString(
                "application.settings.portal_appearance",
                comment: "Portal appearance settings section"
            ),
            card: ApplicationSettingsCardView(rows: [
                settingRow(
                    title: NSLocalizedString(
                        "application.settings.content_size",
                        comment: "Portal content size setting"
                    ),
                    control: iconSizeSlider()
                ),
                settingRow(
                    title: NSLocalizedString(
                        "application.settings.transparency",
                        comment: "Portal transparency setting"
                    ),
                    control: backgroundStyleSlider()
                ),
                settingRow(
                    title: NSLocalizedString(
                        "application.settings.corner_radius",
                        comment: "Portal corner radius setting"
                    ),
                    control: cornerRadiusSlider()
                ),
                settingRow(
                    title: NSLocalizedString(
                        "application.settings.spacing",
                        comment: "Portal spacing setting"
                    ),
                    control: spacingSlider()
                ),
                settingRow(
                    title: NSLocalizedString(
                        "application.settings.shadow",
                        comment: "Portal shadow setting"
                    ),
                    control: shadowSwitch()
                ),
            ])
        )
    }

    private func showAdvancedSettings() {
        let repairTitle = NSTextField(labelWithString: NSLocalizedString(
            "application.settings.position_repair.title",
            comment: "Panel position repair card title"
        ))
        repairTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        let repairDetail = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "application.settings.position_repair.description",
            comment: "Panel position repair card description"
        ))
        repairDetail.font = .systemFont(ofSize: 12)
        repairDetail.textColor = .secondaryLabelColor
        repairDetail.maximumNumberOfLines = 2

        let repairLabels = NSStackView(views: [repairTitle, repairDetail])
        repairLabels.orientation = .vertical
        repairLabels.alignment = .leading
        repairLabels.spacing = 3
        repairLabels.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let repairButton = backupButton(
            titleKey: "application.settings.position_repair.action",
            identifier: "application-settings.position-repair.action",
            action: #selector(repairPanelPositions(_:))
        )
        let repairSpacer = NSView()
        let repairActions = NSStackView(views: [repairSpacer, repairButton])
        repairActions.orientation = .horizontal
        repairActions.alignment = .centerY
        repairActions.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let repairCard = ApplicationSettingsCardView(rows: [repairLabels, repairActions])
        repairCard.identifier = NSUserInterfaceItemIdentifier(
            "application-settings.position-repair.card"
        )
        addSection(
            title: NSLocalizedString(
                "application.settings.position_repair.section",
                comment: "Panel position repair settings section"
            ),
            card: repairCard
        )

        let title = NSTextField(labelWithString: NSLocalizedString(
            "application.settings.backup.title",
            comment: "Layout backup card title"
        ))
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let detail = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "application.settings.backup.description",
            comment: "Layout backup card description"
        ))
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2

        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let importButton = backupButton(
            titleKey: "application.settings.backup.import",
            identifier: "application-settings.backup.import",
            action: #selector(importLayout(_:))
        )
        let exportButton = backupButton(
            titleKey: "application.settings.backup.export",
            identifier: "application-settings.backup.export",
            action: #selector(exportLayout(_:))
        )
        let spacer = NSView()
        let actions = NSStackView(views: [spacer, importButton, exportButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        actions.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let card = ApplicationSettingsCardView(rows: [labels, actions])
        card.identifier = NSUserInterfaceItemIdentifier("application-settings.backup.card")
        addSection(
            title: NSLocalizedString(
                "application.settings.backup.section",
                comment: "Layout backup settings section"
            ),
            card: card
        )
    }

    private func backupButton(titleKey: String, identifier: String, action: Selector) -> NSButton {
        let button = NSButton(
            title: NSLocalizedString(titleKey, comment: "Layout backup action"),
            target: self,
            action: action
        )
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.controlSize = .large
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
        } else {
            button.bezelStyle = .rounded
        }
        return button
    }

    private func iconSizeSlider() -> NSSlider {
        let values: [IconSize] = [.small, .medium, .large]
        let selectedIndex = values.firstIndex(of: preferencesController.portalAppearance.iconSize) ?? 1
        let slider = discreteSlider(
            identifier: "application-settings.content-size",
            value: selectedIndex,
            maximum: values.count - 1,
            action: #selector(changeIconSize(_:))
        )
        slider.setAccessibilityLabel(NSLocalizedString(
            "application.settings.content_size",
            comment: "Portal content size setting"
        ))
        slider.setAccessibilityValue(iconSizeTitle(values[selectedIndex]))
        return slider
    }

    private func backgroundStyleSlider() -> NSSlider {
        let values = PortalBackgroundStyle.allCases
        let selectedIndex = values.firstIndex(
            of: preferencesController.portalAppearance.backgroundStyle
        ) ?? 2
        let slider = discreteSlider(
            identifier: "application-settings.transparency",
            value: selectedIndex,
            maximum: values.count - 1,
            action: #selector(changeBackgroundStyle(_:))
        )
        slider.setAccessibilityLabel(NSLocalizedString(
            "application.settings.transparency",
            comment: "Portal transparency setting"
        ))
        slider.setAccessibilityValue(backgroundStyleTitle(values[selectedIndex]))
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

    private func spacingSlider() -> NSSlider {
        let values = PortalSpacing.allCases
        let selectedIndex = values.firstIndex(
            of: preferencesController.portalAppearance.spacing
        ) ?? PortalSpacing.medium.rawValue
        let slider = NSSlider(
            value: Double(selectedIndex),
            minValue: 0,
            maxValue: Double(values.count - 1),
            target: self,
            action: #selector(changeSpacing(_:))
        )
        slider.identifier = NSUserInterfaceItemIdentifier("application-settings.spacing")
        slider.numberOfTickMarks = values.count
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        slider.setAccessibilityLabel(NSLocalizedString(
            "application.settings.spacing",
            comment: "Portal spacing setting"
        ))
        slider.setAccessibilityValue(spacingTitle(values[selectedIndex]))
        return slider
    }

    private func cornerRadiusSlider() -> NSSlider {
        let values = PortalCornerRadius.allCases
        let selectedIndex = values.firstIndex(
            of: preferencesController.portalAppearance.cornerRadius
        ) ?? values.count - 1
        let slider = NSSlider(
            value: Double(selectedIndex),
            minValue: 0,
            maxValue: Double(values.count - 1),
            target: self,
            action: #selector(changeCornerRadius(_:))
        )
        slider.identifier = NSUserInterfaceItemIdentifier(
            "application-settings.corner-radius"
        )
        slider.numberOfTickMarks = values.count
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        slider.setAccessibilityLabel(NSLocalizedString(
            "application.settings.corner_radius",
            comment: "Portal corner radius setting"
        ))
        slider.setAccessibilityValue(cornerRadiusTitle(values[selectedIndex]))
        return slider
    }

    private func shadowSwitch() -> NSSwitch {
        let control = NSSwitch()
        control.identifier = NSUserInterfaceItemIdentifier("application-settings.shadow")
        control.state = preferencesController.portalAppearance.shadowEnabled ? .on : .off
        control.target = self
        control.action = #selector(changeShadow(_:))
        control.setAccessibilityLabel(NSLocalizedString(
            "application.settings.shadow",
            comment: "Portal shadow setting"
        ))
        return control
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

    @objc private func importLayout(_ sender: NSButton) {
        guard let window = view.window else { return }
        layoutBackupController.beginImport(from: window)
    }

    @objc private func exportLayout(_ sender: NSButton) {
        guard let window = view.window else { return }
        layoutBackupController.beginExport(from: window)
    }

    @objc private func repairPanelPositions(_ sender: NSButton) {
        guard let window = view.window else { return }
        sender.isEnabled = false
        Task { [weak self, weak sender, weak window] in
            guard let self else { return }
            defer { sender?.isEnabled = true }
            do {
                let count = try await panelPositionRepairer.repairPanelPositions()
                presentPositionRepairResult(count: count, from: window)
            } catch {
                presentPositionRepairError(error, from: window)
            }
        }
    }

    private func presentPositionRepairResult(count: Int, from window: NSWindow?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = count == 0
            ? NSLocalizedString(
                "application.settings.position_repair.no_changes",
                comment: "No panel positions needed repair"
            )
            : NSLocalizedString(
                "application.settings.position_repair.completed",
                comment: "Panel position repair completed"
            )
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Dismiss alert"))
        alert.beginSheetModal(for: window)
    }

    private func presentPositionRepairError(_ error: Error, from window: NSWindow?) {
        guard let window else { return }
        let alert = NSAlert(error: error)
        alert.messageText = NSLocalizedString(
            "application.settings.position_repair.error",
            comment: "Panel position repair error title"
        )
        alert.beginSheetModal(for: window)
    }

    @objc private func changeIconSize(_ sender: NSSlider) {
        let values: [IconSize] = [.small, .medium, .large]
        let index = Int(sender.doubleValue.rounded())
        guard values.indices.contains(index) else { return }
        let iconSize = values[index]
        if preferencesController.setPortalIconSize(iconSize) {
            sender.setAccessibilityValue(iconSizeTitle(iconSize))
        } else {
            sender.doubleValue = Double(
                values.firstIndex(of: preferencesController.portalAppearance.iconSize) ?? 1
            )
        }
    }

    @objc private func changeBackgroundStyle(_ sender: NSSlider) {
        let values = PortalBackgroundStyle.allCases
        let index = Int(sender.doubleValue.rounded())
        guard values.indices.contains(index) else { return }
        let backgroundStyle = values[index]
        if preferencesController.setPortalBackgroundStyle(backgroundStyle) {
            sender.setAccessibilityValue(backgroundStyleTitle(backgroundStyle))
        } else {
            sender.doubleValue = Double(
                values.firstIndex(of: preferencesController.portalAppearance.backgroundStyle) ?? 2
            )
        }
    }

    @objc private func changeCornerRadius(_ sender: NSSlider) {
        let values = PortalCornerRadius.allCases
        let index = Int(sender.doubleValue.rounded())
        guard values.indices.contains(index) else { return }
        let cornerRadius = values[index]
        if preferencesController.setPortalCornerRadius(cornerRadius) {
            sender.setAccessibilityValue(cornerRadiusTitle(cornerRadius))
        } else {
            sender.doubleValue = Double(preferencesController.portalAppearance.cornerRadius.rawValue)
        }
    }

    @objc private func changeShadow(_ sender: NSSwitch) {
        if !preferencesController.setPortalShadowEnabled(sender.state == .on) {
            sender.state = preferencesController.portalAppearance.shadowEnabled ? .on : .off
        }
    }

    @objc private func changeSpacing(_ sender: NSSlider) {
        let values = PortalSpacing.allCases
        let index = Int(sender.doubleValue.rounded())
        guard values.indices.contains(index) else { return }
        let spacing = values[index]
        if preferencesController.setPortalSpacing(spacing) {
            sender.setAccessibilityValue(spacingTitle(spacing))
        } else {
            sender.doubleValue = Double(preferencesController.portalAppearance.spacing.rawValue)
        }
    }

    private func cornerRadiusTitle(_ cornerRadius: PortalCornerRadius) -> String {
        String(
            format: NSLocalizedString(
                "application.settings.corner_radius_value",
                comment: "Portal corner radius accessibility value"
            ),
            Int(cornerRadius.points)
        )
    }

    private func spacingTitle(_ spacing: PortalSpacing) -> String {
        String(
            format: NSLocalizedString(
                "application.settings.spacing_value",
                comment: "Portal spacing accessibility value"
            ),
            Int(spacing.points)
        )
    }

    private func iconSizeTitle(_ iconSize: IconSize) -> String {
        switch iconSize {
        case .small:
            NSLocalizedString("application.settings.content_size.small", comment: "Small content size")
        case .medium:
            NSLocalizedString("application.settings.content_size.medium", comment: "Medium content size")
        case .large:
            NSLocalizedString("application.settings.content_size.large", comment: "Large content size")
        default:
            NSLocalizedString("application.settings.content_size.medium", comment: "Medium content size")
        }
    }

    private func backgroundStyleTitle(_ style: PortalBackgroundStyle) -> String {
        switch style {
        case .maximumTransparency:
            NSLocalizedString("application.settings.transparency.maximum", comment: "Maximum transparency")
        case .highTransparency:
            NSLocalizedString("application.settings.transparency.high", comment: "High transparency")
        case .standard:
            NSLocalizedString("application.settings.transparency.standard", comment: "Standard transparency")
        case .lowTransparency:
            NSLocalizedString("application.settings.transparency.low", comment: "Low transparency")
        case .minimumTransparency:
            NSLocalizedString("application.settings.transparency.minimum", comment: "Minimum transparency")
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

        var arrangedViews: [NSView] = []
        for (index, row) in rows.enumerated() {
            arrangedViews.append(row)
            if index < rows.count - 1 {
                let separator = NSBox()
                separator.boxType = .separator
                separator.identifier = NSUserInterfaceItemIdentifier(
                    "application-settings.row-separator"
                )
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
