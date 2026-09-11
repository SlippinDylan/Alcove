import AlcoveCore
import AppKit

@MainActor
final class FileGridViewController: NSViewController {
    private let collectionView = NSCollectionView()
    private var items: [FileItem] = []

    var itemCount: Int {
        items.count
    }

    override func loadView() {
        let metrics = GridMetrics(iconSize: .medium)
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

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView
        view = scrollView
    }

    func setItems(_ items: [FileItem]) {
        self.items = items
        collectionView.reloadData()
    }

    func item(at index: Int) -> FileItem {
        items[index]
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
        fileCell.configure(with: items[indexPath.item])
        return fileCell
    }
}
