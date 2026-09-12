import AppKit
import AlcoveCore

@MainActor
final class PortalWindowController: NSWindowController, PortalWindowPresenting {
    var isUserPlacementInteractionActive: Bool {
        (window as? PortalWindow)?.isUserPlacementInteractionActive ?? false
    }

    var onUserPlacementCommit: ((NSRect) -> Void)?
    var onUserResizeCommit: ((NSRect, GridCapacity) -> Void)?
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
    var onSetBackgroundStyle: ((PortalBackgroundStyle) -> Void)? {
        didSet { portalViewController.onSetBackgroundStyle = onSetBackgroundStyle }
    }
    private let portalViewController: PortalViewController
    private let quickLookIntegration: QuickLookIntegration
    private var iconLayout: PortalIconLayout
    private var gridCapacity: GridCapacity
    private var pendingResizeCapacity: GridCapacity?

    init(
        portal: Portal,
        loadingCoordinator: FolderLoadingCoordinator,
        initialFrame: NSRect? = nil,
        strategy: PortalWindowStrategy = .developmentDefault,
        quickLookIntegration: QuickLookIntegration = QuickLookIntegration()
    ) {
        self.quickLookIntegration = quickLookIntegration
        iconLayout = portal.iconLayout
        gridCapacity = portal.gridCapacity
        portalViewController = PortalViewController(
            portal: portal,
            loadingCoordinator: loadingCoordinator
        )
        let window = PortalWindow(
            contentRect: initialFrame ?? NSRect(x: 0, y: 0, width: 560, height: 480),
            strategy: strategy,
            contentViewController: portalViewController,
            dragRegionHeight: PortalViewController.tabBarHeight
        )
        window.contentMinSize = PortalViewController.minimumContentSize(for: portal.iconLayout)
        let selectedTab = portal.tabs.first(where: { $0.id == portal.selectedTabID })
        window.title = selectedTab?.folderURL.lastPathComponent ?? "Alcove"
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        window.onUserPlacementCommit = { [weak self] frame in
            self?.onUserPlacementCommit?(frame)
        }
        window.onUserResizeCommit = { [weak self] frame in
            guard let self, let capacity = self.pendingResizeCapacity else { return }
            self.gridCapacity = capacity
            self.pendingResizeCapacity = nil
            self.onUserResizeCommit?(frame, capacity)
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
        if let window {
            quickLookIntegration.installIfNeeded(in: window)
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func updatePortal(_ portal: Portal) {
        iconLayout = portal.iconLayout
        gridCapacity = portal.gridCapacity
        portalViewController.updatePortal(portal)
        window?.contentMinSize = PortalViewController.minimumContentSize(for: portal.iconLayout)
        let selectedTab = portal.tabs.first(where: { $0.id == portal.selectedTabID })
        window?.title = selectedTab?.folderURL.lastPathComponent ?? "Alcove"
    }

    func reloadSelectedFolder() {
        portalViewController.reloadSelectedFolder()
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
        pendingResizeCapacity = nil
        (window as? PortalWindow)?.beginUserResize()
    }

    func windowWillResize(
        _ sender: NSWindow,
        toFrameSize frameSize: NSSize
    ) -> NSSize {
        let proposedContentSize = sender.contentRect(
            forFrameRect: NSRect(origin: .zero, size: frameSize)
        ).size
        guard proposedContentSize.width.isFinite,
              proposedContentSize.height.isFinite else {
            return frameSize
        }
        let metrics = GridMetrics(
            iconSize: iconLayout.iconSize,
            labelFontSize: iconLayout.textSize
        )
        let proposedGridSize = NSSize(
            width: proposedContentSize.width,
            height: max(0, proposedContentSize.height - PortalViewController.tabBarHeight)
        )
        let preview: GridCapacityPreview
        do {
            preview = try metrics.capacityPreview(for: proposedGridSize)
        } catch {
            assertionFailure("Finite AppKit resize geometry must produce a grid capacity: \(error)")
            return frameSize
        }
        pendingResizeCapacity = preview.capacity
        portalViewController.showResizeCapacityPreview(preview)
        let snappedContentSize = PortalViewController.contentSize(
            for: preview.capacity,
            iconLayout: iconLayout
        )
        return sender.frameRect(
            forContentRect: NSRect(origin: .zero, size: snappedContentSize)
        ).size
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let portalWindow = window as? PortalWindow else { return }
        guard portalWindow.hasLiveResizeGeometryChanged else {
            pendingResizeCapacity = nil
            portalWindow.endUserResize()
            portalViewController.hideResizeCapacityPreview()
            return
        }
        _ = windowWillResize(portalWindow, toFrameSize: portalWindow.frame.size)
        if let pendingResizeCapacity {
            let snappedSize = PortalViewController.contentSize(
                for: pendingResizeCapacity,
                iconLayout: iconLayout
            )
            let contentSize = portalWindow.contentRect(forFrameRect: portalWindow.frame).size
            if snappedSize != contentSize {
                portalWindow.setContentSize(snappedSize)
            }
        }
        portalWindow.endUserResize()
        portalViewController.hideResizeCapacityPreview()
    }
}
