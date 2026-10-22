import AlcoveCore
import AppKit

enum FileDropIntent: Equatable {
    case automatic
    case copy
    case move
}

struct FileGridRuntimeState: Equatable {
    let selection: SelectionState
    let scrollOrigin: NSPoint
}

@MainActor
final class FileGridViewController: NSViewController, NSMenuItemValidation {
    private let collectionView = FileCollectionView()
    private let workspaceOpener: any WorkspaceOpening
    private let openFailurePresenter: any WorkspaceOpenFailurePresenting
    private let fileTransferService: any FileTransferPerforming
    private let fileRecycler: any FileRecycling
    private let fileOperationFailurePresenter: any FileOperationFailurePresenting
    private let contextActionPerformer: any FileContextActionPerforming
    private let fileRenamer: any FileRenaming
    private let fileDuplicator: any FileDuplicating
    private let finderInfoOpener: any FinderInfoOpening
    private let fileCompressor: any FileCompressing
    private var metrics: GridMetrics
    private var gridCapacity: GridCapacity
    private var items: [FileItem] = []
    private var compressionTask: Task<Void, Never>?
    private var defaultDropTask: Task<Void, Never>?
    private var defaultDropResolution: DefaultDropResolution?
    private var validatedDrop: ValidatedDrop?

    private struct DropRequest: Equatable {
        let sequenceNumber: Int
        let sourceURLs: [URL]
        let destinationURL: URL
    }

    private struct DefaultDropResolution {
        let request: DropRequest
        var result: Result<FileTransferOperation, Error>?
    }

    private struct ValidatedDrop: Equatable {
        let request: DropRequest
        let operation: FileTransferOperation
        let sourceMask: NSDragOperation
        let modifiers: NSEvent.ModifierFlags
    }
    private(set) var selectionState = SelectionState()
    private(set) var failedOpenURLs: [URL] = []
    private(set) var lastKeyboardScrollPosition: NSCollectionView.ScrollPosition?
    private(set) var dropDestinationURL: URL?
    var onQuickLookRequested: (([URL]) -> Void)?
    var onSelectionChanged: (([URL]) -> Void)?
    var onNavigateDirectory: ((FileItem) -> Void)?
    var onFileOperationCompleted: (() -> Void)?

