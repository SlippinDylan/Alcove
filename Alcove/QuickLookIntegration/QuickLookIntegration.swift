import AppKit
import Quartz

@MainActor
protocol QuickLookPanelManaging: AnyObject {
    var identity: ObjectIdentifier { get }
    var isVisible: Bool { get }
    var currentPreviewItemIndex: Int { get set }
    var dataSource: (any QLPreviewPanelDataSource)? { get set }
    var delegate: AnyObject? { get set }
    var currentController: AnyObject? { get }

    func reloadData()
    func updateController()
    func present()
    func dismiss()
}

@MainActor
private final class SystemQuickLookPanel: QuickLookPanelManaging {
    private let panel: QLPreviewPanel

    init(panel: QLPreviewPanel) {
        self.panel = panel
    }

    var identity: ObjectIdentifier { ObjectIdentifier(panel) }
    var isVisible: Bool { panel.isVisible }
    var currentPreviewItemIndex: Int {
        get { panel.currentPreviewItemIndex }
        set { panel.currentPreviewItemIndex = newValue }
    }
    var dataSource: (any QLPreviewPanelDataSource)? {
        get { panel.dataSource }
        set { panel.dataSource = newValue }
    }
    var delegate: AnyObject? {
        get { panel.delegate }
        set { panel.delegate = newValue }
    }
    var currentController: AnyObject? { panel.currentController as AnyObject? }

    func reloadData() {
        panel.reloadData()
    }

    func updateController() {
        panel.updateController()
    }

    func present() {
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel.orderOut(nil)
    }
}

@MainActor
final class QuickLookIntegration: NSResponder,
    @MainActor QLPreviewPanelDataSource,
    @MainActor QLPreviewPanelDelegate
{
    private let panelProvider: () -> (any QuickLookPanelManaging)?
    private var previewItems: [URLPreviewItem] = []
    private let unavailableItem = UnavailablePreviewItem()
    private weak var installedWindow: NSWindow?
    private var originalWindowResponder: NSResponder?
    private var windowCloseObserver: NSObjectProtocol?
    private var controlledPanel: (any QuickLookPanelManaging)?

    init(panelProvider: @escaping () -> (any QuickLookPanelManaging)? = {
        guard let panel = QLPreviewPanel.shared() else { return nil }
        return SystemQuickLookPanel(panel: panel)
    }) {
        self.panelProvider = panelProvider
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var selectedURLs: [URL] {
        previewItems.map(\.url)
    }

    /// Inserts this responder between the portal window and its former successor.
    func install(in window: NSWindow) {
        detach()
        originalWindowResponder = window.nextResponder
        nextResponder = originalWindowResponder ?? NSApp
        window.nextResponder = self
        installedWindow = window
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.detach()
            }
        }
    }

    func installIfNeeded(in window: NSWindow) {
        guard installedWindow !== window || window.nextResponder !== self else { return }
        install(in: window)
    }

    /// Removes the responder-chain link and any Objective-C assign references.
    func detach() {
        previewItems = []
        relinquishControl()
        if let installedWindow, installedWindow.nextResponder === self {
            installedWindow.nextResponder = originalWindowResponder
        }
        installedWindow = nil
        originalWindowResponder = nil
        nextResponder = nil
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
            self.windowCloseObserver = nil
        }
    }

    /// Replaces the data-source snapshot in the exact order supplied by the grid.
    func updateSelection(_ urls: [URL]) {
        previewItems = urls.map(URLPreviewItem.init(url:))
        if previewItems.isEmpty {
            relinquishControl()
            return
        }
        guard let controlledPanel else { return }
        guard ownsControl(of: controlledPanel) else {
            self.controlledPanel = nil
            return
        }
        controlledPanel.reloadData()
        if !previewItems.indices.contains(controlledPanel.currentPreviewItemIndex) {
            controlledPanel.currentPreviewItemIndex = 0
        }
    }

    /// Applies the verified Space policy: no selection does nothing; a visible Alcove-owned panel closes.
    func handleSpace(for urls: [URL]) {
        guard !urls.isEmpty else {
            updateSelection([])
            return
        }
        if let controlledPanel {
            if ownsControl(of: controlledPanel), controlledPanel.isVisible {
                controlledPanel.dismiss()
                return
            }
            if !ownsControl(of: controlledPanel) {
                self.controlledPanel = nil
            }
        }
        updateSelection(urls)
        presentPreview()
    }

    /// Invalidates the current tab's selection as well as any panel ownership.
    func invalidateSelection() {
        previewItems = []
        relinquishControl()
    }

    /// Call on a tab switch or any portal lifecycle transition that invalidates this selection.
    func relinquishControl() {
        guard let controlledPanel else { return }
        let wasCurrentController = controlledPanel.currentController === self
        if ownsControl(of: controlledPanel) {
            if controlledPanel.isVisible {
                controlledPanel.dismiss()
            }
            clearReferencesOwnedBySelf(in: controlledPanel)
        }
        self.controlledPanel = nil
        if wasCurrentController {
            controlledPanel.updateController()
        }
    }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated {
            !previewItems.isEmpty
        }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            guard let panel else { return }
            beginControl(of: SystemQuickLookPanel(panel: panel))
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            guard let panel, let controlledPanel else { return }
            let systemPanel = SystemQuickLookPanel(panel: panel)
            guard isSamePanel(systemPanel, controlledPanel) else { return }
            clearReferencesOwnedBySelf(in: controlledPanel)
            self.controlledPanel = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        guard previewItems.indices.contains(index) else { return unavailableItem }
        return previewItems[index]
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        false
    }

    private func presentPreview() {
        guard let panel = panelProvider() else { return }
        panel.updateController()
        guard panel.currentController === self, ownsControl(of: panel) else { return }
        panel.present()
    }

    func beginControl(of panel: any QuickLookPanelManaging) {
        if let controlledPanel, !isSamePanel(controlledPanel, panel) {
            clearReferencesOwnedBySelf(in: controlledPanel)
        }
        controlledPanel = panel
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        if !previewItems.isEmpty, !previewItems.indices.contains(panel.currentPreviewItemIndex) {
            panel.currentPreviewItemIndex = 0
        }
    }

    private func clearReferencesOwnedBySelf(in panel: any QuickLookPanelManaging) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
    }

    private func ownsControl(of panel: any QuickLookPanelManaging) -> Bool {
        panel.currentController === self
            && panel.dataSource === self
            && panel.delegate === self
    }

    private func isSamePanel(
        _ lhs: any QuickLookPanelManaging,
        _ rhs: any QuickLookPanelManaging
    ) -> Bool {
        lhs.identity == rhs.identity
    }
}

private final class URLPreviewItem: NSObject, QLPreviewItem {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    var previewItemURL: URL? { url }
}

private final class UnavailablePreviewItem: NSObject, QLPreviewItem {
    var previewItemURL: URL? { nil }
}
