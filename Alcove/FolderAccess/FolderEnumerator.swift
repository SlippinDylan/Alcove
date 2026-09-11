import AlcoveCore
import Dispatch
import Foundation
import Synchronization

protocol FolderEnumerating: Sendable {
    func enumerate(
        root: URL,
        showHidden: Bool,
        generation: UInt64
    ) async throws -> FolderEnumerationResult
}

struct FolderEnumerator: FolderEnumerating, Sendable {
    private let queue: DispatchQueue
    private let executionObserver: @Sendable (Bool) -> Void
    private let enumerationProgressObserver: @Sendable (Int) -> Void

    init(
        queue: DispatchQueue = DispatchQueue(
            label: "com.dylanwang.alcove.folder-enumeration",
            qos: .userInitiated,
            attributes: .concurrent
        ),
        executionObserver: @escaping @Sendable (Bool) -> Void = { _ in },
        enumerationProgressObserver: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.queue = queue
        self.executionObserver = executionObserver
        self.enumerationProgressObserver = enumerationProgressObserver
    }

    func enumerate(
        root: URL,
        showHidden: Bool = false,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        let cancellation = FolderEnumerationCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<FolderEnumerationResult, Error>) in
                queue.async {
                    executionObserver(Thread.isMainThread)
                    do {
                        continuation.resume(
                            returning: try Self.enumerateSynchronously(
                                root: root,
                                showHidden: showHidden,
                                generation: generation,
                                cancellation: cancellation,
                                progressObserver: enumerationProgressObserver
                            )
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func enumerateSynchronously(
        root: URL,
        showHidden: Bool,
        generation: UInt64,
        cancellation: FolderEnumerationCancellation,
        progressObserver: @Sendable (Int) -> Void
    ) throws -> FolderEnumerationResult {
        try cancellation.check()
        let root = root.standardizedFileURL
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let childURLs: [URL]
        do {
            childURLs = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .isHiddenKey],
                options: options
            )
        } catch let error as NSError {
            throw FolderAccessError.classifyRootError(url: root, error: error)
        }
        try cancellation.check()

        var items: [FileItem] = []
        var diagnostics: [FolderItemDiagnostic] = []
        for (index, childURL) in childURLs.enumerated() {
            try cancellation.check()
            do {
                items.append(try makeFileItem(url: childURL))
            } catch let error as NSError {
                diagnostics.append(
                    FolderItemDiagnostic(
                        url: childURL,
                        metadata: FolderErrorMetadata(error: error)
                    )
                )
            }
            progressObserver(index + 1)
        }
        try cancellation.check()
        items.sort(by: Self.sortItems)
        return FolderEnumerationResult(
            root: root,
            generation: generation,
            items: items,
            itemDiagnostics: diagnostics
        )
    }

    private static func makeFileItem(url: URL) throws -> FileItem {
        let standardizedURL = url.standardizedFileURL
        let values = try standardizedURL.resourceValues(
            forKeys: [.nameKey, .isDirectoryKey, .isHiddenKey]
        )
        guard let name = values.name,
              let isDirectory = values.isDirectory,
              let isHidden = values.isHidden else {
            throw FolderItemMetadataError.incomplete(url: standardizedURL)
        }
        return FileItem(
            url: standardizedURL,
            name: name,
            isDirectory: isDirectory,
            isHidden: isHidden
        )
    }

    private static func sortItems(_ left: FileItem, _ right: FileItem) -> Bool {
        if left.isDirectory != right.isDirectory {
            return left.isDirectory
        }
        let comparison = left.name.localizedStandardCompare(right.name)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return left.url.path < right.url.path
    }
}

private final class FolderEnumerationCancellation: Sendable {
    private let cancelled = Mutex(false)

    func cancel() {
        cancelled.withLock { $0 = true }
    }

    func check() throws {
        if cancelled.withLock({ $0 }) {
            throw CancellationError()
        }
    }
}

private enum FolderItemMetadataError: Error {
    case incomplete(url: URL)
}
