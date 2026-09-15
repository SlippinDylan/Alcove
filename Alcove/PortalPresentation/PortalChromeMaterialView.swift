import AlcoveCore
import AppKit

enum PortalChromeMaterialPath: Equatable {
    case glass
    case frosted
    case opaque
}

struct PortalAccessibilityOptions: Equatable {
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let reduceMotion: Bool

    @MainActor
    static func current() -> PortalAccessibilityOptions {
        let workspace = NSWorkspace.shared
        return PortalAccessibilityOptions(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion
        )
    }
}

enum PortalChromeMaterialResolver {
    static func resolve(
        backgroundType: PortalBackgroundType,
        accessibility: PortalAccessibilityOptions
    ) -> PortalChromeMaterialPath {
        if accessibility.reduceTransparency {
            return .opaque
        }
        return switch backgroundType {
        case .liquidGlass: .glass
        case .frostedGlass: .frosted
        }
    }
}

@MainActor
final class PortalChromeMaterialView: NSView {
    typealias AccessibilityProvider = @MainActor () -> PortalAccessibilityOptions

    private let chromeContentView: NSView
    private let accessibilityProvider: AccessibilityProvider
    private let notificationCenter: NotificationCenter
    private var backgroundType: PortalBackgroundType
    private var backgroundStyle: PortalBackgroundStyle
    private var portalTint: PortalTint
    private var surfaceCornerRadius: CGFloat
    private var observation: PortalMaterialObservation?
    private var observationGeneration: UInt64 = 0
    private var materialConstraints: [NSLayoutConstraint] = []

    private(set) var materialPath: PortalChromeMaterialPath
    private(set) var materialView: NSView?
    private(set) var surfaceTintView: NSView?
    private(set) var accessibility: PortalAccessibilityOptions
    private(set) var rebuildCount = 0

    init(
        contentView: NSView,
        backgroundType: PortalBackgroundType = .liquidGlass,
        backgroundStyle: PortalBackgroundStyle = .standard,
        portalTint: PortalTint = .default,
        cornerRadius: CGFloat = 24,
        accessibilityProvider: @escaping AccessibilityProvider = {
            PortalAccessibilityOptions.current()
        },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        chromeContentView = contentView
        self.accessibilityProvider = accessibilityProvider
        self.notificationCenter = notificationCenter
        self.backgroundType = backgroundType
        self.backgroundStyle = backgroundStyle
        self.portalTint = portalTint
        surfaceCornerRadius = cornerRadius
        accessibility = accessibilityProvider()
        materialPath = PortalChromeMaterialResolver.resolve(
            backgroundType: backgroundType,
            accessibility: accessibility
        )
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        rebuildMaterial()
        startObserving()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyContrastStyle()
        applySurfaceStyle()
        (materialView as? PortalOpaqueChromeView)?.needsDisplay = true
    }

    func rebuildMaterial() {
        accessibility = accessibilityProvider()
        materialPath = PortalChromeMaterialResolver.resolve(
            backgroundType: backgroundType,
            accessibility: accessibility
        )
        chromeContentView.removeFromSuperview()
        NSLayoutConstraint.deactivate(materialConstraints)
        materialConstraints = []
        materialView?.removeFromSuperview()
        surfaceTintView = nil

        let material = makeMaterialView()
        material.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material, positioned: .below, relativeTo: nil)
        materialConstraints = [
            material.topAnchor.constraint(equalTo: topAnchor),
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        NSLayoutConstraint.activate(materialConstraints)
        materialView = material
        rebuildCount += 1
        applyContrastStyle()
        applySurfaceStyle()
    }

    func updateBackgroundStyle(_ backgroundStyle: PortalBackgroundStyle) {
        self.backgroundStyle = backgroundStyle
        applySurfaceStyle()
    }

    func updateBackgroundType(_ backgroundType: PortalBackgroundType) {
        guard self.backgroundType != backgroundType else { return }
        self.backgroundType = backgroundType
        rebuildMaterial()
    }

    func updatePortalTint(_ portalTint: PortalTint) {
        guard self.portalTint != portalTint else { return }
        self.portalTint = portalTint
        applySurfaceStyle()
    }

