import AppKit
import Foundation

enum FileTransferOperation: Sendable {
    case copy
    case move
}

enum FileOperationError: LocalizedError, Equatable, Sendable {
    case sourceAlreadyInDestination(URL)
    case destinationAlreadyExists(URL)
    case directoryIntoDescendant(URL)
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
        let supportsCaseSensitiveNames = try destination.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames ?? false
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
               destination.resolvingSymlinksInPath().isDescendant(of: source.resolvingSymlinksInPath()) {
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
    func isDescendant(of ancestor: URL) -> Bool {
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        let candidateComponents = standardizedFileURL.pathComponents
        return candidateComponents.count > ancestorComponents.count
            && candidateComponents.starts(with: ancestorComponents)
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

        var completedCount = 0
        do {
            for entry in plan.entries {
                try coordinate(
                    entry: entry,
                    destinationDirectoryURL: plan.destinationDirectoryURL,
                    operation: operation
                )
                completedCount += 1
            }
        } catch {
            throw FileOperationError.operationFailed(
                completedCount: completedCount,
                totalCount: plan.entries.count
            )
        }
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
