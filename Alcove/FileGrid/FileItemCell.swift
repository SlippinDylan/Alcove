import AlcoveCore
import AppKit

@MainActor
final class FileItemCell: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FileItemCell")

    private(set) var iconView = NSImageView()
    private(set) var nameLabel = NSTextField(labelWithString: "")
    private(set) var iconSelectionView = NSView()
    private(set) var labelSelectionView = NSView()
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var iconSelectionWidthConstraint: NSLayoutConstraint?
    private var iconSelectionHeightConstraint: NSLayoutConstraint?
    private var labelMaximumWidthConstraint: NSLayoutConstraint?
    private var iconLabelSpacingConstraint: NSLayoutConstraint?
    private var itemPosition = 0
    private var itemCount = 0
    private var onOpen: (() -> Bool)?

    override func loadView() {
        let rootView = FileItemRootView()
        rootView.onAppearanceChange = { [weak self] in
            self?.updateSelectionAppearance()
        }
        view = rootView
        view.wantsLayer = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconSelectionView.wantsLayer = true
        iconSelectionView.layer?.cornerRadius = 10
        iconSelectionView.translatesAutoresizingMaskIntoConstraints = false
        labelSelectionView.wantsLayer = true
        labelSelectionView.layer?.cornerRadius = 6
        labelSelectionView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byCharWrapping
        nameLabel.maximumNumberOfLines = 2
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(iconSelectionView)
        iconSelectionView.addSubview(iconView)
        view.addSubview(labelSelectionView)
        labelSelectionView.addSubview(nameLabel)
        let iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 64)
        let iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 64)
        let iconSelectionWidthConstraint = iconSelectionView.widthAnchor.constraint(
            equalToConstant: 72
        )
        let iconSelectionHeightConstraint = iconSelectionView.heightAnchor.constraint(
            equalToConstant: 72
        )
        let labelMaximumWidthConstraint = labelSelectionView.widthAnchor.constraint(
            lessThanOrEqualToConstant: GridMetrics(iconSize: .medium).itemSize.width
        )
        self.iconWidthConstraint = iconWidthConstraint
        self.iconHeightConstraint = iconHeightConstraint
        self.iconSelectionWidthConstraint = iconSelectionWidthConstraint
        self.iconSelectionHeightConstraint = iconSelectionHeightConstraint
        self.labelMaximumWidthConstraint = labelMaximumWidthConstraint
        let iconLabelSpacingConstraint = labelSelectionView.topAnchor.constraint(
            equalTo: iconSelectionView.bottomAnchor,
            constant: 4
        )
        self.iconLabelSpacingConstraint = iconLabelSpacingConstraint
        NSLayoutConstraint.activate([
            iconSelectionView.topAnchor.constraint(equalTo: view.topAnchor),
            iconSelectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconSelectionWidthConstraint,
            iconSelectionHeightConstraint,
            iconView.centerXAnchor.constraint(equalTo: iconSelectionView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconSelectionView.centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,
            iconLabelSpacingConstraint,
            labelSelectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            labelSelectionView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            labelSelectionView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            labelSelectionView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            labelMaximumWidthConstraint,
            nameLabel.topAnchor.constraint(equalTo: labelSelectionView.topAnchor, constant: 2),
            nameLabel.leadingAnchor.constraint(equalTo: labelSelectionView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: labelSelectionView.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: labelSelectionView.bottomAnchor, constant: -2),
        ])
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
            updateAccessibilityValue()
        }
    }

    func configure(
        with item: FileItem,
        metrics: GridMetrics,
        position: Int,
        itemCount: Int,
        onOpen: @escaping () -> Bool
    ) {
        representedObject = item
        itemPosition = position
        self.itemCount = itemCount
        self.onOpen = onOpen
        iconWidthConstraint?.constant = metrics.iconSize.rawValue
        iconHeightConstraint?.constant = metrics.iconSize.rawValue
        iconSelectionWidthConstraint?.constant = metrics.iconSelectionSize.width
        iconSelectionHeightConstraint?.constant = metrics.iconSelectionSize.height
        labelMaximumWidthConstraint?.constant = metrics.itemSize.width
        iconLabelSpacingConstraint?.constant = metrics.iconLabelSpacing
        nameLabel.font = NSFont.systemFont(ofSize: metrics.labelFontSize)
        nameLabel.preferredMaxLayoutWidth = metrics.itemSize.width - 8
        nameLabel.stringValue = item.name
        iconView.image = NSWorkspace.shared.icon(forFile: item.url.path)
        view.toolTip = item.name
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(item.name)
        updateAccessibilityValue()
        updateSelectionAppearance()
        view.setAccessibilityHelp(item.isDirectory ? "Folder. Double-click to open in Finder." : "File. Double-click to open.")
        view.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(
                name: "Open",
                target: self,
                selector: #selector(performAccessibilityOpen)
            ),
        ])
    }

    private func updateAccessibilityValue() {
        let selection = isSelected ? "Selected" : "Not selected"
        view.setAccessibilityValue("\(selection), item \(itemPosition) of \(itemCount)")
    }

    private func updateSelectionAppearance() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            iconSelectionView.layer?.backgroundColor = isSelected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).cgColor
                : NSColor.clear.cgColor
            iconSelectionView.layer?.borderWidth = isSelected ? 1 : 0
            iconSelectionView.layer?.borderColor = isSelected
                ? NSColor.separatorColor.cgColor
                : nil
            labelSelectionView.layer?.backgroundColor = isSelected
                ? NSColor.selectedContentBackgroundColor.cgColor
                : NSColor.clear.cgColor
            nameLabel.textColor = isSelected ? .white : .labelColor
        }
    }

    @objc func performAccessibilityOpen() -> Bool {
        onOpen?() ?? false
    }
}

@MainActor
private final class FileItemRootView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}
