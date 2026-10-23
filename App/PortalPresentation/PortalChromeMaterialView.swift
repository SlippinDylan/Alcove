import AlcoveCore
import AppKit

enum PortalChromeMaterialPath: Equatable {
    case styled
    case accessibilityOpaque
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
        accessibility.reduceTransparency ? .accessibilityOpaque : .styled
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
    private(set) var surfaceStyle: PortalSurfaceStyle
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
        surfaceStyle: PortalSurfaceStyle = .translucent,
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
        self.surfaceStyle = surfaceStyle
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

    func updateSurfaceStyle(_ surfaceStyle: PortalSurfaceStyle) {
        guard self.surfaceStyle != surfaceStyle else { return }
        self.surfaceStyle = surfaceStyle
        applyContrastStyle()
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
        case .styled:
            let surface = PortalStaticSurfaceView()
            surface.layer?.cornerRadius = cornerRadius
            surface.layer?.masksToBounds = true
            installChromeContent(in: surface)
            return surface
        case .accessibilityOpaque:
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
            layer?.borderWidth = accessibility.increaseContrast ? 2 : (surfaceStyle == .outline ? 1 : 0)
            layer?.borderColor = accessibility.increaseContrast
                ? NSColor.separatorColor.cgColor
                : (surfaceStyle == .outline ? NSColor.labelColor.withAlphaComponent(0.35).cgColor : nil)
        }
    }

    private func applySurfaceStyle() {
        guard materialPath == .styled,
              let material = materialView as? PortalStaticSurfaceView else { return }
        let color: NSColor
        let alpha: CGFloat
        switch surfaceStyle {
        case .translucent:
            color = staticSurfaceColor
            alpha = staticSurfaceAlpha
        case .matte, .gradient, .paper:
            color = tintedMatteColor
            alpha = 1
        case .smoke:
            color = tintedMatteColor
            alpha = 0.85 + (staticSurfaceAlpha - 0.32) * 0.25
        case .softTint:
            let tint = portalTint == .default
                ? NSColor(srgbRed: 0.45, green: 0.56, blue: 0.49, alpha: 1)
                : surfaceTintColor
            color = matteColor.blended(withFraction: isDarkAppearance ? 0.24 : 0.18, of: tint) ?? matteColor
            alpha = 1
        case .outline:
            color = staticSurfaceColor
            alpha = 0.10 + (staticSurfaceAlpha - 0.32) * 0.25
        }
        material.configure(
            color: color.withAlphaComponent(alpha),
            style: surfaceStyle,
            isDark: isDarkAppearance
        )
    }

    private var matteColor: NSColor {
        isDarkAppearance
            ? NSColor(srgbRed: 0.105, green: 0.115, blue: 0.13, alpha: 1)
            : NSColor(srgbRed: 0.955, green: 0.95, blue: 0.935, alpha: 1)
    }

    private var tintedMatteColor: NSColor {
        guard portalTint != .default else { return matteColor }
        return matteColor.blended(withFraction: 0.08, of: surfaceTintColor) ?? matteColor
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
private final class PortalStaticSurfaceView: NSView {
    private var surfaceStyle: PortalSurfaceStyle = .translucent
    private var surfaceColor: NSColor = .clear
    private var isDark = false

    // A shared small tile keeps the paper finish deterministic and independent of panel size.
    private static let paperTexture = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
        NSColor.clear.setFill()
        rect.fill()
        for y in 0..<64 {
            for x in 0..<64 {
                let value = (x * 73 + y * 151 + x * y * 17) % 101
                if value < 18 {
                    NSColor(white: value < 9 ? 0 : 1, alpha: 0.035).setFill()
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
        }
        return true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(color: NSColor, style: PortalSurfaceStyle, isDark: Bool) {
        surfaceColor = color
        surfaceStyle = style
        self.isDark = isDark
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // One drawing path owns the base and decoration, including replacement of old translucent pixels.
        surfaceColor.setFill()
        dirtyRect.fill(using: .copy)
        switch surfaceStyle {
        case .gradient:
            let highlight = surfaceColor.blended(withFraction: isDark ? 0.055 : 0.025, of: .white)
                ?? surfaceColor
            let shade = surfaceColor.blended(withFraction: 0.025, of: .black) ?? surfaceColor
            NSGradient(starting: highlight, ending: shade)?.draw(in: bounds, angle: -90)
        case .paper:
            NSColor(patternImage: Self.paperTexture).setFill()
            dirtyRect.fill(using: .sourceOver)
        default:
            break
        }
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
