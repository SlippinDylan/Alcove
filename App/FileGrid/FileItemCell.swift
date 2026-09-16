import AlcoveCore
import AppKit

@MainActor
final class FileItemCell: NSCollectionViewItem, NSTextFieldDelegate {
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
    private var renameState: RenameState?

    private struct RenameState {
        let originalName: String
        let onCommit: (String) -> Void
    }

    override func loadView() {
        let rootView = FileItemRootView()
        rootView.onAppearanceChange = { [weak self] in
            self?.updateSelectionAppearance()
        }
        view = rootView

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
        nameLabel.delegate = self
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
        opensDirectoryInPanel: Bool = false,
        onOpen: @escaping () -> Bool
    ) {
        cancelRenaming()
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
        let accessibilityHelp = item.isNavigableDirectory && opensDirectoryInPanel
            ? NSLocalizedString(
                "portal.item.folder.navigate.help",
                comment: "Accessibility help for a navigable folder item"
            )
            : item.isDirectory ? NSLocalizedString(
                "Folder. Double-click to open in Finder.",
                comment: "Accessibility help for a folder item"
            ) : NSLocalizedString(
                "File. Double-click to open.",
                comment: "Accessibility help for a file item"
            )
        view.setAccessibilityHelp(accessibilityHelp)
        view.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(
                name: NSLocalizedString("Open", comment: "Accessibility action to open an item"),
                target: self,
                selector: #selector(performAccessibilityOpen)
            ),
        ])
    }

    func beginRenaming(
        selecting range: NSRange,
        onCommit: @escaping (String) -> Void
    ) {
        guard renameState == nil else { return }
        renameState = RenameState(originalName: nameLabel.stringValue, onCommit: onCommit)
        nameLabel.isEditable = true
        nameLabel.isSelectable = true
        nameLabel.maximumNumberOfLines = 1
        nameLabel.lineBreakMode = .byClipping
        view.window?.makeFirstResponder(nameLabel)
        nameLabel.currentEditor()?.selectedRange = range
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            finishRenaming(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finishRenaming(commit: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finishRenaming(commit: true)
    }

    private func finishRenaming(commit: Bool) {
        guard let state = renameState else { return }
        let proposedName = nameLabel.stringValue
        renameState = nil
        nameLabel.abortEditing()
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.maximumNumberOfLines = 2
        nameLabel.lineBreakMode = .byCharWrapping
        nameLabel.stringValue = state.originalName
        if commit {
            state.onCommit(proposedName)
        }
    }

    private func cancelRenaming() {
        finishRenaming(commit: false)
    }

    private func updateAccessibilityValue() {
        let selection = isSelected
            ? NSLocalizedString("Selected", comment: "Accessibility state for a selected item")
            : NSLocalizedString("Not selected", comment: "Accessibility state for an unselected item")
        let format = NSLocalizedString(
            "%1$@, item %2$d of %3$d",
            comment: "Accessibility value showing selection and item position"
        )
        view.setAccessibilityValue(
            String(format: format, selection, itemPosition, itemCount)
        )
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
