import AppKit
import AlcoveCore

@MainActor
final class PortalWindowController: NSWindowController, PortalWindowPresenting {
    var onUserPlacementCommit: ((NSRect) -> Void)?
    var onUserPlacementInteractionCancelled: (() -> Void)?
    var onSelectTab: ((FolderTabID) -> Void)? {
        didSet { portalViewController.onSelectTab = onSelectTab }
    }
    var onAddTab: (() -> Void)? {
        didSet { portalViewController.onAddTab = onAddTab }
    }
    var onCloseTab: ((FolderTabID) -> Void)? {
        didSet { portalViewController.onCloseTab = onCloseTab }
    }
    var onLocateFolder: ((FolderTabID) -> Void)? {
        didSet { portalViewController.onLocateFolderRequested = onLocateFolder }
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
        window.contentMinSize = PortalViewController.minimumContentSize(for: portal.iconSize)
        let selectedTab = portal.tabs.first(where: { $0.id == portal.selectedTabID })
        window.title = selectedTab?.folderURL.lastPathComponent ?? "Alcove"
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        window.onUserPlacementCommit = { [weak self] frame in
            self?.onUserPlacementCommit?(frame)
        }
        window.onUserPlacementInteractionCancelled = { [weak self] in
            self?.onUserPlacementInteractionCancelled?()
        }
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
        window?.contentMinSize = PortalViewController.minimumContentSize(for: portal.iconSize)
        let selectedTab = portal.tabs.first(where: { $0.id == portal.selectedTabID })
        window?.title = selectedTab?.folderURL.lastPathComponent ?? "Alcove"
    }

    func applySystemPlacement(frame: NSRect) -> Bool {
        guard let portalWindow = window as? PortalWindow else {
            return false
        }
        return portalWindow.applySystemPlacement(frame: frame)
    }
}

extension PortalWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        (window as? PortalWindow)?.cancelUserPlacementInteraction(notify: false)
        portalViewController.stopObservation()
        quickLookIntegration.detach()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        (window as? PortalWindow)?.beginUserResize()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        (window as? PortalWindow)?.endUserResize()
    }
}
