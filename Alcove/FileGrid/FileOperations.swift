import AppKit
import Foundation

enum FileTransferOperation: Equatable, Sendable {
    case automatic
    case copy
    case move

    func resolved(
        sourceVolumeURL: URL,
        destinationVolumeURL: URL
    ) -> FileTransferOperation {
        guard self == .automatic else { return self }
        return sourceVolumeURL.standardizedFileURL
            == destinationVolumeURL.standardizedFileURL ? .move : .copy
    }
}

enum FileOperationError: LocalizedError, Equatable, Sendable {
    case sourceAlreadyInDestination(URL)
    case destinationAlreadyExists(URL)
    case directoryIntoDescendant(URL)
    case invalidDestinationDirectory(URL)
    case volumeUnavailable(URL)
    case duplicateDestinationName(String)
    case operationFailed(completedCount: Int, totalCount: Int)

    var errorDescription: String? {
        switch self {
        case .sourceAlreadyInDestination:
            return NSLocalizedString(
                "portal.files.same_destination",
                comment: "File transfer source is already in the destination"
            )
        case .destinationAlreadyExists:
            return NSLocalizedString(
                "portal.files.name_conflict",
                comment: "File transfer destination name conflict"
            )
        case .directoryIntoDescendant:
            return NSLocalizedString(
                "portal.files.descendant_destination",
                comment: "A directory cannot be moved into its own descendant"
            )
        case .invalidDestinationDirectory:
            return NSLocalizedString(
                "portal.files.invalid_destination_directory",
                comment: "File transfer destination is no longer an ordinary directory"
            )
        case .volumeUnavailable:
            return NSLocalizedString(
                "portal.files.volume_unavailable",
                comment: "File transfer volume identity is unavailable"
            )
        case .duplicateDestinationName:
            return NSLocalizedString(
                "portal.files.duplicate_names",
                comment: "Multiple transfer sources have the same name"
            )
        case .operationFailed(let completedCount, let totalCount):
            let format = NSLocalizedString(
                "portal.files.partial_failure",
                comment: "File transfer partial failure detail"
            )
            return String(format: format, completedCount, totalCount)
        }
    }
}