    func updateCornerRadius(_ cornerRadius: CGFloat) {
        guard surfaceCornerRadius != cornerRadius else { return }
        surfaceCornerRadius = cornerRadius
        layer?.cornerRadius = cornerRadius
        materialView?.layer?.cornerRadius = cornerRadius
        if let glass = materialView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        }
    }

    func startObserving() {
        guard observation == nil else { return }
        observationGeneration += 1
        let generation = observationGeneration
        let token = notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            _ = Task { @MainActor [weak self] in
                guard let self,
                      self.observation != nil,
                      self.observationGeneration == generation else {
                    return
                }
                self.rebuildMaterial()
            }
        }
        observation = PortalMaterialObservation(center: notificationCenter, token: token)
    }

    func stopObserving() {
        observationGeneration += 1
        observation = nil
    }

    private func makeMaterialView() -> NSView {
        switch materialPath {
        case .glass:
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.contentView = chromeContentView
            return glass
        case .frosted:
            let effect = NSVisualEffectView()
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.masksToBounds = true
            let tint = PortalSurfaceTintView()
            tint.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(tint)
            installChromeContent(in: effect)
            NSLayoutConstraint.activate([
                tint.topAnchor.constraint(equalTo: effect.topAnchor),
                tint.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                tint.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                tint.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            surfaceTintView = tint
            return effect
        case .opaque:
            let opaque = PortalOpaqueChromeView()
            opaque.layer?.cornerRadius = cornerRadius
            opaque.layer?.masksToBounds = true
            installChromeContent(in: opaque)
            return opaque
        }
    }

    private func installChromeContent(in container: NSView) {
        chromeContentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(chromeContentView)
        NSLayoutConstraint.activate([
            chromeContentView.topAnchor.constraint(equalTo: container.topAnchor),
            chromeContentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            chromeContentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            chromeContentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func applyContrastStyle() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = accessibility.increaseContrast ? 2 : 0
            layer?.borderColor = accessibility.increaseContrast
                ? NSColor.separatorColor.cgColor
                : nil
        }
    }

    private var cornerRadius: CGFloat {
        surfaceCornerRadius
    }

    private func applySurfaceStyle() {
        alphaValue = 1
        switch materialPath {
        case .glass:
            guard let glass = materialView as? NSGlassEffectView else { return }
            applyGlassSurfaceStyle(glass)
        case .frosted:
            surfaceTintView?.layer?.backgroundColor = frostedSurfaceTintColor
                .withAlphaComponent(frostedTintAlpha)
                .cgColor
        case .opaque:
            break
        }
    }

    private func applyGlassSurfaceStyle(_ glass: NSGlassEffectView) {
        glass.style = switch backgroundStyle {
        case .maximumTransparency, .highTransparency:
            .clear
        case .standard, .lowTransparency, .minimumTransparency:
            .regular
        }

        let tintAlpha: CGFloat?
        if portalTint == .default {
            tintAlpha = switch backgroundStyle {
            case .maximumTransparency, .standard:
                nil
            case .highTransparency:
                0.06
            case .lowTransparency:
                0.12
            case .minimumTransparency:
                0.20
            }
        } else {
            tintAlpha = switch backgroundStyle {
            case .maximumTransparency:
                0.04
            case .highTransparency:
                0.08
            case .standard:
                0.16
            case .lowTransparency:
                0.26
            case .minimumTransparency:
                0.34
            }
        }

        glass.tintColor = tintAlpha.map {
            surfaceTintColor.withAlphaComponent($0)
        }
    }

    private var surfaceTintColor: NSColor {
        let color = portalTint.resolvedColor(forDarkAppearance: isDarkAppearance)
        return NSColor(
            srgbRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: 1
        )
    }

    private var frostedSurfaceTintColor: NSColor {
        guard portalTint == .default else { return surfaceTintColor }
        return isDarkAppearance ? .black : .white
    }

    private var frostedTintAlpha: CGFloat {
        if portalTint == .default {
            return switch backgroundStyle {
            case .maximumTransparency: 0.12
            case .highTransparency: 0.24
            case .standard: 0.36
            case .lowTransparency: 0.48
            case .minimumTransparency: 0.60
            }
        }
        return switch backgroundStyle {
        case .maximumTransparency: 0.04
        case .highTransparency: 0.08
        case .standard: 0.16
        case .lowTransparency: 0.26
        case .minimumTransparency: 0.34
        }
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

@MainActor
private final class PortalSurfaceTintView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
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
private final class PortalOpaqueChromeView: NSView {
    override var isOpaque: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}

private final class PortalMaterialObservation {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(center: NotificationCenter, token: any NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    deinit {
        center.removeObserver(token)
    }
}
