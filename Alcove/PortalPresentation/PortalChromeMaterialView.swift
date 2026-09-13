import AlcoveCore
import AppKit

enum PortalChromeMaterialPath: Equatable {
    case glass
    case visualEffect
    case opaque
}

enum PortalChromeMaterialRole: Equatable {
    case surface
    case controlGroup
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
        role: PortalChromeMaterialRole,
        supportsGlass: Bool,
        accessibility: PortalAccessibilityOptions
    ) -> PortalChromeMaterialPath {
        if accessibility.reduceTransparency {
            return .opaque
        }
        return role == .controlGroup && supportsGlass ? .glass : .visualEffect
    }
}

@MainActor
final class PortalChromeMaterialView: NSView {
    typealias AccessibilityProvider = @MainActor () -> PortalAccessibilityOptions

    private let chromeContentView: NSView
    let role: PortalChromeMaterialRole
    private let accessibilityProvider: AccessibilityProvider
    private let supportsGlass: Bool
    private let notificationCenter: NotificationCenter
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
        role: PortalChromeMaterialRole = .controlGroup,
        backgroundStyle: PortalBackgroundStyle = .standard,
        portalTint: PortalTint = .default,
        cornerRadius: CGFloat = 24,
        accessibilityProvider: @escaping AccessibilityProvider = {
            PortalAccessibilityOptions.current()
        },
        supportsGlass: Bool = PortalChromeMaterialView.runtimeSupportsGlass,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        chromeContentView = contentView
        self.role = role
        self.accessibilityProvider = accessibilityProvider
        self.supportsGlass = supportsGlass
        self.notificationCenter = notificationCenter
        self.backgroundStyle = backgroundStyle
        self.portalTint = portalTint
        surfaceCornerRadius = cornerRadius
        accessibility = accessibilityProvider()
        materialPath = PortalChromeMaterialResolver.resolve(
            role: role,
            supportsGlass: supportsGlass,
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
            role: role,
            supportsGlass: supportsGlass,
            accessibility: accessibility
        )
        chromeContentView.removeFromSuperview()
        NSLayoutConstraint.deactivate(materialConstraints)
        materialConstraints = []
        materialView?.removeFromSuperview()
        surfaceTintView?.removeFromSuperview()
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
        if role == .surface, materialPath == .visualEffect {
            let tint = PortalSurfaceTintView()
            tint.translatesAutoresizingMaskIntoConstraints = false
            addSubview(tint, positioned: .above, relativeTo: material)
            materialConstraints += [
                tint.topAnchor.constraint(equalTo: topAnchor),
                tint.leadingAnchor.constraint(equalTo: leadingAnchor),
                tint.trailingAnchor.constraint(equalTo: trailingAnchor),
                tint.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
            surfaceTintView = tint
        }
        NSLayoutConstraint.activate(materialConstraints)
        materialView = material
        rebuildCount += 1
        applyContrastStyle()
        applySurfaceStyle()
    }

    func updateBackgroundStyle(_ backgroundStyle: PortalBackgroundStyle) {
        guard role == .surface else { return }
        self.backgroundStyle = backgroundStyle
        applySurfaceStyle()
    }

    func updatePortalTint(_ portalTint: PortalTint) {
        guard role == .surface, self.portalTint != portalTint else { return }
        self.portalTint = portalTint
        applySurfaceStyle()
    }

    func updateCornerRadius(_ cornerRadius: CGFloat) {
        guard role == .surface, surfaceCornerRadius != cornerRadius else { return }
        surfaceCornerRadius = cornerRadius
        layer?.cornerRadius = cornerRadius
        materialView?.layer?.cornerRadius = cornerRadius
        if #available(macOS 26.0, *), let glass = materialView as? NSGlassEffectView {
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

    private static var runtimeSupportsGlass: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    private func makeMaterialView() -> NSView {
        switch materialPath {
        case .glass:
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.cornerRadius = cornerRadius
                glass.style = .regular
                glass.contentView = chromeContentView
                return glass
            }
            return makeVisualEffectView()
        case .visualEffect:
            return makeVisualEffectView()
        case .opaque:
            let opaque = PortalOpaqueChromeView()
            opaque.layer?.cornerRadius = cornerRadius
            opaque.layer?.masksToBounds = true
            installChromeContent(in: opaque)
            return opaque
        }
    }

    private func makeVisualEffectView() -> NSVisualEffectView {
        let effect = NSVisualEffectView()
        effect.material = visualEffectMaterial
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        installChromeContent(in: effect)
        return effect
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
            if role == .controlGroup {
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = accessibility.increaseContrast ? 2 : 0
                layer?.borderColor = accessibility.increaseContrast
                    ? NSColor.separatorColor.cgColor
                    : nil
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = accessibility.increaseContrast ? 2 : 0
                layer?.borderColor = accessibility.increaseContrast
                    ? NSColor.separatorColor.cgColor
                    : nil
            }
        }
    }

    private var cornerRadius: CGFloat {
        role == .surface ? surfaceCornerRadius : 999
    }

    private var visualEffectMaterial: NSVisualEffectView.Material {
        guard role == .surface else { return .popover }
        return .popover
    }

    private func applySurfaceStyle() {
        guard role == .surface else {
            alphaValue = 1
            return
        }
        alphaValue = 1
        guard materialPath == .visualEffect else { return }
        let tintAlpha: CGFloat = switch backgroundStyle {
        case .maximumTransparency: 0.04
        case .highTransparency: 0.08
        case .standard: 0.16
        case .lowTransparency: 0.26
        case .minimumTransparency: 0.34
        }
        surfaceTintView?.layer?.backgroundColor = surfaceTintColor
            .withAlphaComponent(tintAlpha)
            .cgColor
        (materialView as? NSVisualEffectView)?.material = visualEffectMaterial
    }

    private var surfaceTintColor: NSColor {
        if let color = portalTint.color {
            return NSColor(
                srgbRed: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 1
            )
        }
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .black
        }
        return .white
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
