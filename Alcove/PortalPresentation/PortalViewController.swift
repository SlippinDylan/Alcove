import AlcoveCore
import AppKit

enum PortalPresentationState: Equatable {
    case loading
    case items(Int)
    case message(String)
    case error(PortalErrorPresentation)
}

enum PortalRecoveryAction: Equatable {
    case locateFolder
    case retry
}

struct PortalErrorPresentation: Equatable {
    let message: String
    let detail: String
    let action: PortalRecoveryAction
}

@MainActor
final class PortalViewController: NSViewController {
    static let tabBarHeight = PortalLayoutMetrics.tabBarHeight

    static func minimumContentSize(for iconSize: IconSize) -> NSSize {
        minimumContentSize(for: .fixed(iconSize))
    }

    static func minimumContentSize(for iconLayout: PortalIconLayout) -> NSSize {
        contentSize(for: .minimum, iconLayout: iconLayout)
    }

    static func contentSize(
        for capacity: GridCapacity,
        iconLayout: PortalIconLayout
    ) -> NSSize {
        let gridSize = GridMetrics(
            iconSize: iconLayout.iconSize,
            labelFontSize: iconLayout.textSize
        ).contentSize(for: capacity)
        return NSSize(width: gridSize.width, height: gridSize.height + tabBarHeight)
    }

    static func snappedContentSize(_ requestedSize: NSSize, for iconSize: IconSize) -> NSSize {
        snappedContentSize(requestedSize, for: .fixed(iconSize))
    }

    static func snappedContentSize(
        _ requestedSize: NSSize,
        for iconLayout: PortalIconLayout,
        roundingRule: FloatingPointRoundingRule = .toNearestOrAwayFromZero
    ) -> NSSize {
        let metrics = GridMetrics(
            iconSize: iconLayout.iconSize,
            labelFontSize: iconLayout.textSize
        )
        let minimum = minimumContentSize(for: iconLayout)
        let width = snappedExtent(
            requestedSize.width,
            minimum: minimum.width,
            increment: metrics.itemSize.width + metrics.horizontalSpacing,
            roundingRule: roundingRule
        )
        let height = snappedExtent(
            requestedSize.height,
            minimum: minimum.height,
            increment: metrics.itemSize.height + metrics.verticalSpacing,
            roundingRule: roundingRule
        )
        return NSSize(width: width, height: height)
    }

    private static func snappedExtent(
        _ requested: CGFloat,
        minimum: CGFloat,
        increment: CGFloat,
        roundingRule: FloatingPointRoundingRule
    ) -> CGFloat {
        let constrained = max(requested, minimum)
        let steps = ((constrained - minimum) / increment).rounded(roundingRule)
        return minimum + steps * increment
    }

    private var portal: Portal
    private let loadingCoordinator: FolderLoadingCoordinator
    private let tabBarView: TabBarView
    private let portalContentView: NSView
    private let portalMaterialView: PortalChromeMaterialView
    private let gridViewController: FileGridViewController
    private let stateLabel = NSTextField(labelWithString: "")
    private let recoveryButton = NSButton()
    private let progressIndicator = NSProgressIndicator()
    private var loadTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var runtimeStates: [FolderTabID: FileGridRuntimeState] = [:]
    private var presentedTabID: FolderTabID?
    private(set) var presentationState: PortalPresentationState = .loading
    var onSelectTab: ((FolderTabID) -> Void)?
    var onAddTab: (() -> Void)?
    var onCloseTab: ((FolderTabID) -> Void)?
    var onSetBackgroundStyle: ((PortalBackgroundStyle) -> Void)?
    var onQuickLookRequested: (([URL]) -> Void)?
    var onQuickLookSelectionChanged: (([URL]) -> Void)?
    var onSelectionInvalidated: (() -> Void)?
    var onLocateFolderRequested: ((FolderTabID) -> Void)?
    private(set) var recoveryAction: PortalRecoveryAction?
    private lazy var observationCoordinator = FolderObservationCoordinator(
        onRefresh: { [weak self] in self?.load() },
        onFailure: { [weak self] error in self?.showObservationFailure(error) }
    )

