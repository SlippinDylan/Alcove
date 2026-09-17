import AlcoveCore
import AppKit

enum PortalChromeMaterialPath: Equatable {
    case translucent
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
    static func resolve(accessibility: PortalAccessibilityOptions) -> PortalChromeMaterialPath {
        accessibility.reduceTransparency ? .opaque : .translucent
    }
}

@MainActor
final class PortalChromeMaterialView: NSView {
    typealias AccessibilityProvider = @MainActor () -> PortalAccessibilityOptions

    private let chromeContentView: NSView
    private let accessibilityProvider: AccessibilityProvider
    private let notificationCenter: NotificationCenter
    private var backgroundStyle: PortalBackgroundStyle
    private var portalTint: PortalTint
    private var surfaceCornerRadius: CGFloat
    private var observation: PortalMaterialObservation?
    private var observationGeneration: UInt64 = 0
    private var materialConstraints: [NSLayoutConstraint] = []

    private(set) var materialPath: PortalChromeMaterialPath
    private(set) var materialView: NSView?
    private(set) var accessibility: PortalAccessibilityOptions
    private(set) var rebuildCount = 0

    init(
        contentView: NSView,
        backgroundStyle: PortalBackgroundStyle = .lowTransparency,
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
        self.backgroundStyle = backgroundStyle
        self.portalTint = portalTint
        surfaceCornerRadius = cornerRadius
        accessibility = accessibilityProvider()
        materialPath = PortalChromeMaterialResolver.resolve(accessibility: accessibility)
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
        materialPath = PortalChromeMaterialResolver.resolve(accessibility: accessibility)
        chromeContentView.removeFromSuperview()
        NSLayoutConstraint.deactivate(materialConstraints)
        materialConstraints = []
        materialView?.removeFromSuperview()

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
        case .translucent:
            let translucent = PortalStaticTranslucentChromeView()
            translucent.layer?.cornerRadius = cornerRadius
            translucent.layer?.masksToBounds = true
            installChromeContent(in: translucent)
            return translucent
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

    private func applySurfaceStyle() {
        guard materialPath == .translucent else { return }
        materialView?.layer?.backgroundColor = staticSurfaceColor
            .withAlphaComponent(staticSurfaceAlpha)
            .cgColor
    }

    private var staticSurfaceColor: NSColor {
        let neutral = isDarkAppearance ? NSColor.black : NSColor.white
        guard portalTint != .default else { return neutral }
        return neutral.blended(withFraction: 0.20, of: surfaceTintColor) ?? neutral
    }

    private var staticSurfaceAlpha: CGFloat {
        switch backgroundStyle {
        case .highestTransparency: 0.32
        case .maximumTransparency: 0.42
        case .highTransparency: 0.52
        case .standard: 0.62
        case .lowTransparency: 0.72
        case .minimumTransparency: 0.72
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

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var cornerRadius: CGFloat {
        surfaceCornerRadius
    }
}

@MainActor
private final class PortalStaticTranslucentChromeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
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
