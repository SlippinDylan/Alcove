import AppKit

enum PortalChromeMaterialPath: Equatable {
    case glass
    case visualEffect
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
        supportsGlass: Bool,
        accessibility: PortalAccessibilityOptions
    ) -> PortalChromeMaterialPath {
        if accessibility.reduceTransparency {
            return .opaque
        }
        return supportsGlass ? .glass : .visualEffect
    }
}

@MainActor
final class PortalChromeMaterialView: NSView {
    typealias AccessibilityProvider = @MainActor () -> PortalAccessibilityOptions

    private let chromeContentView: NSView
    private let accessibilityProvider: AccessibilityProvider
    private let supportsGlass: Bool
    private let notificationCenter: NotificationCenter
    private var observation: PortalMaterialObservation?
    private var observationGeneration: UInt64 = 0
    private var materialConstraints: [NSLayoutConstraint] = []

    private(set) var materialPath: PortalChromeMaterialPath
    private(set) var materialView: NSView?
    private(set) var accessibility: PortalAccessibilityOptions
    private(set) var rebuildCount = 0

    init(
        contentView: NSView,
        accessibilityProvider: @escaping AccessibilityProvider = {
            PortalAccessibilityOptions.current()
        },
        supportsGlass: Bool = PortalChromeMaterialView.runtimeSupportsGlass,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        chromeContentView = contentView
        self.accessibilityProvider = accessibilityProvider
        self.supportsGlass = supportsGlass
        self.notificationCenter = notificationCenter
        accessibility = accessibilityProvider()
        materialPath = PortalChromeMaterialResolver.resolve(
            supportsGlass: supportsGlass,
            accessibility: accessibility
        )
        super.init(frame: .zero)
        wantsLayer = true
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
        (materialView as? PortalOpaqueChromeView)?.needsDisplay = true
    }

    func rebuildMaterial() {
        accessibility = accessibilityProvider()
        materialPath = PortalChromeMaterialResolver.resolve(
            supportsGlass: supportsGlass,
            accessibility: accessibility
        )
        chromeContentView.removeFromSuperview()
        NSLayoutConstraint.deactivate(materialConstraints)
        materialConstraints = []
        materialView?.removeFromSuperview()

        let material = makeMaterialView()
        material.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material)
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
                glass.cornerRadius = 10
                glass.style = .regular
                glass.contentView = chromeContentView
                return glass
            }
            return makeVisualEffectView()
        case .visualEffect:
            return makeVisualEffectView()
        case .opaque:
            let opaque = PortalOpaqueChromeView()
            installChromeContent(in: opaque)
            return opaque
        }
    }

    private func makeVisualEffectView() -> NSVisualEffectView {
        let effect = NSVisualEffectView()
        effect.material = .headerView
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
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
        layer?.borderWidth = accessibility.increaseContrast ? 2 : 0
        layer?.borderColor = accessibility.increaseContrast ? NSColor.separatorColor.cgColor : nil
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
