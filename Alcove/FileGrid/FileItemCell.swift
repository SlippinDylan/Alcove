import AlcoveCore
import AppKit

@MainActor
final class FileItemCell: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FileItemCell")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var itemPosition = 0
    private var itemCount = 0
    private var onOpen: (() -> Bool)?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(iconView)
        view.addSubview(nameLabel)
        let iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 64)
        let iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 64)
        self.iconWidthConstraint = iconWidthConstraint
        self.iconHeightConstraint = iconHeightConstraint
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconWidthConstraint,
            iconHeightConstraint,
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -4),
        ])
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.24).cgColor
                : NSColor.clear.cgColor
            updateAccessibilityValue()
        }
    }

    func configure(
        with item: FileItem,
        iconSize: IconSize,
        position: Int,
        itemCount: Int,
        onOpen: @escaping () -> Bool
    ) {
        representedObject = item
        itemPosition = position
        self.itemCount = itemCount
        self.onOpen = onOpen
        iconWidthConstraint?.constant = iconSize.rawValue
        iconHeightConstraint?.constant = iconSize.rawValue
        nameLabel.stringValue = item.name
        iconView.image = NSWorkspace.shared.icon(forFile: item.url.path)
        view.toolTip = item.name
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(item.name)
        updateAccessibilityValue()
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

    @objc func performAccessibilityOpen() -> Bool {
        onOpen?() ?? false
    }
}
