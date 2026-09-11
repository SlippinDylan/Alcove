import AppKit

@MainActor
final class PortalWindowController: NSWindowController, PortalWindowPresenting {
    var onFrameChange: ((NSRect) -> Void)?

    init(
        folderURL: URL,
        loadingCoordinator: FolderLoadingCoordinator,
        initialFrame: NSRect? = nil,
        strategy: PortalWindowStrategy = .developmentDefault
    ) {
        let portalViewController = PortalViewController(
            folderURL: folderURL,
            loadingCoordinator: loadingCoordinator
        )
        let window = PortalWindow(
            contentRect: initialFrame ?? NSRect(x: 0, y: 0, width: 560, height: 480),
            strategy: strategy,
            contentViewController: portalViewController
        )
        window.title = folderURL.lastPathComponent
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
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
}

extension PortalWindowController: NSWindowDelegate {
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
