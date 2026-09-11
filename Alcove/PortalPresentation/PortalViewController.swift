import AlcoveCore
import AppKit

enum PortalPresentationState: Equatable {
    case loading
    case items(Int)
    case message(String)
}

@MainActor
final class PortalViewController: NSViewController {
    private var portal: Portal
    private let loadingCoordinator: FolderLoadingCoordinator
    private let tabBarView = TabBarView()
    private let gridViewController = FileGridViewController()
    private let stateLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private var loadTask: Task<Void, Never>?
    private var runtimeStates: [FolderTabID: FileGridRuntimeState] = [:]
    private(set) var presentationState: PortalPresentationState = .loading
    var onSelectTab: ((FolderTabID) -> Void)?
    var onAddTab: (() -> Void)?
    var onCloseTab: ((FolderTabID) -> Void)?
    var onQuickLookRequested: (([URL]) -> Void)?
    var onQuickLookSelectionChanged: (([URL]) -> Void)?
    var onSelectionInvalidated: (() -> Void)?

    init(portal: Portal, loadingCoordinator: FolderLoadingCoordinator) {
        self.portal = portal
        self.loadingCoordinator = loadingCoordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        loadTask?.cancel()
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        tabBarView.onSelect = { [weak self] id in self?.onSelectTab?(id) }
        tabBarView.onAdd = { [weak self] in self?.onAddTab?() }
        tabBarView.onClose = { [weak self] id in self?.onCloseTab?(id) }
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

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.isHidden = true
        rootView.addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            gridView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tabBarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 40),
            gridView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            gridView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            stateLabel.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: 24),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -24),
            progressIndicator.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: stateLabel.topAnchor, constant: -12),
        ])
        view = rootView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        load()
    }

    func load() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await reload()
        }
    }

    func updatePortal(_ portal: Portal) {
        let previousTabID = self.portal.selectedTabID
        if isViewLoaded {
            runtimeStates[previousTabID] = gridViewController.captureRuntimeState()
        }
        self.portal = portal
        runtimeStates = runtimeStates.filter { id, _ in
            portal.tabs.contains(where: { $0.id == id })
        }
        if isViewLoaded {
            tabBarView.configure(with: portal)
        }
        if portal.selectedTabID != previousTabID {
            onSelectionInvalidated?()
            load()
        }
    }

    func reload() async {
        showLoading()
        do {
            let completion = try await loadingCoordinator.load(
                root: folderURL,
                showHidden: false
            )
            guard !Task.isCancelled else { return }
            apply(completion)
        } catch {
            guard !Task.isCancelled else { return }
            showState("Unable to load folder")
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
                if items.isEmpty {
                    showState("This folder is empty")
                } else {
                    showItems(items)
                    if let runtimeState = runtimeStates[portal.selectedTabID] {
                        gridViewController.restoreRuntimeState(runtimeState)
                    }
                }
            case .failure(let error):
                showState(error.userMessage)
            }
        }
    }

    private func showLoading() {
        presentationState = .loading
        gridViewController.view.isHidden = true
        stateLabel.stringValue = "Loading…"
        stateLabel.isHidden = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
    }

    private func showItems(_ items: [FileItem]) {
        presentationState = .items(items.count)
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        stateLabel.isHidden = true
        gridViewController.setItems(items)
        gridViewController.view.isHidden = false
    }

    private func showState(_ message: String) {
        presentationState = .message(message)
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        gridViewController.setItems([])
        gridViewController.view.isHidden = true
        stateLabel.stringValue = message
        stateLabel.isHidden = false
    }

    private var folderURL: URL {
        guard let tab = portal.tabs.first(where: { $0.id == portal.selectedTabID }) else {
            preconditionFailure("Portal selected-tab invariant violated")
        }
        return tab.folderURL
    }
}