    init(
        portal: Portal,
        loadingCoordinator: FolderLoadingCoordinator,
        gridViewController: FileGridViewController? = nil
    ) {
        self.portal = portal
        self.loadingCoordinator = loadingCoordinator
        let tabBarView = TabBarView()
        self.tabBarView = tabBarView
        let portalContentView = NSView()
        self.portalContentView = portalContentView
        portalMaterialView = PortalChromeMaterialView(
            contentView: NSView(),
            role: .surface,
            backgroundStyle: portal.backgroundStyle
        )
        self.gridViewController = gridViewController
            ?? FileGridViewController(iconSize: portal.iconSize, textSize: portal.textSize)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        loadTask?.cancel()
        observationTask?.cancel()
    }

    override func loadView() {
        let rootView = portalContentView

        portalMaterialView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(portalMaterialView)

        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        tabBarView.onSelect = { [weak self] id in self?.onSelectTab?(id) }
        tabBarView.onAdd = { [weak self] in self?.onAddTab?() }
        tabBarView.onClose = { [weak self] id in self?.onCloseTab?(id) }
        tabBarView.onSetBackgroundStyle = { [weak self] style in
            self?.onSetBackgroundStyle?(style)
        }
        tabBarView.configure(with: portal)
        rootView.addSubview(tabBarView)

        addChild(gridViewController)
        gridViewController.onQuickLookRequested = { [weak self] urls in
            self?.onQuickLookRequested?(urls)
        }
        gridViewController.onSelectionChanged = { [weak self] urls in
            self?.onQuickLookSelectionChanged?(urls)
        }
        let gridView = gridViewController.view
        gridView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(gridView)

        stateLabel.alignment = .center
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.isHidden = true
        rootView.addSubview(stateLabel)

        recoveryButton.target = self
        recoveryButton.action = #selector(performRecoveryAction)
        recoveryButton.bezelStyle = .rounded
        recoveryButton.translatesAutoresizingMaskIntoConstraints = false
        recoveryButton.isHidden = true
        rootView.addSubview(recoveryButton)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.isHidden = true
        rootView.addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            portalMaterialView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            portalMaterialView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            portalMaterialView.topAnchor.constraint(equalTo: rootView.topAnchor),
            portalMaterialView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tabBarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: Self.tabBarHeight),
            gridView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            gridView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            stateLabel.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: 24),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -24),
            recoveryButton.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 12),
            recoveryButton.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            progressIndicator.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: stateLabel.topAnchor, constant: -12),
        ])
        view = rootView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startObservation()
    }

    func load() {
        loadTask?.cancel()
        let showLoadingIndicator = presentationState == .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            await reload(showLoadingIndicator: showLoadingIndicator)
        }
    }

    func updatePortal(_ portal: Portal) {
        let previousTabID = self.portal.selectedTabID
        let previousIconLayout = self.portal.iconLayout
        let previousBackgroundStyle = self.portal.backgroundStyle
        let previousFolderURL = folderURL
        if isViewLoaded,
           portal.selectedTabID != previousTabID,
           presentedTabID == previousTabID {
            runtimeStates[previousTabID] = gridViewController.captureRuntimeState()
        }
        self.portal = portal
        if portal.iconLayout != previousIconLayout {
            gridViewController.updateIconLayout(
                iconSize: portal.iconSize,
                textSize: portal.textSize
            )
        }
        if portal.backgroundStyle != previousBackgroundStyle {
            portalMaterialView.updateBackgroundStyle(portal.backgroundStyle)
        }
        runtimeStates = runtimeStates.filter { id, _ in
            portal.tabs.contains(where: { $0.id == id })
        }
        if isViewLoaded {
            tabBarView.configure(with: portal)
        }
        if portal.selectedTabID != previousTabID || folderURL != previousFolderURL {
            onSelectionInvalidated?()
            if isViewLoaded {
                showLoading()
                startObservation()
            }
        }
    }

    func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
        observationCoordinator.stop()
        loadTask?.cancel()
        loadTask = nil
    }

    func reload(showLoadingIndicator: Bool = true) async {
        if showLoadingIndicator {
            showLoading()
        }
        do {
            let completion = try await loadingCoordinator.load(
                root: folderURL,
                showHidden: false
            )
            guard !Task.isCancelled else { return }
            apply(completion)
        } catch {
            guard !Task.isCancelled else { return }
            showErrorPresentation(
                PortalErrorPresentation(
                    message: "Unable to load folder",
                    detail: "Try again. If the problem continues, choose another folder.",
                    action: .retry
                )
            )
        }
    }

    private func startObservation() {
        loadTask?.cancel()
        loadTask = nil
        observationTask?.cancel()
        observationCoordinator.stop()
        let root = folderURL
        observationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await observationCoordinator.start(root: root)
                guard !Task.isCancelled else { return }
                load()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                showObservationFailure(error)
            }
        }
    }

    private func showObservationFailure(_ error: Error) {
        loadTask?.cancel()
        loadTask = nil
        if let error = error as? FolderAccessError {
            showError(error)
        } else {
            showErrorPresentation(
                PortalErrorPresentation(
                    message: "Unable to watch folder",
                    detail: "The folder could not be monitored for changes.",
                    action: .retry
                )
            )
        }
    }

    private func apply(_ completion: FolderLoadCompletion) {
        switch completion {
        case .discarded:
            return
        case .accepted(_, let outcome):
            switch outcome {
            case .contents(let result):
                let items = result.items
                let runtimeState = runtimeStates.removeValue(forKey: portal.selectedTabID)
                if items.isEmpty {
                    showState("This folder is empty")
                } else {
                    showItems(items)
                    if let runtimeState {
                        gridViewController.restoreRuntimeState(runtimeState)
                    }
                }
            case .failure(let error):
                showError(error)
            }
        }
    }

    private func showLoading() {
        presentationState = .loading
        presentedTabID = nil
        recoveryAction = nil
        recoveryButton.isHidden = true
        gridViewController.setItems([])
        gridViewController.view.isHidden = true
        stateLabel.stringValue = "Loading…"
        stateLabel.isHidden = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
    }

    private func showItems(_ items: [FileItem]) {
        presentationState = .items(items.count)
        presentedTabID = portal.selectedTabID
        recoveryAction = nil
        recoveryButton.isHidden = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        stateLabel.isHidden = true
        gridViewController.setItems(items)
        gridViewController.view.isHidden = false
    }

    private func showState(_ message: String) {
        presentationState = .message(message)
        presentedTabID = nil
        recoveryAction = nil
        recoveryButton.isHidden = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        gridViewController.setItems([])
        gridViewController.view.isHidden = true
        stateLabel.stringValue = message
        stateLabel.isHidden = false
    }

    private func showError(_ error: FolderAccessError) {
        showErrorPresentation(Self.errorPresentation(for: error))
    }

    private func showErrorPresentation(_ presentation: PortalErrorPresentation) {
        presentationState = .error(presentation)
        presentedTabID = nil
        recoveryAction = presentation.action
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        gridViewController.setItems([])
        gridViewController.view.isHidden = true
        stateLabel.stringValue = "\(presentation.message)\n\(presentation.detail)"
        stateLabel.maximumNumberOfLines = 0
        stateLabel.isHidden = false
        recoveryButton.title = presentation.action == .locateFolder ? "Locate Folder…" : "Retry"
        recoveryButton.setAccessibilityLabel(recoveryButton.title)
        recoveryButton.isHidden = false
    }

    static func errorPresentation(for error: FolderAccessError) -> PortalErrorPresentation {
        switch error {
        case .folderNotFound(let url, _), .folderReplaced(let url):
            return PortalErrorPresentation(
                message: "Folder not found",
                detail: url.path,
                action: .locateFolder
            )
        case .notDirectory(let url, _):
            return PortalErrorPresentation(
                message: "The selected item is not a folder",
                detail: url.path,
                action: .locateFolder
            )
        case .permissionDenied(let url, _):
            return PortalErrorPresentation(
                message: "Permission denied",
                detail: "\(url.lastPathComponent). macOS may require permission in System Settings → Privacy & Security → Files and Folders.",
                action: .retry
            )
        case .readFailed(let url, _):
            return PortalErrorPresentation(
                message: "Unable to read folder contents",
                detail: url.path,
                action: .retry
            )
        case .unsupportedLocation(let url, _):
            return PortalErrorPresentation(
                message: "Choose a folder on this Mac's internal disk",
                detail: url.path,
                action: .locateFolder
            )
        }
    }

    @objc func performRecoveryAction() {
        switch recoveryAction {
        case .locateFolder:
            onLocateFolderRequested?(portal.selectedTabID)
        case .retry:
            startObservation()
        case nil:
            break
        }
    }

    func reloadSelectedFolder() {
        onSelectionInvalidated?()
        guard isViewLoaded else { return }
        showLoading()
        startObservation()
    }

    private var folderURL: URL {
        guard let tab = portal.tabs.first(where: { $0.id == portal.selectedTabID }) else {
            preconditionFailure("Portal selected-tab invariant violated")
        }
        return tab.folderURL
    }
}
