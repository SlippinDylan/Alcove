import Foundation

struct FileCompressionPlan: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let sourceURL: URL
        let isDirectory: Bool
    }

    let entries: [Entry]
    let destinationURL: URL

    static func make(
        sourceURLs: [URL],
        archiveBaseName: String,
        fileManager: FileManager = .default
    ) throws -> FileCompressionPlan {
        guard let firstURL = sourceURLs.first else {
            throw FileOperationError.compressionNoSources
        }
        let sources = sourceURLs.map(\.standardizedFileURL)
        let destinationDirectory = firstURL.standardizedFileURL.deletingLastPathComponent()
        guard sources.allSatisfy({ $0.deletingLastPathComponent() == destinationDirectory }) else {
            throw FileOperationError.compressionSourcesNotColocated
        }

        let entries = try sources.map { source -> Entry in
            let values = try source.resourceValues(forKeys: [.isDirectoryKey])
            return Entry(sourceURL: source, isDirectory: values.isDirectory == true)
        }
        let baseName = entries.count == 1
            ? entries[0].sourceURL.lastPathComponent
            : archiveBaseName
        let destination = uniqueArchiveURL(
            in: destinationDirectory,
            baseName: baseName,
            fileManager: fileManager
        )
        return FileCompressionPlan(entries: entries, destinationURL: destination)
    }

    private static func uniqueArchiveURL(
        in directory: URL,
        baseName: String,
        fileManager: FileManager
    ) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).zip")
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).zip")
            counter += 1
        }
        return candidate
    }
}

protocol FileCompressing: Sendable {
    func compress(_ sourceURLs: [URL]) async throws -> URL
}

actor DittoFileCompressionService: FileCompressing {
    private let fileManager: FileManager
    private let executableURL: URL

    init(
        fileManager: FileManager = .default,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/ditto")
    ) {
        self.fileManager = fileManager
        self.executableURL = executableURL
    }

    func compress(_ sourceURLs: [URL]) async throws -> URL {
        let plan = try FileCompressionPlan.make(
            sourceURLs: sourceURLs,
            archiveBaseName: NSLocalizedString(
                "portal.files.archive_base_name",
                comment: "Default multi-item archive filename"
            ),
            fileManager: fileManager
        )
        let scratchDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Alcove-Compression-\(UUID().uuidString)", isDirectory: true)
        let temporaryArchive = scratchDirectory.appendingPathComponent("result.zip")
        try fileManager.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: false
        )
        defer { try? fileManager.removeItem(at: scratchDirectory) }

        if plan.entries.count == 1, let entry = plan.entries.first {
            var arguments = ["-c", "-k", "--sequesterRsrc"]
            if entry.isDirectory {
                arguments.append("--keepParent")
            }
            arguments.append(contentsOf: [entry.sourceURL.path, temporaryArchive.path])
            try await runDitto(arguments: arguments)
        } else {
            let payload = scratchDirectory.appendingPathComponent("Payload", isDirectory: true)
            try fileManager.createDirectory(at: payload, withIntermediateDirectories: false)
            for entry in plan.entries {
                try Task.checkCancellation()
                let stagedURL = payload.appendingPathComponent(entry.sourceURL.lastPathComponent)
                try await runDitto(arguments: [entry.sourceURL.path, stagedURL.path])
            }
            try await runDitto(arguments: [
                "-c", "-k", "--sequesterRsrc", payload.path, temporaryArchive.path,
            ])
        }

        try Task.checkCancellation()
        try fileManager.moveItem(at: temporaryArchive, to: plan.destinationURL)
        return plan.destinationURL
    }

    private func runDitto(arguments: [String]) async throws {
        try Task.checkCancellation()
        let process = CancellableProcess(
            executableURL: executableURL,
            arguments: arguments
        )

        let terminationStatus: Int32 = try await withTaskCancellationHandler {
            try await process.run()
        } onCancel: {
            Task { await process.cancel() }
        }
        try Task.checkCancellation()
        guard terminationStatus == 0 else {
            throw FileOperationError.compressionFailed(terminationStatus)
        }
    }
}

private actor CancellableProcess {
    private let process: Process
    private var isCancelled = false

    init(executableURL: URL, arguments: [String]) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        self.process = process
    }

    func run() async throws -> Int32 {
        if isCancelled {
            throw CancellationError()
        }
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { completedProcess in
                continuation.resume(returning: completedProcess.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func cancel() {
        isCancelled = true
        if process.isRunning {
            process.terminate()
        }
    }
}
