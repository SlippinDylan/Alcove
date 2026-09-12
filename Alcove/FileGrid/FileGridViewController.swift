import AlcoveCore
import AppKit

@MainActor
final class PortalGridCollectionViewLayout: NSCollectionViewLayout {
    var metrics: GridMetrics {
        didSet { invalidateLayout() }
    }
    var visibleColumns: Int {
        didSet { invalidateLayout() }
    }

    private var result: GridLayoutResult?
    private var attributes: [IndexPath: NSCollectionViewLayoutAttributes] = [:]

    init(metrics: GridMetrics, visibleColumns: Int) {
        self.metrics = metrics
        self.visibleColumns = visibleColumns
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let result = GridLayout(metrics: metrics).layout(
            itemCount: collectionView.numberOfItems(inSection: 0),
            visibleColumns: visibleColumns,
            availableWidth: collectionView.bounds.width
        )
        self.result = result
        attributes = Dictionary(
            uniqueKeysWithValues: result.itemFrames.enumerated().map { index, frame in
                let indexPath = IndexPath(item: index, section: 0)
                let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
                attributes.frame = frame
                return (indexPath, attributes)
            }
        )
    }

    override var collectionViewContentSize: NSSize {
        result?.contentSize ?? .zero
    }

    override func layoutAttributesForElements(
        in rect: NSRect
    ) -> [NSCollectionViewLayoutAttributes] {
        attributes.values.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        attributes[indexPath]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        collectionView?.bounds.width != newBounds.width
    }
}

struct FileGridRuntimeState: Equatable {
    let selection: SelectionState
    let scrollOrigin: NSPoint
}

@MainActor
final class FileGridViewController: NSViewController {
    private let collectionView = FileCollectionView()
    private let workspaceOpener: any WorkspaceOpening
    private let openFailurePresenter: any WorkspaceOpenFailurePresenting
    private var metrics: GridMetrics
    private var gridCapacity: GridCapacity
    private var items: [FileItem] = []
    private(set) var selectionState = SelectionState()
    private(set) var failedOpenURLs: [URL] = []
    private(set) var lastKeyboardScrollPosition: NSCollectionView.ScrollPosition?
    var onQuickLookRequested: (([URL]) -> Void)?
    var onSelectionChanged: (([URL]) -> Void)?

