// ExperimentWindowController.swift
// Alcove Spike 0.1B — Desktop Window Strategy Model
// Disposable harness; not production architecture.

import AppKit

/// Manages a single experiment window, its diagnostics display, and all
/// delegate/notification-driven state refresh.
///
/// Strong ownership: the AppDelegate holds this controller, and the controller
/// holds the window. Closing the window does not deallocate the controller;
/// the AppDelegate explicitly nils its reference to allow clean recreation.
final class ExperimentWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Properties

    let preset: StrategyPreset
    var onWindowWillClose: (() -> Void)?
    private let diagnosticsView = DiagnosticsView()

    // MARK: - Initialization

    init(preset: StrategyPreset) {
        self.preset = preset

        let window = Self.makeWindow(preset: preset)
        super.init(window: window)

        window.delegate = self
        setupContentView()
        registerNotifications()
        refreshDiagnostics()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Window Factory

    private static func makeWindow(preset: StrategyPreset) -> AlcoveSpikeWindow {
        let contentRect = NSRect(x: 200, y: 200, width: 600, height: 500)
        let styleMask: NSWindow.StyleMask = [
            .resizable, .titled, .closable, .miniaturizable,
        ]
        let window = AlcoveSpikeWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false,
            isKeyEligible: preset.isKeyEligible
        )
        window.title = "Alcove Spike — \(preset.description)"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true

        // Apply strategy configuration from the typed preset.
        window.level = preset.windowLevel
        window.collectionBehavior = preset.collectionBehavior

        // Translucent background via NSVisualEffectView
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .underPageBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.appearance = NSAppearance(named: .darkAqua)
        window.contentView = visualEffect

        return window
    }

    // MARK: - Content View Setup

    private func setupContentView() {
        guard let contentView = window?.contentView else { return }

        contentView.addSubview(diagnosticsView)

        NSLayoutConstraint.activate([
            diagnosticsView.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: 28),
            diagnosticsView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 20),
            diagnosticsView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -20),
            diagnosticsView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Show / Activate

    /// Orders the window front and makes it key (if eligible).
    func showAndActivate() {
        NSApp.activate(ignoringOtherApps: true)
        if preset.isKeyEligible {
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFront(nil)
        }
        refreshDiagnostics()
    }

    // MARK: - Notification Registration

    private func registerNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self, selector: #selector(appDidActivate(_:)),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(
            self, selector: #selector(appDidDeactivate(_:)),
            name: NSApplication.didResignActiveNotification, object: nil)
        nc.addObserver(
            self, selector: #selector(screenDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    // MARK: - Notification Handlers

    @objc private func appDidActivate(_ note: Notification) {
        logEvent("applicationDidBecomeActive")
        refreshDiagnostics()
    }

    @objc private func appDidDeactivate(_ note: Notification) {
        logEvent("applicationDidResignActive")
        refreshDiagnostics()
    }

    @objc private func screenDidChange(_ note: Notification) {
        logEvent("didChangeScreenParameters")
        refreshDiagnostics()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        logEvent("windowDidBecomeKey")
        refreshDiagnostics()
    }

    func windowDidResignKey(_ notification: Notification) {
        logEvent("windowDidResignKey")
        refreshDiagnostics()
    }

    func windowDidBecomeMain(_ notification: Notification) {
        logEvent("windowDidBecomeMain")
        refreshDiagnostics()
    }

    func windowDidResignMain(_ notification: Notification) {
        logEvent("windowDidResignMain")
        refreshDiagnostics()
    }

    func windowDidMove(_ notification: Notification) {
        logEvent("windowDidMove")
        refreshDiagnostics()
    }

    func windowDidResize(_ notification: Notification) {
        logEvent("windowDidResize")
        refreshDiagnostics()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        logEvent("windowDidChangeScreen")
        refreshDiagnostics()
    }

    func windowWillClose(_ notification: Notification) {
        logEvent("windowWillClose")
        onWindowWillClose?()
    }

    // MARK: - Diagnostics Refresh

    private func refreshDiagnostics() {
        let spikeWindow = window as? AlcoveSpikeWindow
        diagnosticsView.refresh(
            preset: preset,
            window: window,
            actualCanBecomeKey: spikeWindow?.canBecomeKey ?? false,
            activationPolicy: NSApp.activationPolicy()
        )
    }

    // MARK: - Logging

    private func logEvent(_ name: String) {
        let timestamp = Self.dateFormatter.string(from: Date())
        let wFrame = window.map {
            String(
                format: "(%.0f,%.0f %.0fx%.0f)",
                $0.frame.origin.x, $0.frame.origin.y,
                $0.frame.size.width, $0.frame.size.height)
        } ?? "nil"
        let screenID = window?.screen.flatMap { screen -> String? in
            let desc = screen.deviceDescription
            guard let n = desc[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return String(n.uint32Value)
        } ?? "N/A"
        print("[\(timestamp)] EVENT: \(name) | preset=\(preset.identifier) | window=\(wFrame) screen=\(screenID)")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
