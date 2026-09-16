import AlcoveCore
import AppKit

@MainActor
final class PortalTintSwatchButton: NSButton {
    let tint: PortalTint
    private let optionTitle: String
    private(set) var isOptionSelected = false
    private(set) var swatchView = NSView()
    private(set) var checkmarkView = NSImageView()

    init(tint: PortalTint, title: String, target: AnyObject?, action: Selector?) {
        self.tint = tint
        optionTitle = title
        super.init(frame: .zero)
        self.title = ""
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        isBordered = false
        focusRingType = .none
        identifier = NSUserInterfaceItemIdentifier("portal-settings.tint.\(tint.rawValue)")
        toolTip = title
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)

        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 14
        swatchView.layer?.masksToBounds = true
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatchView)

        checkmarkView.imageScaling = .scaleProportionallyDown
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkmarkView)

        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        NSLayoutConstraint.activate([
            swatchView.centerXAnchor.constraint(equalTo: centerXAnchor),
            swatchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 28),
            swatchView.heightAnchor.constraint(equalToConstant: 28),
            checkmarkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 14),
            checkmarkView.heightAnchor.constraint(equalToConstant: 14),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 30)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setSelected(_ selected: Bool) {
        isOptionSelected = selected
        state = selected ? .on : .off
        setAccessibilitySelected(selected)
        setAccessibilityValue(NSNumber(value: selected))
        checkmarkView.image = selected
            ? NSImage(
                systemSymbolName: "checkmark",
                accessibilityDescription: optionTitle
            )?.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
            : nil
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            swatchView.layer?.backgroundColor = swatchColor.cgColor
            swatchView.layer?.borderWidth = isOptionSelected ? 3 : 1
            swatchView.layer?.borderColor = (isOptionSelected
                ? NSColor.controlAccentColor
                : NSColor.separatorColor).cgColor
            checkmarkView.contentTintColor = checkmarkColor
        }
    }

    private var swatchColor: NSColor {
        let isDarkAppearance = effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua
        let color = tint.resolvedColor(forDarkAppearance: isDarkAppearance)
        return NSColor(
            srgbRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: 1
        )
    }

    private var checkmarkColor: NSColor {
        switch tint {
        case .default, .orange, .yellow, .green:
            .labelColor
        case .red, .blue, .indigo, .purple:
            .white
        }
    }
}

