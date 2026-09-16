import AlcoveCore
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol ApplicationLayoutBackupControlling: AnyObject {
    func beginImport(from window: NSWindow)
    func beginExport(from window: NSWindow)
}

@MainActor
final class DisabledApplicationLayoutBackupController: ApplicationLayoutBackupControlling {
    func beginImport(from window: NSWindow) {}
    func beginExport(from window: NSWindow) {}
}

protocol ApplicationLayoutBackupFileAccessing: Sendable {
    func readBackup(at url: URL, homeDirectory: URL) async throws -> AlcoveLayoutBackup
    func write(_ data: Data, to url: URL) async throws
}

actor FoundationApplicationLayoutBackupFileAccess: ApplicationLayoutBackupFileAccessing {
    func readBackup(at url: URL, homeDirectory: URL) throws -> AlcoveLayoutBackup {
        let data = try Data(contentsOf: url)
        return try AlcoveLayoutBackupCodec.decode(data, homeDirectory: homeDirectory)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
final class ApplicationLayoutBackupController: ApplicationLayoutBackupControlling {
    typealias SnapshotProvider = @MainActor () -> ([Portal], PortalAppearancePreferences)
    typealias ReplaceHandler = @MainActor (AlcoveLayoutBackup) async throws -> Void
    typealias ImportCompletion = @MainActor (PortalAppearancePreferences) -> Void

    private let fileAccess: any ApplicationLayoutBackupFileAccessing
    private let homeDirectory: URL
    private let snapshotProvider: SnapshotProvider
    private let replaceHandler: ReplaceHandler
    private let importCompletion: ImportCompletion

    init(
        fileAccess: any ApplicationLayoutBackupFileAccessing = FoundationApplicationLayoutBackupFileAccess(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        snapshotProvider: @escaping SnapshotProvider,
        replaceHandler: @escaping ReplaceHandler,
        importCompletion: @escaping ImportCompletion
    ) {
        self.fileAccess = fileAccess
        self.homeDirectory = homeDirectory
        self.snapshotProvider = snapshotProvider
        self.replaceHandler = replaceHandler
        self.importCompletion = importCompletion
    }

    func beginExport(from window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Alcove Layout.json"
        panel.prompt = NSLocalizedString(
            "application.settings.backup.export",
            comment: "Export layout button"
        )

        Task { @MainActor [weak self, weak window] in
            guard let self, let window else { return }
            let response = await panel.beginSheetModal(for: window)
            guard response == .OK, let url = panel.url else { return }
            panel.orderOut(nil)
            do {
                let snapshot = snapshotProvider()
                let data = try AlcoveLayoutBackupCodec.encode(
                    portals: snapshot.0,
                    appearance: snapshot.1,
                    homeDirectory: homeDirectory
                )
                try await fileAccess.write(data, to: url)
            } catch {
                presentError(
                    titleKey: "application.settings.backup.export_error",
                    error: error,
                    on: window
                )
            }
        }
    }

    func beginImport(from window: NSWindow) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = NSLocalizedString(
            "application.settings.backup.import",
            comment: "Import layout button"
        )

        Task { @MainActor [weak self, weak window] in
            guard let self, let window else { return }
            let response = await panel.beginSheetModal(for: window)
            guard response == .OK, let url = panel.url else { return }
            panel.orderOut(nil)
            do {
                let backup = try await fileAccess.readBackup(
                    at: url,
                    homeDirectory: homeDirectory
                )
                guard await confirmReplacement(of: backup.portals.count, on: window) else {
                    return
                }
                try await replaceHandler(backup)
                let appearance = PortalAppearancePreferences(
                    iconSize: backup.global.iconSize,
                    backgroundStyle: backup.global.backgroundStyle,
                    cornerRadius: backup.global.cornerRadius,
                    spacing: backup.global.spacing,
                    shadowEnabled: backup.global.shadowEnabled
                )
                importCompletion(appearance)
            } catch {
                presentError(
                    titleKey: "application.settings.backup.import_error",
                    error: error,
                    on: window
                )
            }
        }
    }

    private func confirmReplacement(of portalCount: Int, on window: NSWindow) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(
            "application.settings.backup.replace_title",
            comment: "Replace layout confirmation title"
        )
        alert.informativeText = String(
            format: NSLocalizedString(
                "application.settings.backup.replace_message",
                comment: "Replace layout confirmation message"
            ),
            portalCount
        )
        alert.addButton(withTitle: NSLocalizedString(
            "application.settings.backup.replace",
            comment: "Replace layout confirmation button"
        ))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    private func presentError(titleKey: String, error: Error, on window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(titleKey, comment: "Layout backup error title")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        alert.beginSheetModal(for: window)
    }
}