struct FileTransferPlan: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let sourceURL: URL
        let destinationURL: URL
    }

    let destinationDirectoryURL: URL
    let entries: [Entry]

    static func make(
        sourceURLs: [URL],
        destinationDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> FileTransferPlan {
        let destination = destinationDirectoryURL.standardizedFileURL
        let destinationValues = try destination.resourceValues(forKeys: [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .volumeSupportsCaseSensitiveNamesKey,
        ])
        guard destinationValues.isDirectory == true,
              destinationValues.isPackage != true,
              destinationValues.isSymbolicLink != true else {
            throw FileOperationError.invalidDestinationDirectory(destination)
        }
        let supportsCaseSensitiveNames = destinationValues.volumeSupportsCaseSensitiveNames
            ?? false
        var names = Set<String>()
        var entries: [Entry] = []

        for rawSource in sourceURLs {
            let source = rawSource.standardizedFileURL
            guard source.deletingLastPathComponent() != destination else {
                throw FileOperationError.sourceAlreadyInDestination(source)
            }
            let destinationNameKey = destinationNameKey(
                source.lastPathComponent,
                caseSensitive: supportsCaseSensitiveNames
            )
            guard names.insert(destinationNameKey).inserted else {
                throw FileOperationError.duplicateDestinationName(source.lastPathComponent)
            }

            let target = destination.appendingPathComponent(source.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else {
                throw FileOperationError.destinationAlreadyExists(target)
            }

            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               destination.resolvingSymlinksInPath().isSameAsOrDescendant(
                    of: source.resolvingSymlinksInPath()
               ) {
                throw FileOperationError.directoryIntoDescendant(source)
            }

            entries.append(Entry(sourceURL: source, destinationURL: target))
        }

        return FileTransferPlan(
            destinationDirectoryURL: destination,
            entries: entries
        )
    }

    static func destinationNameKey(_ name: String, caseSensitive: Bool) -> String {
        let normalizedName = name.precomposedStringWithCanonicalMapping
        return caseSensitive
            ? normalizedName
            : normalizedName.folding(options: [.caseInsensitive], locale: nil)
    }
}

private extension URL {
    func isSameAsOrDescendant(of ancestor: URL) -> Bool {
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        let candidateComponents = standardizedFileURL.pathComponents
        return candidateComponents.starts(with: ancestorComponents)
    }
}

protocol FileTransferPerforming: Sendable {
    func transfer(
        sourceURLs: [URL],
        to destinationDirectoryURL: URL,
        operation: FileTransferOperation
    ) async throws
}

actor CoordinatedFileTransferService: FileTransferPerforming {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func transfer(
        sourceURLs: [URL],
        to destinationDirectoryURL: URL,
        operation: FileTransferOperation
    ) async throws {
        let plan = try FileTransferPlan.make(
            sourceURLs: sourceURLs,
            destinationDirectoryURL: destinationDirectoryURL,
            fileManager: fileManager
        )
        let resolvedTransfers = try plan.entries.map { entry in
            (
                entry: entry,
                operation: try resolve(
                    operation,
                    sourceURL: entry.sourceURL,
                    destinationDirectoryURL: plan.destinationDirectoryURL
                )
            )
        }

        var completedCount = 0
        do {
            for transfer in resolvedTransfers {
                try coordinate(
                    entry: transfer.entry,
                    destinationDirectoryURL: plan.destinationDirectoryURL,
                    operation: transfer.operation
                )
                completedCount += 1
            }
        } catch {
            throw FileOperationError.operationFailed(
                completedCount: completedCount,
                totalCount: resolvedTransfers.count
            )
        }
    }

    private func resolve(
        _ operation: FileTransferOperation,
        sourceURL: URL,
        destinationDirectoryURL: URL
    ) throws -> FileTransferOperation {
        guard operation == .automatic else { return operation }
        let sourceVolume = try sourceURL.resourceValues(forKeys: [.volumeURLKey]).volume
        let destinationVolume = try destinationDirectoryURL.resourceValues(
            forKeys: [.volumeURLKey]
        ).volume
        guard let sourceVolume, let destinationVolume else {
            throw FileOperationError.volumeUnavailable(sourceURL)
        }
        return operation.resolved(
            sourceVolumeURL: sourceVolume,
            destinationVolumeURL: destinationVolume
        )
    }

    private func coordinate(
        entry: FileTransferPlan.Entry,
        destinationDirectoryURL: URL,
        operation: FileTransferOperation
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?

        switch operation {
        case .automatic:
            preconditionFailure("Automatic transfer operation must be resolved before IO")
        case .copy:
            coordinator.coordinate(
                readingItemAt: entry.sourceURL,
                options: .withoutChanges,
                writingItemAt: destinationDirectoryURL,
                options: .forMerging,
                error: &coordinationError
            ) { coordinatedSource, coordinatedDestination in
                do {
                    try fileManager.copyItem(
                        at: coordinatedSource,
                        to: coordinatedDestination.appendingPathComponent(entry.destinationURL.lastPathComponent)
                    )
                } catch {
                    operationError = error
                }
            }
        case .move:
            coordinator.coordinate(
                writingItemAt: entry.sourceURL,
                options: .forMoving,
                writingItemAt: destinationDirectoryURL,
                options: .forMerging,
                error: &coordinationError
            ) { coordinatedSource, coordinatedDestination in
                do {
                    try fileManager.moveItem(
                        at: coordinatedSource,
                        to: coordinatedDestination.appendingPathComponent(entry.destinationURL.lastPathComponent)
                    )
                } catch {
                    operationError = error
                }
            }
        }

        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }
}

@MainActor
protocol FileRecycling: AnyObject {
    func recycle(
        _ urls: [URL],
        completion: @escaping @MainActor @Sendable (Error?) -> Void
    )
}

@MainActor
final class SystemFileRecycler: FileRecycling {
    func recycle(
        _ urls: [URL],
        completion: @escaping @MainActor @Sendable (Error?) -> Void
    ) {
        NSWorkspace.shared.recycle(urls) { _, error in
            Task { @MainActor in completion(error) }
        }
    }
}

@MainActor
protocol FileOperationFailurePresenting: AnyObject {
    func present(_ error: Error)
}

@MainActor
final class FileOperationFailurePresenter: FileOperationFailurePresenting {
    func present(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(
            "portal.files.operation_failed",
            comment: "File operation failure title"
        )
        alert.runModal()
    }
}
