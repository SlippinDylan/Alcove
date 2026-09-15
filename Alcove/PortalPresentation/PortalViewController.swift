import AlcoveCore
import AppKit

private func portalLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(
        format: NSLocalizedString(key, comment: ""),
        locale: Locale.current,
        arguments: arguments
    )
}

private final class PortalStateLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

enum PortalPresentationState: Equatable {
    case emptyPortal
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

private struct FolderNavigationHistoryEntry {
    let url: URL
    let gridState: FileGridRuntimeState
}

private struct FolderTabNavigationState {
    let rootURL: URL
    var currentURL: URL
    var backStack: [FolderNavigationHistoryEntry] = []
    var gridState: FileGridRuntimeState?
}

@MainActor
final class PortalViewController: NSViewController {
    static let tabBarHeight = PortalLayoutMetrics.tabBarHeight
    static let pathBarHeight = PortalLayoutMetrics.pathBarHeight
    static let chromeHeight = PortalLayoutMetrics.chromeHeight

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
        return NSSize(width: gridSize.width, height: gridSize.height + chromeHeight)
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
    private let pathBarView = FolderPathBarView()
    private(set) var topSeparator = NSBox()
    private(set) var bottomSeparator = NSBox()
    private let stateLabel = PortalStateLabel()
    private let recoveryButton = NSButton()
    private let progressIndicator = NSProgressIndicator()
    private let chooseFolderButton = NSButton()
    private let resizeCapacityOverlay = PortalResizeCapacityOverlay()
    private var loadTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var navigationStates: [FolderTabID: FolderTabNavigationState] = [:]
    private var pendingGridState: FileGridRuntimeState?
    private var presentedTabID: FolderTabID?
    private(set) var presentationState: PortalPresentationState = .loading
    var onSelectTab: ((FolderTabID) -> Void)?
    var onAddTab: (() -> Void)? {
        didSet { tabBarView.onAdd = onAddTab }
    }
    var onCloseTab: ((FolderTabID) -> Void)?
    var onMoveTab: ((FolderTabID, Int) -> Void)? {
        didSet { tabBarView.onMoveTab = onMoveTab }
    }
    var onRemovePortal: (() -> Void)? {
        didSet { tabBarView.onRemovePortal = onRemovePortal }
    }
    var onSetPinned: ((Bool) -> Void)? {
        didSet { tabBarView.onSetPinned = onSetPinned }
    }
    var onSetSortOrder: ((PortalSortOrder) -> Void)? {
        didSet { tabBarView.onSetSortOrder = onSetSortOrder }
    }
    var onSetTint: ((PortalTint) -> Void)? {
        didSet { tabBarView.onSetTint = onSetTint }
    }
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
            backgroundStyle: portal.backgroundStyle,
            portalTint: portal.tint
        )
        if let gridViewController {
            gridViewController.updateGridCapacity(portal.gridCapacity)
            self.gridViewController = gridViewController
        } else {
            self.gridViewController = FileGridViewController(
                iconSize: portal.iconSize,
                textSize: portal.textSize,
                gridCapacity: portal.gridCapacity
            )
        }
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
        tabBarView.onNavigateBack = { [weak self] in self?.navigateBack() }
        tabBarView.configure(with: portal)
        rootView.addSubview(tabBarView)

        addChild(gridViewController)
        gridViewController.onQuickLookRequested = { [weak self] urls in
            self?.onQuickLookRequested?(urls)
        }
        gridViewController.onSelectionChanged = { [weak self] urls in
            self?.onQuickLookSelectionChanged?(urls)
        }
        gridViewController.onNavigateDirectory = { [weak self] item in
            self?.navigate(into: item.url)
        }
        gridViewController.onFileOperationCompleted = { [weak self] in
            self?.load()
        }
        let gridView = gridViewController.view
        gridView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(gridView)

        pathBarView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(pathBarView)

        configureSeparator(topSeparator, identifier: "portal.top-separator")
        configureSeparator(bottomSeparator, identifier: "portal.bottom-separator")
        rootView.addSubview(topSeparator)
        rootView.addSubview(bottomSeparator)

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

