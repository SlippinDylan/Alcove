import AppKit

@MainActor
final class FolderPathBarView: NSView {
    private(set) var contentView = NSView()
    private let pathIcon = NSImageView()
    private(set) var pathLabel = NSTextField(labelWithString: "")
    private(set) var terminalButton = NSButton()
    private(set) var copyButton = NSButton()
    private(set) var actionSpacer = NSView()
    private(set) var displayedPath: String?
    private(set) var folderURL: URL?
    private let pathOpener: any FolderPathOpening
    private let failurePresenter: any FolderPathOpenFailurePresenting

    init(
        pathOpener: any FolderPathOpening,
        failurePresenter: any FolderPathOpenFailurePresenting
    ) {
        self.pathOpener = pathOpener
        self.failurePresenter = failurePresenter
        super.init(frame: .zero)
        configureView()
    }

    override init(frame frameRect: NSRect) {
        pathOpener = SystemFolderPathOpener()
        failurePresenter = FolderPathOpenFailurePresenter()
        super.init(frame: frameRect)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(folderURL: URL?) {
        guard let folderURL else {
            displayedPath = nil
            self.folderURL = nil
            contentView.isHidden = true
            return
        }
        let standardizedURL = folderURL.standardizedFileURL
        let path = NSString(
            string: standardizedURL.path
        ).abbreviatingWithTildeInPath
        self.folderURL = standardizedURL
        displayedPath = path
        pathLabel.stringValue = path
        pathLabel.toolTip = path
        contentView.isHidden = false
    }

    private func configureView() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        pathIcon.image = NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: nil
        )
        pathIcon.contentTintColor = .secondaryLabelColor
        pathIcon.translatesAutoresizingMaskIntoConstraints = false
        pathIcon.addGestureRecognizer(NSClickGestureRecognizer(
            target: self,
            action: #selector(openInFinder)
        ))

        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.setAccessibilityLabel(
            NSLocalizedString("portal.path.label", comment: "Folder path accessibility label")
        )
        pathLabel.addGestureRecognizer(NSClickGestureRecognizer(
            target: self,
            action: #selector(openInFinder)
        ))

        terminalButton.image = NSImage(
            systemSymbolName: "terminal",
            accessibilityDescription: nil
        )
        terminalButton.imagePosition = .imageOnly
        terminalButton.isBordered = false
        terminalButton.contentTintColor = .secondaryLabelColor
        terminalButton.target = self
        terminalButton.action = #selector(openInTerminal)
        terminalButton.toolTip = NSLocalizedString(
            "portal.path.terminal",
            comment: "Open folder in Terminal"
        )
        terminalButton.setAccessibilityLabel(terminalButton.toolTip ?? "")

        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: nil
        )
        copyButton.imagePosition = .imageOnly
        copyButton.isBordered = false
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.target = self
        copyButton.action = #selector(copyPath)
        copyButton.toolTip = NSLocalizedString("portal.path.copy", comment: "Copy folder path")
        copyButton.setAccessibilityLabel(copyButton.toolTip ?? "")

        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [
            pathIcon,
            pathLabel,
            actionSpacer,
            terminalButton,
            copyButton,
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            pathIcon.widthAnchor.constraint(equalToConstant: 16),
            pathIcon.heightAnchor.constraint(equalToConstant: 16),
            terminalButton.widthAnchor.constraint(equalToConstant: 28),
            terminalButton.heightAnchor.constraint(equalToConstant: 28),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc func openInFinder() {
        guard let folderURL else { return }
        if !pathOpener.openInFinder(folderURL) {
            failurePresenter.present(.finderLaunchFailed, for: folderURL)
        }
    }

    @objc func openInTerminal() {
        guard let folderURL else { return }
        pathOpener.openInTerminal(folderURL) { [weak self] error in
            guard let self, let error else { return }
            self.failurePresenter.present(error, for: folderURL)
        }
    }

    @objc private func copyPath() {
        guard let folderURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(folderURL.path, forType: .string)
    }
}