    init(
        workspaceOpener: any WorkspaceOpening = SystemWorkspaceOpener(),
        openFailurePresenter: any WorkspaceOpenFailurePresenting = WorkspaceOpenFailurePresenter(),
        iconSize: IconSize = .medium,
        textSize: CGFloat = 12,
        gridCapacity: GridCapacity = .minimum
    ) {
        self.workspaceOpener = workspaceOpener
        self.openFailurePresenter = openFailurePresenter
        metrics = GridMetrics(iconSize: iconSize, labelFontSize: textSize)
        self.gridCapacity = gridCapacity
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var itemCount: Int {
        items.count
    }

    override func loadView() {
        collectionView.collectionViewLayout = PortalGridCollectionViewLayout(
            metrics: metrics,
            visibleColumns: gridCapacity.columns
        )
        collectionView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: 560, height: metrics.minimumContainerSize.height)
        )
        collectionView.autoresizingMask = [.width]
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            FileItemCell.self,
            forItemWithIdentifier: FileItemCell.reuseIdentifier
        )
        collectionView.onItemClick = { [weak self] index, modifiers, clickCount in
            self?.handleClick(index: index, modifiers: modifiers, clickCount: clickCount)
        }
        collectionView.onKeyCommand = { [weak self] command in
            self?.handleKeyCommand(command)
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView
        view = scrollView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let scrollView = view as? NSScrollView else { return }
        let viewportWidth = scrollView.contentView.bounds.width
        guard viewportWidth > 0, collectionView.frame.width != viewportWidth else { return }

        collectionView.frame.size.width = viewportWidth
        collectionView.collectionViewLayout?.invalidateLayout()
    }

    func setItems(_ items: [FileItem]) {
        self.items = items
        selectionState.reconcile(with: orderedIDs)
        collectionView.reloadData()
        applySelection()
    }

    func item(at index: Int) -> FileItem {
        items[index]
    }

    func updateIconSize(_ iconSize: IconSize) {
        updateIconLayout(iconSize: iconSize, textSize: metrics.labelFontSize)
    }

    func updateIconLayout(iconSize: IconSize, textSize: CGFloat) {
        guard metrics.iconSize != iconSize || metrics.labelFontSize != textSize else { return }
        metrics = GridMetrics(iconSize: iconSize, labelFontSize: textSize)
        guard isViewLoaded,
              let layout = collectionView.collectionViewLayout as? PortalGridCollectionViewLayout else {
            return
        }
        layout.metrics = metrics
        collectionView.reloadData()
        applySelection()
    }

    func updateGridCapacity(_ gridCapacity: GridCapacity) {
        guard self.gridCapacity != gridCapacity else { return }
        self.gridCapacity = gridCapacity
        guard isViewLoaded,
              let layout = collectionView.collectionViewLayout
                as? PortalGridCollectionViewLayout else {
            return
        }
        layout.visibleColumns = gridCapacity.columns
    }

    func captureRuntimeState() -> FileGridRuntimeState {
        let scrollOrigin = (view as? NSScrollView)?.contentView.bounds.origin ?? .zero
        return FileGridRuntimeState(selection: selectionState, scrollOrigin: scrollOrigin)
    }

    func restoreRuntimeState(_ state: FileGridRuntimeState) {
        selectionState = state.selection
        selectionState.reconcile(with: orderedIDs)
        applySelection()
        if let scrollView = view as? NSScrollView {
            scrollView.contentView.scroll(to: state.scrollOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func handleClick(
        index: Int?,
        modifiers: NSEvent.ModifierFlags,
        clickCount: Int = 1
    ) {
        guard let index, items.indices.contains(index) else {
            selectionState.clear()
            applySelection()
            return
        }

        let id = items[index].id
        if modifiers.contains(.shift) {
            selectionState.extendRange(to: id, in: orderedIDs)
        } else if modifiers.contains(.command) {
            selectionState.toggle(id, in: orderedIDs)
        } else {
            selectionState.select(id)
        }
        applySelection()

        if clickCount >= 2 {
            open(items[index])
        }
    }

    func handleKeyCommand(_ command: FileGridKeyCommand) {
        switch command {
        case .moveLeft(let extending):
            moveFocus(offset: -1, extending: extending, scrollPosition: .nearestHorizontalEdge)
        case .moveRight(let extending):
            moveFocus(offset: 1, extending: extending, scrollPosition: .nearestHorizontalEdge)
        case .moveUp(let extending):
            moveFocus(offset: -columnCount, extending: extending, scrollPosition: .nearestVerticalEdge)
        case .moveDown(let extending):
            moveFocus(offset: columnCount, extending: extending, scrollPosition: .nearestVerticalEdge)
        case .selectAll:
            selectionState.selectAll(orderedIDs)
            applySelection()
        case .openSelection:
            openSelection()
        case .toggleQuickLook:
            let urls = items.compactMap { item in
                selectionState.selectedIDs.contains(item.id) ? item.url : nil
            }
            if !urls.isEmpty {
                onQuickLookRequested?(urls)
            }
        case .noOperation:
            break
        }
    }

    private var orderedIDs: [FileIdentity] {
        items.map(\.id)
    }

    private var columnCount: Int {
        gridCapacity.columns
    }

    private func moveFocus(
        offset: Int,
        extending: Bool,
        scrollPosition: NSCollectionView.ScrollPosition
    ) {
        guard !items.isEmpty else { return }
        let currentIndex = selectionState.focusID
            .flatMap { focusedID in items.firstIndex { $0.id == focusedID } }
        let targetIndex: Int
        if let currentIndex {
            let candidate = currentIndex + offset
            guard items.indices.contains(candidate) else { return }
            targetIndex = candidate
        } else {
            targetIndex = 0
        }

        let targetID = items[targetIndex].id
        if extending {
            selectionState.extendFocus(to: targetID, in: orderedIDs)
        } else {
            selectionState.moveFocus(to: targetID)
        }
        applySelection()
        lastKeyboardScrollPosition = scrollPosition
        collectionView.scrollToItems(
            at: [IndexPath(item: targetIndex, section: 0)],
            scrollPosition: scrollPosition
        )
    }

    private func openSelection() {
        failedOpenURLs = []
        for item in items where selectionState.selectedIDs.contains(item.id) {
            open(item)
        }
    }

    @discardableResult
    private func open(_ item: FileItem) -> Bool {
        let didOpen = workspaceOpener.open(item.url)
        if !didOpen {
            failedOpenURLs.append(item.url)
            openFailurePresenter.presentFailure(for: item.url)
        }
        return didOpen
    }

    private func applySelection() {
        let selectedPaths = Set(items.indices.compactMap { index -> IndexPath? in
            selectionState.selectedIDs.contains(items[index].id)
                ? IndexPath(item: index, section: 0)
                : nil
        })
        collectionView.selectionIndexPaths = selectedPaths
        let selectedURLs = items.compactMap { item in
            selectionState.selectedIDs.contains(item.id) ? item.url : nil
        }
        onSelectionChanged?(selectedURLs)
    }
}

extension FileGridViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(
            withIdentifier: FileItemCell.reuseIdentifier,
            for: indexPath
        )
        guard let fileCell = cell as? FileItemCell else {
            preconditionFailure("FileItemCell registration contract violated")
        }
        let item = items[indexPath.item]
        fileCell.configure(
            with: item,
            metrics: metrics,
            position: indexPath.item + 1,
            itemCount: items.count,
            onOpen: { [weak self] in self?.open(item) ?? false }
        )
        return fileCell
    }
}
