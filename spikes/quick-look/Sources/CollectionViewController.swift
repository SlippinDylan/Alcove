// CollectionViewController.swift
// Alcove Spike 0.3A — Quick Look Responder Bootstrap
// Disposable harness; not production architecture.

import AppKit

@MainActor
final class SpaceHandlingCollectionView: NSCollectionView {
    var onSpacePressed: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onSpacePressed?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class CollectionViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let quickLookResponder: QuickLookResponder

    private(set) var collectionView: SpaceHandlingCollectionView?
    private let diagnosticsLabel = NSTextField(labelWithString: "Selected: none")
    private var windowStrategy: PreviewWindowLevelStrategy?

    var onSelectionChanged: (([Int]) -> Void)?

    init(quickLookResponder: QuickLookResponder) {
        self.quickLookResponder = quickLookResponder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let rootView = NSView()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let collectionView = SpaceHandlingCollectionView()
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.onSpacePressed = { [weak self] in
            self?.quickLookResponder.togglePanel()
        }
        collectionView.register(FixtureItem.self, forItemWithIdentifier: FixtureItem.identifier)

        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        collectionView.collectionViewLayout = layout
        scrollView.documentView = collectionView

        diagnosticsLabel.translatesAutoresizingMaskIntoConstraints = false
        diagnosticsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnosticsLabel.lineBreakMode = .byTruncatingMiddle
        diagnosticsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        rootView.addSubview(diagnosticsLabel)
        rootView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            diagnosticsLabel.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 8),
            diagnosticsLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12),
            diagnosticsLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: diagnosticsLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])

        self.collectionView = collectionView
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateItemSize()
        updateDiagnostics()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateItemSize()
    }

    func focusCollection(in window: NSWindow) {
        guard let collectionView else { return }
        window.makeFirstResponder(collectionView)
    }

    func updateWindowStrategy(_ strategy: PreviewWindowLevelStrategy) {
        windowStrategy = strategy
        updateDiagnostics()
    }

    private func updateItemSize() {
        guard let collectionView,
              let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout
        else { return }
        let availableWidth = collectionView.visibleRect.width - 24
        guard availableWidth > 0 else { return }
        layout.itemSize = NSSize(width: availableWidth, height: 44)
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        quickLookResponder.fixtures.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: FixtureItem.identifier, for: indexPath)
        guard let fixtureItem = item as? FixtureItem,
              quickLookResponder.fixtures.indices.contains(indexPath.item)
        else { return item }

        let fixture = quickLookResponder.fixtures[indexPath.item]
        fixtureItem.configure(
            name: fixture.displayName,
            icon: NSWorkspace.shared.icon(forFile: fixture.url.path)
        )
        return fixtureItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToResponder()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToResponder()
    }

    private func syncSelectionToResponder() {
        guard let collectionView else { return }
        let indices = collectionView.selectionIndexes.sorted()
        quickLookResponder.setSelectedIndices(indices)
        updateDiagnostics()
        onSelectionChanged?(indices)
    }

    private func updateDiagnostics() {
        let names = quickLookResponder.selectedPreviewItems.map(\.fixtureTitle)
        let selection = names.isEmpty ? "none" : names.joined(separator: ", ")
        let windowText = windowStrategy.map { " | Window: \($0.name) (\($0.level.rawValue))" } ?? ""
        diagnosticsLabel.stringValue = "Selected: \(selection)\(windowText)"
    }
}

private final class FixtureItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FixtureItem")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let container = NSView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        container.addSubview(iconView)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = .systemFont(ofSize: 13)
        container.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        view = container
    }

    func configure(name: String, icon: NSImage?) {
        nameLabel.stringValue = name
        iconView.image = icon
    }
}