    init(
        workspaceOpener: any WorkspaceOpening = SystemWorkspaceOpener(),
        openFailurePresenter: any WorkspaceOpenFailurePresenting = WorkspaceOpenFailurePresenter(),
        fileTransferService: any FileTransferPerforming = CoordinatedFileTransferService(),
        fileRecycler: any FileRecycling = SystemFileRecycler(),
        fileOperationFailurePresenter: any FileOperationFailurePresenting = FileOperationFailurePresenter(),
        contextActionPerformer: any FileContextActionPerforming = SystemFileContextActionPerformer(),
        fileRenamer: any FileRenaming = CoordinatedFileRenamingService(),
        fileDuplicator: any FileDuplicating = SystemFileDuplicator(),
        finderInfoOpener: any FinderInfoOpening = FinderInfoAppleEventOpener(),
        fileCompressor: any FileCompressing = DittoFileCompressionService(),
        iconSize: IconSize = .medium,
        textSize: CGFloat = 12,
        gridCapacity: GridCapacity = .minimum
    ) {
        self.workspaceOpener = workspaceOpener
        self.openFailurePresenter = openFailurePresenter
        self.fileTransferService = fileTransferService
        self.fileRecycler = fileRecycler
        self.fileOperationFailurePresenter = fileOperationFailurePresenter
        self.contextActionPerformer = contextActionPerformer
        self.fileRenamer = fileRenamer
        self.fileDuplicator = fileDuplicator
        self.finderInfoOpener = finderInfoOpener
        self.fileCompressor = fileCompressor
        metrics = GridMetrics(iconSize: iconSize, labelFontSize: textSize)
        self.gridCapacity = gridCapacity
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        compressionTask?.cancel()
        defaultDropTask?.cancel()
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
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.register(
            FileItemCell.self,
            forItemWithIdentifier: FileItemCell.reuseIdentifier
        )
        collectionView.onNativeItemInteraction = {
            [weak self] indexes, clickedIndex, modifiers, clickCount in
            self?.handleNativeItemInteraction(
                indexes: indexes,
                clickedIndex: clickedIndex,
                modifiers: modifiers,
                clickCount: clickCount
            )
        }
        collectionView.onKeyCommand = { [weak self] command in
            self?.handleKeyCommand(command)
        }
        collectionView.onMarqueeSelection = { [weak self] indexes in
            self?.replaceSelection(with: indexes)
        }
        collectionView.onValidateDrop = { [weak self] info in self?.validateFileDrop(info) }
        collectionView.onAcceptDrop = { [weak self] info in self?.acceptFileDrop(info) ?? false }
        collectionView.onDropSessionEnded = { [weak self] in self?.endFileDropSession() }
        collectionView.contextMenuProvider = { [weak self] index in
            self?.contextMenu(forItemAt: index)
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.controlSize = .mini
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
        collectionView.endDropSession()
        self.items = items
        selectionState.reconcile(with: orderedIDs)
        collectionView.reloadData()
        applySelection()
    }

    func updateDropDestination(_ url: URL?) {
        let destination = url?.standardizedFileURL
        if destination != dropDestinationURL { collectionView.endDropSession() }
        dropDestinationURL = destination
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

    private func handleNativeItemInteraction(
        indexes: Set<Int>,
        clickedIndex: Int,
        modifiers: NSEvent.ModifierFlags,
        clickCount: Int
    ) {
        guard items.indices.contains(clickedIndex) else { return }
        let ids = Set(indexes.compactMap { index in
            items.indices.contains(index) ? items[index].id : nil
        })
        let clickedID = items[clickedIndex].id
        let preferredAnchorID = modifiers.contains(.shift)
            ? selectionState.anchorID
            : clickedID
        selectionState.replaceSelection(
            with: ids,
            in: orderedIDs,
            preferredAnchorID: preferredAnchorID,
            preferredFocusID: clickedID
        )
        notifySelectionChanged()

        if clickCount >= 2 {
            open(items[clickedIndex])
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
        case .renameSelection:
            beginRenamingSelection()
        case .trashSelection:
            trashSelection()
        case .toggleQuickLook:
            let urls = selectedItemsInGridOrder.map(\.url)
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

    private var selectedItemsInGridOrder: [FileItem] {
        items.filter { selectionState.selectedIDs.contains($0.id) }
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
        let selectedItems = selectedItemsInGridOrder
        let allowsNavigation = selectedItems.count == 1
        for item in selectedItems {
            open(item, allowsNavigation: allowsNavigation)
        }
    }

    private func replaceSelection(with indexes: Set<Int>) {
        let ids = Set(indexes.compactMap { index in
            items.indices.contains(index) ? items[index].id : nil
        })
        selectionState.replaceSelection(with: ids, in: orderedIDs)
        applySelection()
    }

    private func trashSelection() {
        let urls = selectedItemsInGridOrder.map(\.url)
        guard !urls.isEmpty else { return }

        // Freeze the URL snapshot before invalidating selection and Quick Look ownership.
        selectionState.clear()
        applySelection()
        fileRecycler.recycle(urls) { [weak self] error in
            guard let self else { return }
            if let error {
                fileOperationFailurePresenter.present(error)
            } else {
                onFileOperationCompleted?()
            }
        }
    }

    @discardableResult
    private func open(_ item: FileItem, allowsNavigation: Bool = true) -> Bool {
        if allowsNavigation, item.isNavigableDirectory, let onNavigateDirectory {
            onNavigateDirectory(item)
            return true
        }
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
        notifySelectionChanged()
    }

    private func notifySelectionChanged() {
        onSelectionChanged?(selectedItemsInGridOrder.map(\.url))
    }

    func contextMenu(forItemAt index: Int) -> NSMenu? {
        guard items.indices.contains(index) else { return nil }
        let clickedID = items[index].id
        if !selectionState.selectedIDs.contains(clickedID) {
            selectionState.select(clickedID)
            applySelection()
        }

        let menu = NSMenu()
        menu.addItem(menuItem(
            "portal.files.open",
            symbolName: "arrow.up.forward.app",
            action: #selector(openFromContextMenu)
        ))
        menu.addItem(menuItem(
            "portal.files.quick_look",
            symbolName: "eye",
            action: #selector(quickLookFromContextMenu)
        ))
        menu.addItem(menuItem(
            "portal.files.show_in_finder",
            symbolName: "folder",
            action: #selector(revealFromContextMenu)
        ))
        menu.addItem(menuItem(
            "portal.files.get_info",
            symbolName: "info.circle",
            action: #selector(inspectFromContextMenu)
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            "portal.files.rename",
            symbolName: "pencil",
            action: #selector(renameFromContextMenu)
        ))
        menu.addItem(menuItem(
            "portal.files.compress",
            symbolName: "archivebox",
            action: #selector(compressFromContextMenu)
        ))
        menu.addItem(menuItem(
            "portal.files.duplicate",
            symbolName: "plus.square.on.square",
            action: #selector(duplicateFromContextMenu)
        ))
        menu.addItem(menuItem(
            "portal.files.move_to_trash",
            symbolName: "trash",
            action: #selector(trashFromContextMenu)
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            "portal.files.airdrop",
            symbolName: "square.and.arrow.up",
            action: #selector(airDropFromContextMenu)
        ))
        menu.addItem(menuItem(
            "portal.files.copy_path",
            symbolName: "document.on.document",
            action: #selector(copyPathFromContextMenu)
        ))
        menu.addItem(menuItem(
            "portal.files.open_in_terminal",
            symbolName: "terminal",
            action: #selector(openInTerminalFromContextMenu)
        ))
        return menu
    }

    private func menuItem(
        _ localizationKey: String,
        symbolName: String,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString(localizationKey, comment: "File context menu item"),
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: item.title
        )
        item.image?.isTemplate = true
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let urls = selectedItemsInGridOrder.map(\.url)
        guard !urls.isEmpty else { return false }
        if menuItem.action == #selector(airDropFromContextMenu) {
            return contextActionPerformer.canSendViaAirDrop(urls)
        }
        if menuItem.action == #selector(renameFromContextMenu) {
            return urls.count == 1
        }
        if menuItem.action == #selector(inspectFromContextMenu) {
            return urls.count == 1
        }
        if menuItem.action == #selector(compressFromContextMenu) {
            return compressionTask == nil
        }
        return true
    }

    @objc private func openFromContextMenu() {
        openSelection()
    }

    @objc private func quickLookFromContextMenu() {
        let urls = selectedItemsInGridOrder.map(\.url)
        if !urls.isEmpty {
            onQuickLookRequested?(urls)
        }
    }

    @objc private func revealFromContextMenu() {
        contextActionPerformer.revealInFinder(selectedItemsInGridOrder.map(\.url))
    }

    @objc private func inspectFromContextMenu() {
        let selectedItems = selectedItemsInGridOrder
        guard selectedItems.count == 1, let item = selectedItems.first else { return }
        Task { [weak self, finderInfoOpener] in
            do {
                try await finderInfoOpener.openInfo(for: item.url)
            } catch {
                self?.fileOperationFailurePresenter.present(error)
            }
        }
    }

    @objc private func trashFromContextMenu() {
        trashSelection()
    }

    @objc private func renameFromContextMenu() {
        beginRenamingSelection()
    }

    @objc private func duplicateFromContextMenu() {
        duplicateSelection()
    }

    @objc private func compressFromContextMenu() {
        compressSelection()
    }

    @objc private func copyPathFromContextMenu() {
        contextActionPerformer.copyPaths(selectedItemsInGridOrder.map(\.url))
    }

    @objc private func airDropFromContextMenu() {
        let urls = selectedItemsInGridOrder.map(\.url)
        guard contextActionPerformer.sendViaAirDrop(urls) else {
            fileOperationFailurePresenter.present(FileContextActionError.airDropUnavailable)
            return
        }
    }

    @objc private func openInTerminalFromContextMenu() {
        var seen = Set<URL>()
        let directories = selectedItemsInGridOrder.compactMap { item -> URL? in
            let directory = item.isNavigableDirectory
                ? item.url
                : item.url.deletingLastPathComponent()
            return seen.insert(directory.standardizedFileURL).inserted
                ? directory.standardizedFileURL
                : nil
        }
        contextActionPerformer.openInTerminal(directories) { [weak self] error in
            if let error {
                self?.fileOperationFailurePresenter.present(error)
            }
        }
    }

    private func beginRenamingSelection() {
        guard selectedItemsInGridOrder.count == 1,
              let selectedItem = selectedItemsInGridOrder.first,
              let index = items.firstIndex(where: { $0.id == selectedItem.id }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
        collectionView.layoutSubtreeIfNeeded()
        guard let cell = collectionView.item(at: indexPath) as? FileItemCell else { return }
        cell.beginRenaming(selecting: Self.renameSelectionRange(for: selectedItem)) {
            [weak self] newName in
            self?.commitRename(selectedItem, to: newName)
        }
    }

    static func renameSelectionRange(for item: FileItem) -> NSRange {
        let name = item.name as NSString
        guard !item.isDirectory || item.isPackage else {
            return NSRange(location: 0, length: name.length)
        }
        let pathExtension = name.pathExtension as NSString
        guard pathExtension.length > 0 else {
            return NSRange(location: 0, length: name.length)
        }
        return NSRange(location: 0, length: name.length - pathExtension.length - 1)
    }

    func commitRename(_ item: FileItem, to newName: String) {
        Task { [weak self, fileRenamer] in
            do {
                let renamedURL = try await fileRenamer.rename(item.url, to: newName)
                guard let self else { return }
                selectionState.select(FileIdentity(url: renamedURL))
                onSelectionChanged?([renamedURL])
                onFileOperationCompleted?()
            } catch {
                self?.fileOperationFailurePresenter.present(error)
            }
        }
    }

    private func duplicateSelection() {
        let sourceURLs = selectedItemsInGridOrder.map(\.url)
        guard !sourceURLs.isEmpty else { return }
        fileDuplicator.duplicate(sourceURLs) { [weak self] duplicatedURLs, error in
            guard let self else { return }
            if !duplicatedURLs.isEmpty {
                let duplicatedIDs = duplicatedURLs.map(FileIdentity.init(url:))
                selectionState = SelectionState()
                selectionState.selectAll(duplicatedIDs)
                onSelectionChanged?(duplicatedURLs)
                onFileOperationCompleted?()
            }
            if let error {
                fileOperationFailurePresenter.present(error)
            }
        }
    }

    private func compressSelection() {
        let sourceURLs = selectedItemsInGridOrder.map(\.url)
        guard !sourceURLs.isEmpty, compressionTask == nil else { return }
        compressionTask = Task { [weak self, fileCompressor] in
            do {
                let archiveURL = try await fileCompressor.compress(sourceURLs)
                guard let self else { return }
                selectionState.select(FileIdentity(url: archiveURL))
                onSelectionChanged?([archiveURL])
                onFileOperationCompleted?()
                compressionTask = nil
            } catch is CancellationError {
                self?.compressionTask = nil
            } catch {
                guard let self else { return }
                fileOperationFailurePresenter.present(error)
                compressionTask = nil
            }
        }
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
            opensDirectoryInPanel: onNavigateDirectory != nil,
            onOpen: { [weak self] in self?.open(item) ?? false }
        )
        return fileCell
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> (any NSPasteboardWriting)? {
        guard items.indices.contains(indexPath.item) else { return nil }
        return items[indexPath.item].url as NSURL
    }

    private func validateFileDrop(_ info: any NSDraggingInfo) -> FileGridDropProposal? {
        validatedDrop = nil
        collectionView.layoutSubtreeIfNeeded()
        let point = collectionView.convert(info.draggingLocation, from: nil)
        let targetIndex = collectionView.collectionViewLayout?.layoutAttributesForElements(
            in: NSRect(origin: point, size: NSSize(width: 1, height: 1))
        ).first(where: { $0.representedElementCategory == .item && $0.frame.contains(point) })?.indexPath?.item
        let isLocal = info.draggingSource as AnyObject? === collectionView
        guard collectionView.visibleRect.contains(point),
              let destination = destinationURL(forDropAt: targetIndex, isLocal: isLocal),
              let sources = Self.fileURLs(from: info.draggingPasteboard), !sources.isEmpty,
              let requested = Self.requestedTransferOperation(
                  sourceMask: info.draggingSourceOperationMask, modifiers: NSEvent.modifierFlags
              ) else {
            resetDefaultDropOperation()
            return nil
        }
        let request = DropRequest(
            sequenceNumber: info.draggingSequenceNumber, sourceURLs: sources, destinationURL: destination
        )
        let operation: FileTransferOperation
        if requested == .automatic {
            guard let resolved = defaultOperation(for: request) else { return nil }
            operation = resolved
        } else {
            resetDefaultDropOperation()
            operation = requested == .copy ? .copy : .move
        }
        let nativeOperation: NSDragOperation = operation == .copy ? .copy : .move
        guard info.draggingSourceOperationMask.contains(nativeOperation) else { return nil }
        validatedDrop = ValidatedDrop(
            request: request, operation: operation,
            sourceMask: info.draggingSourceOperationMask, modifiers: NSEvent.modifierFlags
        )
        let folderIndexPath = targetIndex.flatMap { index in
            items[index].isNavigableDirectory ? IndexPath(item: index, section: 0) : nil
        }
        return FileGridDropProposal(operation: nativeOperation, folderIndexPath: folderIndexPath)
    }

    private func defaultOperation(for request: DropRequest) -> FileTransferOperation? {
        if defaultDropResolution?.request != request {
            resetDefaultDropOperation()
            defaultDropResolution = DefaultDropResolution(request: request)
            defaultDropTask = Task { [weak self, fileTransferService] in
                let result: Result<FileTransferOperation, Error>
                do {
                    try Task.checkCancellation()
                    result = .success(try await fileTransferService.defaultOperation(
                        sourceURLs: request.sourceURLs, to: request.destinationURL
                    ))
                } catch {
                    result = .failure(error)
                }
                guard !Task.isCancelled, let self,
                      self.defaultDropResolution?.request == request else { return }
                self.defaultDropResolution?.result = result
            }
        }
        guard case .success(let operation) = defaultDropResolution?.result else { return nil }
        return operation
    }

    private func acceptFileDrop(_ info: any NSDraggingInfo) -> Bool {
        guard let drop = validatedDrop,
              validateFileDrop(info) != nil, validatedDrop == drop else { return false }
        // Freeze the exact operation offered to AppKit; transfer IO must not choose a different one.
        Task { [weak self, fileTransferService] in
            do {
                try await fileTransferService.transfer(
                    sourceURLs: drop.request.sourceURLs,
                    to: drop.request.destinationURL, operation: drop.operation
                )
                self?.onFileOperationCompleted?()
            } catch {
                self?.fileOperationFailurePresenter.present(error)
            }
        }
        return true
    }

    private func resetDefaultDropOperation() {
        defaultDropTask?.cancel()
        defaultDropTask = nil
        defaultDropResolution = nil
    }

    private func endFileDropSession() {
        let result = defaultDropResolution?.result
        resetDefaultDropOperation()
        validatedDrop = nil
        // Present preparation failures after leaving the native drag callback stack.
        if case .failure(let error) = result {
            Task { [weak self] in self?.fileOperationFailurePresenter.present(error) }
        }
    }

    func destinationURL(forDropAt index: Int?, isLocal: Bool) -> URL? {
        if let index {
            guard items.indices.contains(index) else { return nil }
            if items[index].isNavigableDirectory {
                return items[index].url
            }
        }
        return isLocal ? nil : dropDestinationURL
    }

    static func requestedTransferOperation(
        sourceMask: NSDragOperation,
        modifiers: NSEvent.ModifierFlags
    ) -> FileDropIntent? {
        if modifiers.contains([.command, .option]) {
            return nil
        }
        if modifiers.contains(.option), sourceMask.contains(.copy) {
            return .copy
        }
        if modifiers.contains(.command), sourceMask.contains(.move) {
            return .move
        }
        if sourceMask.contains(.copy), !sourceMask.contains(.move) {
            return .copy
        }
        if sourceMask.contains(.move), !sourceMask.contains(.copy) {
            return .move
        }
        guard sourceMask.contains(.copy), sourceMask.contains(.move) else { return nil }
        return .automatic
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
}
