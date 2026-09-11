import AlcoveCore
import AppKit

struct FileGridRuntimeState: Equatable {
    let selection: SelectionState
    let scrollOrigin: NSPoint
}

@MainActor
final class FileGridViewController: NSViewController {
    private let collectionView = FileCollectionView()
    private let workspaceOpener: any WorkspaceOpening
    private var metrics: GridMetrics
    private var items: [FileItem] = []
    private(set) var selectionState = SelectionState()
    private(set) var failedOpenURLs: [URL] = []
    var onQuickLookRequested: (([URL]) -> Void)?
    var onSelectionChanged: (([URL]) -> Void)?

    init(
        workspaceOpener: any WorkspaceOpening = SystemWorkspaceOpener(),
        iconSize: IconSize = .medium
    ) {
        self.workspaceOpener = workspaceOpener
        metrics = GridMetrics(iconSize: iconSize)
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
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = metrics.itemSize
        flowLayout.sectionInset = NSEdgeInsets(
            top: metrics.contentInsets.top,
            left: metrics.contentInsets.leading,
            bottom: metrics.contentInsets.bottom,
            right: metrics.contentInsets.trailing
        )
        flowLayout.minimumInteritemSpacing = metrics.horizontalSpacing
        flowLayout.minimumLineSpacing = metrics.verticalSpacing

        collectionView.collectionViewLayout = flowLayout
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
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView
        view = scrollView
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
        guard metrics.iconSize != iconSize else { return }
        metrics = GridMetrics(iconSize: iconSize)
        guard isViewLoaded,
              let flowLayout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else {
            return
        }
        flowLayout.itemSize = metrics.itemSize
        flowLayout.sectionInset = NSEdgeInsets(
            top: metrics.contentInsets.top,
            left: metrics.contentInsets.leading,
            bottom: metrics.contentInsets.bottom,
            right: metrics.contentInsets.trailing
        )
        flowLayout.invalidateLayout()
        collectionView.reloadData()
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
            moveFocus(offset: -1, extending: extending)
        case .moveRight(let extending):
            moveFocus(offset: 1, extending: extending)
        case .moveUp(let extending):
            moveFocus(offset: -columnCount, extending: extending)
        case .moveDown(let extending):
            moveFocus(offset: columnCount, extending: extending)
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
        GridLayout(metrics: metrics)
            .layout(itemCount: items.count, availableWidth: collectionView.bounds.width)
            .columnCount
    }

    private func moveFocus(offset: Int, extending: Bool) {
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
        collectionView.scrollToItems(at: [IndexPath(item: targetIndex, section: 0)], scrollPosition: .nearestHorizontalEdge)
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
            iconSize: metrics.iconSize,
            position: indexPath.item + 1,
            itemCount: items.count,
            onOpen: { [weak self] in self?.open(item) ?? false }
        )
        return fileCell
    }
}