@MainActor
final class PortalSettingsCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    init(rows: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        setContentHuggingPriority(.required, for: .vertical)

        var arrangedViews: [NSView] = []
        for (index, row) in rows.enumerated() {
            arrangedViews.append(row)
            if index < rows.count - 1 {
                let separator = NSBox()
                separator.boxType = .separator
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
class PortalFlatCapsuleButton: NSButton {
    private var metrics = PortalCapsuleMetrics(iconSize: .medium)
    private var fixedWidth: CGFloat?
    private var pointerInside = false
    private var pointerTrackingArea: NSTrackingArea?
    private var usesSegmentedStyle = false
    private(set) var usesSelectedAppearance = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCapsule()
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        configureCapsule()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: fixedWidth ?? super.intrinsicContentSize.width + 20,
            height: metrics.height
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(activationStateDidChange),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(activationStateDidChange),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(activationStateDidChange),
                name: NSApplication.didBecomeActiveNotification,
                object: NSApplication.shared
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(activationStateDidChange),
                name: NSApplication.didResignActiveNotification,
                object: NSApplication.shared
            )
        }
        updateCapsuleAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateCapsuleAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        updateCapsuleAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        updateCapsuleAppearance()
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateCapsuleAppearance(isPressed: flag)
    }

    func apply(metrics: PortalCapsuleMetrics, fixedWidth: CGFloat? = nil) {
        self.metrics = metrics
        self.fixedWidth = fixedWidth
        controlSize = metrics.controlSize
        layer?.cornerRadius = metrics.height / 2
        invalidateIntrinsicContentSize()
        updateCapsuleAppearance()
    }

    func setFixedWidth(_ width: CGFloat) {
        guard fixedWidth != width else { return }
        fixedWidth = width
        invalidateIntrinsicContentSize()
    }

    func useSegmentedStyle() {
        usesSegmentedStyle = true
        updateCapsuleAppearance()
    }

    func setCapsuleSelected(_ selected: Bool) {
        usesSelectedAppearance = selected
        updateCapsuleAppearance()
    }

    private func configureCapsule() {
        setButtonType(.momentaryPushIn)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = metrics.height / 2
        layer?.shadowOpacity = 0
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        updateCapsuleAppearance()
    }

    @objc private func activationStateDidChange() {
        updateCapsuleAppearance()
    }

    private func updateCapsuleAppearance(isPressed: Bool = false) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isEmphasized = window.map {
                NSApplication.shared.isActive && $0.isKeyWindow
            } ?? true
            let primaryForeground: NSColor = effectiveAppearance.bestMatch(
                from: [.darkAqua, .aqua]
            ) == .darkAqua ? .white : .black
            let baseBackground: NSColor
            let foreground: NSColor
            if usesSegmentedStyle {
                baseBackground = usesSelectedAppearance
                    ? .tertiarySystemFill
                    : .clear
                foreground = primaryForeground
            } else if usesSelectedAppearance {
                if isEmphasized {
                    baseBackground = .selectedContentBackgroundColor
                } else {
                    baseBackground = NSColor.unemphasizedSelectedContentBackgroundColor.blended(
                        withFraction: 0.10,
                        of: .labelColor
                    ) ?? .unemphasizedSelectedContentBackgroundColor
                }
                foreground = isEmphasized
                    ? .white
                    : .unemphasizedSelectedTextColor
            } else {
                baseBackground = .quaternarySystemFill
                foreground = primaryForeground
            }
            let background: NSColor
            if isPressed {
                background = baseBackground.blended(
                    withFraction: 0.16,
                    of: .labelColor
                ) ?? baseBackground
            } else if pointerInside {
                background = baseBackground.blended(
                    withFraction: 0.08,
                    of: .labelColor
                ) ?? baseBackground
            } else {
                background = baseBackground
            }
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: NSFont.systemFontSize(for: metrics.controlSize),
                        weight: usesSelectedAppearance ? .semibold : .regular
                    ),
                    .foregroundColor: foreground,
                ]
            )
            contentTintColor = foreground
            layer?.backgroundColor = background.cgColor
            if usesSegmentedStyle {
                layer?.borderWidth = usesSelectedAppearance ? 0.75 : 0
                layer?.borderColor = NSColor.separatorColor.cgColor
            } else {
                layer?.borderWidth = usesSelectedAppearance
                    ? (isEmphasized ? 0 : 1)
                    : 0.5
                layer?.borderColor = usesSelectedAppearance && !isEmphasized
                    ? NSColor.secondaryLabelColor.cgColor
                    : NSColor.separatorColor.cgColor
            }
            layer?.shadowOpacity = 0
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

@MainActor
final class PortalTabButton: PortalFlatCapsuleButton {
    private(set) var isTabSelected = false

    init(title: String, metrics: PortalCapsuleMetrics) {
        super.init(title: title)
        toolTip = title
        apply(metrics: metrics, fixedWidth: metrics.tabWidth)
        useSegmentedStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setSelected(_ selected: Bool) {
        let didChange = isTabSelected != selected
        isTabSelected = selected
        setAccessibilitySelected(selected)
        setAccessibilityValue(NSNumber(value: selected))
        setCapsuleSelected(selected)
        if didChange {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

}

@MainActor
final class TabActionTarget: NSObject {
    enum Action {
        case select(FolderTabID)
    }

    private let action: Action
    private weak var owner: TabBarView?

    init(action: Action, owner: TabBarView) {
        self.action = action
        self.owner = owner
    }

    @objc func performAction(_ sender: Any?) {
        switch action {
        case .select(let id):
            owner?.selectTab(id)
        }
    }
}
