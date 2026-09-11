import AppKit
import AlcoveCore

@MainActor
final class PortalWindowController: NSWindowController, PortalWindowPresenting {
    var onFrameChange: ((NSRect) -> Void)?
    var onSelectTab: ((FolderTabID) -> Void)? {
        didSet { portalViewController.onSelectTab = onSelectTab }
    }
    var onAddTab: (() -> Void)? {
        didSet { portalViewController.onAddTab = onAddTab }
    }
    var onCloseTab: ((FolderTabID) -> Void)? {
        didSet { portalViewController.onCloseTab = onCloseTab }
    }
    private let portalViewController: PortalViewController
    private let quickLookIntegration: QuickLookIntegration

    init(
        portal: Portal,
        loadingCoordinator: FolderLoadingCoordinator,
        initialFrame: NSRect? = nil,
        strategy: PortalWindowStrategy = .developmentDefault,
        quickLookIntegration: QuickLookIntegration = QuickLookIntegration()
    ) {
        self.quickLookIntegration = quickLookIntegration
        portalViewController = PortalViewController(
            portal: portal,
            loadingCoordinator: loadingCoordinator
        )
        let window = PortalWindow(
            contentRect: initialFrame ?? NSRect(x: 0, y: 0, width: 560, height: 480),
            strategy: strategy,
            contentViewController: portalViewController
        )
        let selectedTab = portal.tabs.first(where: { $0.id == portal.selectedTabID })
        window.title = selectedTab?.folderURL.lastPathComponent ?? "Alcove"
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        portalViewController.onQuickLookRequested = { [weak quickLookIntegration] urls in
            quickLookIntegration?.handleSpace(for: urls)
        }
        portalViewController.onQuickLookSelectionChanged = { [weak quickLookIntegration] urls in
            quickLookIntegration?.updateSelection(urls)
        }
        portalViewController.onSelectionInvalidated = { [weak quickLookIntegration] in
            quickLookIntegration?.invalidateSelection()
        }
        quickLookIntegration.install(in: window)
        if initialFrame == nil {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func updatePortal(_ portal: Portal) {
        portalViewController.updatePortal(portal)
        let selectedTab = portal.tabs.first(where: { $0.id == portal.selectedTabID })
        window?.title = selectedTab?.folderURL.lastPathComponent ?? "Alcove"
    }
}

extension PortalWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        quickLookIntegration.detach()
    }

    func windowDidMove(_ notification: Notification) {
        publishFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        publishFrame()
    }

    private func publishFrame() {
        guard let frame = window?.frame else { return }
        onFrameChange?(frame)
    }
}