        chooseFolderButton.title = NSLocalizedString(
            "portal.choose",
            comment: "Choose a folder for an empty portal"
        )
        chooseFolderButton.image = NSImage(
            systemSymbolName: "folder.badge.plus",
            accessibilityDescription: nil
        )
        chooseFolderButton.imagePosition = .imageLeading
        chooseFolderButton.bezelStyle = .rounded
        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFirstFolder)
        chooseFolderButton.setAccessibilityLabel(
            NSLocalizedString(
                "portal.choose.help",
                comment: "Choose folder accessibility label"
            )
        )
        chooseFolderButton.translatesAutoresizingMaskIntoConstraints = false
        chooseFolderButton.isHidden = true
        rootView.addSubview(chooseFolderButton)

        resizeCapacityOverlay.translatesAutoresizingMaskIntoConstraints = false
        resizeCapacityOverlay.isHidden = true
        rootView.addSubview(resizeCapacityOverlay)

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
            gridView.bottomAnchor.constraint(equalTo: pathBarView.topAnchor),
            pathBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            pathBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            pathBarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            pathBarView.heightAnchor.constraint(equalToConstant: Self.pathBarHeight),
            topSeparator.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            topSeparator.centerYAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            bottomSeparator.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            bottomSeparator.centerYAnchor.constraint(equalTo: pathBarView.topAnchor),
            stateLabel.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: 24),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -24),
            recoveryButton.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 12),
            recoveryButton.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            progressIndicator.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: stateLabel.topAnchor, constant: -12),
            chooseFolderButton.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            chooseFolderButton.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            resizeCapacityOverlay.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            resizeCapacityOverlay.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            resizeCapacityOverlay.topAnchor.constraint(equalTo: rootView.topAnchor),
            resizeCapacityOverlay.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
        view = rootView
        updateNavigationChrome()
        if portal.tabs.isEmpty {
            showEmptyPortal()
        }
    }

    private func configureSeparator(_ separator: NSBox, identifier: String) {
        separator.boxType = .separator
        separator.identifier = NSUserInterfaceItemIdentifier(identifier)
        separator.translatesAutoresizingMaskIntoConstraints = false
    }

    func showResizeCapacityPreview(_ preview: GridCapacityPreview) {
        loadViewIfNeeded()
        resizeCapacityOverlay.preview = preview
        resizeCapacityOverlay.isHidden = false
    }

    func previewGridCapacity(_ gridCapacity: GridCapacity) {
        gridViewController.updateGridCapacity(gridCapacity)
    }

    func hideResizeCapacityPreview() {
        guard isViewLoaded else { return }
        resizeCapacityOverlay.isHidden = true
    }

    func closeSettingsWindow() {
        tabBarView.closeSettingsWindow()
    }

    func showSettingsWindow() {
        tabBarView.showSettingsWindow()
    }

    func confirmPortalRemoval() {
        tabBarView.confirmPortalRemoval()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startObservation()
    }

    func load() {
        guard currentFolderURL != nil else {
            showEmptyPortal()
            return
        }
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
        let previousGridCapacity = self.portal.gridCapacity
        let previousBackgroundStyle = self.portal.backgroundStyle
        let previousSortOrder = self.portal.sortOrder
        let previousTint = self.portal.tint
        let previousFolderURL = currentFolderURL
        if isViewLoaded,
           let previousTabID,
           portal.selectedTabID != previousTabID,
           presentedTabID == previousTabID {
            saveGridState(for: previousTabID)
        }
        self.portal = portal
        if portal.iconLayout != previousIconLayout {
            gridViewController.updateIconLayout(
                iconSize: portal.iconSize,
                textSize: portal.textSize
            )
        }
        if portal.gridCapacity != previousGridCapacity {
            gridViewController.updateGridCapacity(portal.gridCapacity)
        }
        if portal.backgroundStyle != previousBackgroundStyle {
            portalMaterialView.updateBackgroundStyle(portal.backgroundStyle)
        }
        if portal.tint != previousTint {
            portalMaterialView.updatePortalTint(portal.tint)
        }
        navigationStates = navigationStates.filter { id, state in
            portal.tabs.contains(where: { $0.id == id })
                && portal.tabs.first(where: { $0.id == id })?.folderURL == state.rootURL
        }
        if portal.selectedTabID != previousTabID || currentFolderURL != previousFolderURL {
            pendingGridState = portal.selectedTabID.flatMap { navigationStates[$0]?.gridState }
        }
        if isViewLoaded {
            tabBarView.configure(with: portal)
            updateNavigationChrome()
        }
        if portal.selectedTabID != previousTabID || currentFolderURL != previousFolderURL {
            onSelectionInvalidated?()
            if isViewLoaded {
                if portal.tabs.isEmpty {
                    showEmptyPortal()
                } else {
                    showLoading()
                    startObservation()
                }
            }
        } else if portal.sortOrder != previousSortOrder, isViewLoaded {
            load()
        }
    }

    func updateAppearance(_ appearance: PortalAppearancePreferences) {
        portalMaterialView.updateBackgroundStyle(appearance.backgroundStyle)
        portalMaterialView.updateCornerRadius(appearance.cornerRadius.points)
    }

    func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
        observationCoordinator.stop()
        loadTask?.cancel()
        loadTask = nil
    }

    func reload(showLoadingIndicator: Bool = true) async {
        guard let folderURL = currentFolderURL else {
            showEmptyPortal()
            return
        }
        if showLoadingIndicator {
            showLoading()
        }
        do {
            let completion = try await loadingCoordinator.load(
                root: folderURL,
                showHidden: false,
                sortOrder: portal.sortOrder
            )
            guard !Task.isCancelled else { return }
            apply(completion)
        } catch {
            guard !Task.isCancelled else { return }
            showErrorPresentation(
                PortalErrorPresentation(
                    message: NSLocalizedString(
                        "portal.error.load",
                        comment: "Folder load error title"
                    ),
                    detail: NSLocalizedString(
                        "portal.error.load.detail",
                        comment: "Folder load error detail"
                    ),
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
        guard let root = currentFolderURL else {
            showEmptyPortal()
            return
        }
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
                    message: NSLocalizedString(
                        "portal.error.watch",
                        comment: "Folder observation error title"
                    ),
                    detail: NSLocalizedString(
                        "portal.error.watch.detail",
                        comment: "Folder observation error detail"
                    ),
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
                let runtimeState = pendingGridState
                pendingGridState = nil
                if items.isEmpty {
                    pendingGridState = nil
                    showState(NSLocalizedString(
                        "portal.empty",
                        comment: "Empty folder message"
                    ))
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
        chooseFolderButton.isHidden = true
        gridViewController.setItems([])
        gridViewController.view.isHidden = true
        stateLabel.stringValue = NSLocalizedString("portal.loading", comment: "Loading state")
        stateLabel.isHidden = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
    }

    private func showItems(_ items: [FileItem]) {
        presentationState = .items(items.count)
        presentedTabID = portal.selectedTabID
        recoveryAction = nil
        recoveryButton.isHidden = true
        chooseFolderButton.isHidden = true
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
        chooseFolderButton.isHidden = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        gridViewController.setItems([])
        // Keep the empty collection view active so its background remains a valid file-drop target.
        gridViewController.view.isHidden = false
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
        recoveryButton.title = presentation.action == .locateFolder
            ? NSLocalizedString("portal.locate", comment: "Locate folder action")
            : NSLocalizedString("portal.retry", comment: "Retry action")
        recoveryButton.setAccessibilityLabel(recoveryButton.title)
        recoveryButton.isHidden = false
        chooseFolderButton.isHidden = true
    }

    private func showEmptyPortal() {
        presentationState = .emptyPortal
        presentedTabID = nil
        recoveryAction = nil
        observationCoordinator.stop()
        gridViewController.setItems([])
        gridViewController.view.isHidden = true
        stateLabel.isHidden = true
        recoveryButton.isHidden = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        chooseFolderButton.isHidden = false
    }

    static func errorPresentation(for error: FolderAccessError) -> PortalErrorPresentation {
        switch error {
        case .folderNotFound(let url, _), .folderReplaced(let url):
            return PortalErrorPresentation(
                message: NSLocalizedString(
                    "portal.error.folder_not_found",
                    comment: "Folder not found"
                ),
                detail: url.path,
                action: .locateFolder
            )
        case .notDirectory(let url, _):
            return PortalErrorPresentation(
                message: NSLocalizedString(
                    "portal.error.not_folder",
                    comment: "Selected item is not a folder"
                ),
                detail: url.path,
                action: .locateFolder
            )
        case .permissionDenied(let url, _):
            return PortalErrorPresentation(
                message: NSLocalizedString(
                    "portal.error.permission_denied",
                    comment: "Folder permission denied"
                ),
                detail: portalLocalizedFormat(
                    "portal.error.permission_denied.detail",
                    url.lastPathComponent
                ),
                action: .retry
            )
        case .readFailed(let url, _):
            return PortalErrorPresentation(
                message: NSLocalizedString(
                    "portal.error.read_contents",
                    comment: "Unable to read folder contents"
                ),
                detail: url.path,
                action: .retry
            )
        case .unsupportedLocation(let url, _):
            return PortalErrorPresentation(
                message: NSLocalizedString(
                    "portal.error.unsupported_location",
                    comment: "Unsupported folder location"
                ),
                detail: url.path,
                action: .locateFolder
            )
        }
    }

    @objc func performRecoveryAction() {
        switch recoveryAction {
        case .locateFolder:
            if let selectedTabID = portal.selectedTabID {
                onLocateFolderRequested?(selectedTabID)
            }
        case .retry:
            startObservation()
        case nil:
            break
        }
    }

    func reloadSelectedFolder() {
        onSelectionInvalidated?()
        guard isViewLoaded else { return }
        guard currentFolderURL != nil else {
            showEmptyPortal()
            return
        }
        showLoading()
        startObservation()
    }

    @objc private func chooseFirstFolder() {
        onAddTab?()
    }

    private var currentFolderURL: URL? {
        guard let tab = portal.selectedTab else { return nil }
        return navigationStates[tab.id]?.currentURL ?? tab.folderURL
    }

    private func saveGridState(for tabID: FolderTabID) {
        guard let tab = portal.tabs.first(where: { $0.id == tabID }) else { return }
        var state = navigationStates[tabID] ?? FolderTabNavigationState(
            rootURL: tab.folderURL,
            currentURL: tab.folderURL
        )
        state.gridState = gridViewController.captureRuntimeState()
        navigationStates[tabID] = state
    }

    private func navigate(into url: URL) {
        guard let tab = portal.selectedTab else { return }
        var state = navigationStates[tab.id] ?? FolderTabNavigationState(
            rootURL: tab.folderURL,
            currentURL: tab.folderURL
        )
        let previousGridState = gridViewController.captureRuntimeState()
        state.backStack.append(FolderNavigationHistoryEntry(
            url: state.currentURL,
            gridState: previousGridState
        ))
        state.currentURL = url.standardizedFileURL
        state.gridState = nil
        navigationStates[tab.id] = state
        pendingGridState = nil
        transitionToCurrentFolder()
    }

    private func navigateBack() {
        guard let tabID = portal.selectedTabID,
              var state = navigationStates[tabID],
              let previous = state.backStack.popLast() else { return }
        state.currentURL = previous.url
        state.gridState = previous.gridState
        navigationStates[tabID] = state
        pendingGridState = previous.gridState
        transitionToCurrentFolder()
    }

    private func transitionToCurrentFolder() {
        onSelectionInvalidated?()
        updateNavigationChrome()
        showLoading()
        startObservation()
    }

    private func updateNavigationChrome() {
        let currentFolderURL = currentFolderURL
        pathBarView.update(folderURL: currentFolderURL)
        gridViewController.updateDropDestination(currentFolderURL)
        let canGoBack = portal.selectedTabID.flatMap {
            navigationStates[$0]?.backStack.isEmpty == false
        } ?? false
        tabBarView.updateNavigation(canGoBack: canGoBack)
    }
}

@MainActor
final class FolderPathBarView: NSView {
    private(set) var contentView = NSView()
    private let pathIcon = NSImageView()
    private(set) var pathLabel = NSTextField(labelWithString: "")
    private(set) var terminalButton = NSButton()
    private(set) var copyButton = NSButton()
    private(set) var actionSpacer = NSView()
    private(set) var displayedPath: String?
    private(set) var folderURL: URL?
    private let pathOpener: any FolderPathOpening
    private let failurePresenter: any FolderPathOpenFailurePresenting

    init(
        pathOpener: any FolderPathOpening,
        failurePresenter: any FolderPathOpenFailurePresenting
    ) {
        self.pathOpener = pathOpener
        self.failurePresenter = failurePresenter
        super.init(frame: .zero)
        configureView()
    }

    override init(frame frameRect: NSRect) {
        pathOpener = SystemFolderPathOpener()
        failurePresenter = FolderPathOpenFailurePresenter()
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(folderURL: URL?) {
        guard let folderURL else {
            displayedPath = nil
            self.folderURL = nil
            contentView.isHidden = true
            return
        }
        let standardizedURL = folderURL.standardizedFileURL
        let path = NSString(
            string: standardizedURL.path
        ).abbreviatingWithTildeInPath
        self.folderURL = standardizedURL
        displayedPath = path
        pathLabel.stringValue = path
        pathLabel.toolTip = path
        contentView.isHidden = false
    }

    private func configureView() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        pathIcon.image = NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: nil
        )
        pathIcon.contentTintColor = .secondaryLabelColor
        pathIcon.translatesAutoresizingMaskIntoConstraints = false
        pathIcon.addGestureRecognizer(NSClickGestureRecognizer(
            target: self,
            action: #selector(openInFinder)
        ))

        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.setAccessibilityLabel(
            NSLocalizedString("portal.path.label", comment: "Folder path accessibility label")
        )
        pathLabel.addGestureRecognizer(NSClickGestureRecognizer(
            target: self,
            action: #selector(openInFinder)
        ))

        terminalButton.image = NSImage(
            systemSymbolName: "terminal",
            accessibilityDescription: nil
        )
        terminalButton.imagePosition = .imageOnly
        terminalButton.isBordered = false
        terminalButton.contentTintColor = .secondaryLabelColor
        terminalButton.target = self
        terminalButton.action = #selector(openInTerminal)
        terminalButton.toolTip = NSLocalizedString(
            "portal.path.terminal",
            comment: "Open folder in Terminal"
        )
        terminalButton.setAccessibilityLabel(terminalButton.toolTip ?? "")

        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: nil
        )
        copyButton.imagePosition = .imageOnly
        copyButton.isBordered = false
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.target = self
        copyButton.action = #selector(copyPath)
        copyButton.toolTip = NSLocalizedString("portal.path.copy", comment: "Copy folder path")
        copyButton.setAccessibilityLabel(copyButton.toolTip ?? "")

        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [
            pathIcon,
            pathLabel,
            actionSpacer,
            terminalButton,
            copyButton,
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            pathIcon.widthAnchor.constraint(equalToConstant: 16),
            pathIcon.heightAnchor.constraint(equalToConstant: 16),
            terminalButton.widthAnchor.constraint(equalToConstant: 28),
            terminalButton.heightAnchor.constraint(equalToConstant: 28),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc func openInFinder() {
        guard let folderURL else { return }
        if !pathOpener.openInFinder(folderURL) {
            failurePresenter.present(.finderLaunchFailed, for: folderURL)
        }
    }

    @objc func openInTerminal() {
        guard let folderURL else { return }
        pathOpener.openInTerminal(folderURL) { [weak self] error in
            guard let self, let error else { return }
            self.failurePresenter.present(error, for: folderURL)
        }
    }

    @objc private func copyPath() {
        guard let folderURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(folderURL.path, forType: .string)
    }
}

@MainActor
private final class PortalResizeCapacityOverlay: NSView {
    var preview: GridCapacityPreview? {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let preview else { return }
        let committed = "\(preview.capacity.columns) × \(preview.capacity.rows)"
        let text: String
        if let candidate = preview.candidateCapacity {
            text = "\(committed)  →  \(candidate.columns) × \(candidate.rows)"
        } else {
            text = committed
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let badge = NSRect(
            x: bounds.midX - (textSize.width + 28) / 2,
            y: 14,
            width: textSize.width + 28,
            height: 32
        )
        NSColor.windowBackgroundColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 16, yRadius: 16).fill()
        let border = NSBezierPath(roundedRect: badge, xRadius: 16, yRadius: 16)
        border.lineWidth = 1.5
        border.setLineDash([5, 4], count: 2, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        border.stroke()
        attributedText.draw(
            at: NSPoint(
                x: badge.midX - textSize.width / 2,
                y: badge.midY - textSize.height / 2
            )
        )
    }
}
