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
    /// Retained only to decode existing preferences and layout backups.
    case maximum

    static let selectableCases: [PortalSpacing] = [.minimum, .small, .medium, .large]

    var normalizedSelection: PortalSpacing {
        self == .maximum ? .large : self
    }

    var points: CGFloat {
        switch self {
        case .minimum: 2
        case .small: 4
        case .medium: 6
        case .large: 8
        case .maximum: 8
        }
    }
}

struct PortalAppearancePreferences: Equatable, Sendable {
    static let defaults = PortalAppearancePreferences(
        iconSize: .medium,
        backgroundStyle: .lowTransparency,
        cornerRadius: .medium,
        spacing: .small,
        shadowEnabled: false
    )

    var iconSize: IconSize
    var backgroundStyle: PortalBackgroundStyle
    var cornerRadius: PortalCornerRadius
    var spacing: PortalSpacing
    var shadowEnabled: Bool

    init(
        iconSize: IconSize = .medium,
        backgroundStyle: PortalBackgroundStyle = .lowTransparency,
        cornerRadius: PortalCornerRadius,
        spacing: PortalSpacing,
        shadowEnabled: Bool
    ) {
        self.iconSize = iconSize
        self.backgroundStyle = backgroundStyle.normalizedSelection
        self.cornerRadius = cornerRadius
        self.spacing = spacing.normalizedSelection
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
        if portalAppearance.backgroundStyle != backgroundStyle {
            userDefaults.set(
                portalAppearance.backgroundStyle.rawValue,
                forKey: Key.portalBackgroundStyle
            )
        }
        if portalAppearance.spacing != spacing {
            userDefaults.set(portalAppearance.spacing.rawValue, forKey: Key.portalSpacing)
        }
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
        let backgroundStyle = backgroundStyle.normalizedSelection
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
        let spacing = spacing.normalizedSelection
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
        let normalizedAppearance = PortalAppearancePreferences(
            iconSize: appearance.iconSize,
            backgroundStyle: appearance.backgroundStyle,
            cornerRadius: appearance.cornerRadius,
            spacing: appearance.spacing,
            shadowEnabled: appearance.shadowEnabled
        )
        portalAppearance = normalizedAppearance
        userDefaults.set(Double(normalizedAppearance.iconSize.rawValue), forKey: Key.portalIconSize)
        userDefaults.set(
            normalizedAppearance.backgroundStyle.rawValue,
            forKey: Key.portalBackgroundStyle
        )
        userDefaults.set(normalizedAppearance.cornerRadius.rawValue, forKey: Key.portalCornerRadius)
        userDefaults.set(normalizedAppearance.spacing.rawValue, forKey: Key.portalSpacing)
        userDefaults.set(normalizedAppearance.shadowEnabled, forKey: Key.portalShadowEnabled)
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

enum ApplicationLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
}

@MainActor
protocol ApplicationLanguageControlling: AnyObject {
    var selectedLanguage: ApplicationLanguage { get }
    @discardableResult func setSelectedLanguage(_ language: ApplicationLanguage) -> Bool
}

@MainActor
final class ApplicationLanguageController: ApplicationLanguageControlling {
    private enum Key {
        static let selection = "application.language"
        static let appleLanguages = "AppleLanguages"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [Key.selection: ApplicationLanguage.system.rawValue])
    }

    var selectedLanguage: ApplicationLanguage {
        userDefaults.string(forKey: Key.selection)
            .flatMap(ApplicationLanguage.init(rawValue:)) ?? .system
    }

    @discardableResult
    func setSelectedLanguage(_ language: ApplicationLanguage) -> Bool {
        guard language != selectedLanguage else { return false }
        userDefaults.set(language.rawValue, forKey: Key.selection)
        switch language {
        case .system:
            userDefaults.removeObject(forKey: Key.appleLanguages)
        case .english, .simplifiedChinese, .traditionalChinese:
            userDefaults.set([language.rawValue], forKey: Key.appleLanguages)
        }
        return true
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
        guard let infoDictionary = bundle.infoDictionary,
              infoDictionary["CFBundleShortVersionString"] is String,
              infoDictionary["CFBundleVersion"] is String else {
            preconditionFailure("The app bundle must contain version metadata")
        }
        self.init(infoDictionary: infoDictionary)
    }

    var versionAndBuild: String {
        "\(version) (\(build))"
    }
}
