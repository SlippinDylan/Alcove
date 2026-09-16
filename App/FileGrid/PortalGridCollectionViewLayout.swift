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
