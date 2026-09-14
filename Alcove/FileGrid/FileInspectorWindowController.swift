import AppKit
import Foundation

struct FileInspectorMetadata: Equatable, Sendable {
    let url: URL
    let name: String
    let localizedType: String
    let creationDate: Date?
    let modificationDate: Date?
    let fileSize: Int64?
    let calculatesFolderSize: Bool
}

protocol FileInspectorLoading: Sendable {
    func metadata(for url: URL) async throws -> FileInspectorMetadata
    func folderSize(for url: URL) async throws -> Int64
}

actor FileInspectorLoader: FileInspectorLoading {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func metadata(for rawURL: URL) throws -> FileInspectorMetadata {
        try Task.checkCancellation()
        let url = rawURL.standardizedFileURL
        let values = try url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .localizedTypeDescriptionKey,
            .totalFileSizeKey,
        ])
        let calculatesFolderSize = values.isDirectory == true
            && values.isPackage != true
            && values.isSymbolicLink != true
        return FileInspectorMetadata(
            url: url,
            name: url.lastPathComponent,
            localizedType: values.localizedTypeDescription ?? NSLocalizedString(
                "portal.files.inspector.unknown_type",
                comment: "Fallback file type in the inspector"
            ),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            fileSize: calculatesFolderSize
                ? nil
                : Int64(values.totalFileSize ?? values.fileSize ?? 0),
            calculatesFolderSize: calculatesFolderSize
        )
    }

    func folderSize(for rawURL: URL) throws -> Int64 {
        try Task.checkCancellation()
        let url = rawURL.standardizedFileURL
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .totalFileSizeKey,
            ],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var byteCount: Int64 = 0
        for case let childURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try childURL.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .totalFileSizeKey,
            ])
            if values.isSymbolicLink == true {
                continue
            }
            if values.isRegularFile == true {
                byteCount += Int64(values.totalFileSize ?? values.fileSize ?? 0)
            }
        }
        if let enumerationError { throw enumerationError }
        return byteCount
    }
}

@MainActor
protocol FileInspectorPresenting: AnyObject {
    func showInspector(for url: URL)
}

@MainActor
final class SystemFileInspectorPresenter: FileInspectorPresenting {
    private let loader: any FileInspectorLoading
    private var windowController: FileInspectorWindowController?

    init(loader: any FileInspectorLoading = FileInspectorLoader()) {
        self.loader = loader
    }

    func showInspector(for url: URL) {
        let controller = windowController ?? FileInspectorWindowController(loader: loader)
        windowController = controller
        controller.inspect(url)
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class FileInspectorWindowController: NSWindowController, NSWindowDelegate {
    private let loader: any FileInspectorLoading
    private let iconView = NSImageView()
    private let nameValue = NSTextField(wrappingLabelWithString: "")
    private let typeValue = NSTextField(wrappingLabelWithString: "")
    private let locationValue = NSTextField(wrappingLabelWithString: "")
    private let createdValue = NSTextField(labelWithString: "")
    private let modifiedValue = NSTextField(labelWithString: "")
    private let sizeValue = NSTextField(labelWithString: "")
    private var loadTask: Task<Void, Never>?

    init(loader: any FileInspectorLoading) {
        self.loader = loader
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        loadTask?.cancel()
    }

    func inspect(_ url: URL) {
        loadTask?.cancel()
        window?.title = String(
            format: NSLocalizedString(
                "portal.files.inspector.window_title",
                comment: "File inspector window title with item name"
            ),
            url.lastPathComponent
        )
        iconView.image = NSWorkspace.shared.icon(forFile: url.path)
        nameValue.stringValue = url.lastPathComponent
        typeValue.stringValue = placeholder
        locationValue.stringValue = url.deletingLastPathComponent().path
        createdValue.stringValue = placeholder
        modifiedValue.stringValue = placeholder
        sizeValue.stringValue = placeholder

        loadTask = Task { [weak self, loader] in
            do {
                let metadata = try await loader.metadata(for: url)
                try Task.checkCancellation()
                guard let self else { return }
                apply(metadata)
                if metadata.calculatesFolderSize {
                    sizeValue.stringValue = NSLocalizedString(
                        "portal.files.inspector.calculating",
                        comment: "Folder size calculation state"
                    )
                    do {
                        let byteCount = try await loader.folderSize(for: metadata.url)
                        try Task.checkCancellation()
                        sizeValue.stringValue = ByteCountFormatter.string(
                            fromByteCount: byteCount,
                            countStyle: .file
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                        sizeValue.stringValue = unavailable
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                typeValue.stringValue = unavailable
                createdValue.stringValue = unavailable
                modifiedValue.stringValue = unavailable
                sizeValue.stringValue = unavailable
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        loadTask?.cancel()
        loadTask = nil
    }

    private var placeholder: String {
        NSLocalizedString(
            "portal.files.inspector.loading",
            comment: "File inspector loading placeholder"
        )
    }

    private var unavailable: String {
        NSLocalizedString(
            "portal.files.inspector.unavailable",
            comment: "Unavailable file inspector value"
        )
    }

    private func apply(_ metadata: FileInspectorMetadata) {
        nameValue.stringValue = metadata.name
        typeValue.stringValue = metadata.localizedType
        locationValue.stringValue = metadata.url.deletingLastPathComponent().path
        createdValue.stringValue = format(metadata.creationDate)
        modifiedValue.stringValue = format(metadata.modificationDate)
        if let fileSize = metadata.fileSize {
            sizeValue.stringValue = ByteCountFormatter.string(
                fromByteCount: fileSize,
                countStyle: .file
            )
        }
    }

    private func format(_ date: Date?) -> String {
        guard let date else {
            return unavailable
        }
        return DateFormatter.localizedString(
            from: date,
            dateStyle: .medium,
            timeStyle: .medium
        )
    }

    private func makeContentView() -> NSView {
        let contentView = NSView()
        let labels = [
            "portal.files.inspector.name",
            "portal.files.inspector.type",
            "portal.files.inspector.location",
            "portal.files.inspector.created",
            "portal.files.inspector.modified",
            "portal.files.inspector.size",
        ].map {
            let label = NSTextField(labelWithString: NSLocalizedString(
                $0,
                comment: "File inspector field label"
            ))
            label.alignment = .right
            label.textColor = .secondaryLabelColor
            return label
        }
        let values = [nameValue, typeValue, locationValue, createdValue, modifiedValue, sizeValue]
        for (label, value) in zip(labels, values) {
            value.setAccessibilityLabel(label.stringValue)
        }
        let grid = NSGridView(views: zip(labels, values).map { [$0.0, $0.1] })
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)
        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            grid.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
        return contentView
    }
}
