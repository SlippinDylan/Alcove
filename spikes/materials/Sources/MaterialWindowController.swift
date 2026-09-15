// MaterialWindowController.swift
// Alcove Spike 0.4A — Material Compatibility Boundary Bootstrap

import AppKit
import CoreGraphics

final class NotificationObservation {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    func cancel() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit {
        cancel()
    }
}

@MainActor
final class MaterialWindowController: NSWindowController {
    typealias AccessibilityProvider = @MainActor () -> AccessibilityDisplayOptions

    private(set) var levelCandidate: WindowLevelCandidate
    private(set) var resolvedPath: ResolvedMaterialPath
    private(set) var materialContainer: NSView?
    private(set) var chromeView: MaterialChromeView?
    private(set) var canvasView: NSView?
    private(set) var diagnosticsText = ""
    private(set) var accessibilityChangeCount = 0

    var onClose: (() -> Void)?
    var onAccessibilityChange: (() -> Void)?

    private let accessibilityProvider: AccessibilityProvider
    private var diagnosticsLabel: NSTextField?
    private var accessibilityObservation: NotificationObservation?
    private var activeObservationID: UUID?

    var isAccessibilityObserverActive: Bool {
        accessibilityObservation != nil && activeObservationID != nil
    }

    init(
        levelCandidate: WindowLevelCandidate = .desktopCandidate,
        accessibilityProvider: @escaping AccessibilityProvider = { AccessibilityDisplayOptions.current() }
    ) {
        self.levelCandidate = levelCandidate
        self.accessibilityProvider = accessibilityProvider
        self.resolvedPath = MaterialResolver.resolve(
            accessibility: accessibilityProvider()
        )

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Alcove Material Spike"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 400, height: 300)
        window.center()

        super.init(window: window)
        window.delegate = self
        buildLayout()
        applyLevel()
        startAccessibilityObserver()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setLevelCandidate(_ candidate: WindowLevelCandidate) {
        guard candidate != levelCandidate else { return }
        levelCandidate = candidate
        applyLevel()
        updateDiagnostics()
    }

    func rebuildMaterial() {
        resolvedPath = MaterialResolver.resolve(
            accessibility: accessibilityProvider()
        )
        buildLayout()
    }

    func startAccessibilityObserver() {
        guard accessibilityObservation == nil else { return }
        let observationID = UUID()
        activeObservationID = observationID
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.activeObservationID == observationID else { return }
                self.accessibilityChangeCount += 1
                self.rebuildMaterial()
                self.onAccessibilityChange?()
            }
        }
        accessibilityObservation = NotificationObservation(center: center, token: token)
    }

    func stopAccessibilityObserver() {
        activeObservationID = nil
        accessibilityObservation?.cancel()
        accessibilityObservation = nil
    }

    func updateDiagnostics() {
        let accessibility = accessibilityProvider()
        let observerState = isAccessibilityObserverActive ? "active" : "inactive"
        diagnosticsText = """
        Material: \(resolvedPath.description)
        Window Level: \(levelCandidate.windowLevel.rawValue) | Candidate: \(levelCandidate.description)
        Reduce Transparency: \(accessibility.reduceTransparency) | Increase Contrast: \(accessibility.increaseContrast)
        Accessibility Observer: \(observerState)
        """
        diagnosticsLabel?.stringValue = diagnosticsText
    }

    private func applyLevel() {
        window?.level = levelCandidate.windowLevel
    }

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }
        materialContainer?.removeFromSuperview()
        canvasView?.removeFromSuperview()

        let materialAndChrome = buildMaterialAndChrome()
        let material = materialAndChrome.material
        let chrome = materialAndChrome.chrome
        material.translatesAutoresizingMaskIntoConstraints = false
        materialContainer = material
        chromeView = chrome

        let canvas = NSView()
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvasView = canvas

        let canvasLabel = NSTextField(labelWithString: "File Content Canvas")
        canvasLabel.font = .systemFont(ofSize: 14, weight: .medium)
        canvasLabel.textColor = .tertiaryLabelColor
        canvasLabel.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(canvasLabel)

        let diagnostics = NSTextField(labelWithString: "")
        diagnostics.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnostics.textColor = .secondaryLabelColor
        diagnostics.maximumNumberOfLines = 0
        diagnostics.lineBreakMode = .byWordWrapping
        diagnostics.translatesAutoresizingMaskIntoConstraints = false
        diagnosticsLabel = diagnostics
        canvas.addSubview(diagnostics)

        contentView.addSubview(material)
        contentView.addSubview(canvas)
        NSLayoutConstraint.activate([
            material.topAnchor.constraint(equalTo: contentView.topAnchor),
            material.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            material.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            material.heightAnchor.constraint(equalToConstant: 50),
            canvas.topAnchor.constraint(equalTo: material.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            canvasLabel.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            canvasLabel.centerYAnchor.constraint(equalTo: canvas.centerYAnchor, constant: -20),
            diagnostics.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 12),
            diagnostics.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -12),
            diagnostics.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -12),
        ])
        updateDiagnostics()
    }

    private func buildMaterialAndChrome() -> (material: NSView, chrome: MaterialChromeView) {
        switch resolvedPath {
        case .glass:
            return buildGlassMaterial()
        case .opaqueAccessibility:
            return buildOpaqueMaterial()
        }
    }

    private func buildGlassMaterial() -> (material: NSView, chrome: MaterialChromeView) {
        let chrome = MaterialChromeView { content in
            let glass = NSGlassEffectView()
            glass.contentView = content
            glass.cornerRadius = 10
            glass.style = .regular
            return glass
        }
        chrome.translatesAutoresizingMaskIntoConstraints = false

        let container = NSGlassEffectContainerView()
        container.spacing = 8
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.contentView = content
        content.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.topAnchor.constraint(equalTo: content.topAnchor),
            chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        return (container, chrome)
    }

    private func buildOpaqueMaterial() -> (material: NSView, chrome: MaterialChromeView) {
        let chrome = MaterialChromeView()
        chrome.translatesAutoresizingMaskIntoConstraints = false
        let opaque = OpaqueChromeBackgroundView()
        opaque.addSubview(chrome)
        constrain(chrome, to: opaque)
        return (opaque, chrome)
    }

    private func constrain(_ child: NSView, to parent: NSView) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}

extension MaterialWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopAccessibilityObserver()
        onClose?()
        window?.delegate = nil
        window = nil
    }
}
