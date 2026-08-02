import Darwin
import Foundation

final class FixtureValidator: @unchecked Sendable {
    private let root: URL
    private let counter: GenerationCounter
    private let enumerator: BackgroundEnumerator
    private let restoreAction: @Sendable (String) throws -> Void
    private let enumerationTimeoutSeconds: Double

    init(
        root: URL,
        counter: GenerationCounter,
        enumerator: BackgroundEnumerator,
        restoreAction: @escaping @Sendable (String) throws -> Void,
        enumerationTimeoutSeconds: Double
    ) {
        self.root = root
        self.counter = counter
        self.enumerator = enumerator
        self.restoreAction = restoreAction
        self.enumerationTimeoutSeconds = enumerationTimeoutSeconds
    }

    func validateAll() throws -> [FixtureResult] {
        [
            try validateAccessibleDirectory(),
            try validateMissingPath(),
            try validateFileAsDirectory(),
            try validatePermissionDenied()
        ]
    }

    private func enumerate(_ url: URL) throws -> EnumerationAttempt {
        let generation = counter.next()
        let attempt = try enumerator.enumerate(
            path: url.path,
            generation: generation,
            timeoutSeconds: enumerationTimeoutSeconds
        )
        try requireCurrent(attempt, currentGeneration: counter.current)
        guard !attempt.executedOnMainThread else {
            throw ProbeError.fixtureMismatch("enumeration ran on the main thread")
        }
        return attempt
    }

    private func validateAccessibleDirectory() throws -> FixtureResult {
        let directory = root.appendingPathComponent("accessible")
        try createDirectory(directory)
        try createFile(directory.appendingPathComponent("one"))
        try createFile(directory.appendingPathComponent("two"))
        let attempt = try enumerate(directory)
        guard attempt.error == nil, attempt.entryCount == 2 else {
            throw ProbeError.fixtureMismatch("accessible directory did not enumerate exactly two entries")
        }
        return FixtureResult(
            name: "accessible-directory",
            expectedCategory: "success",
            entryCount: attempt.entryCount,
            enumerationError: nil,
            posixProbeErrno: nil,
            generation: attempt.generation,
            executedOnMainThread: attempt.executedOnMainThread
        )
    }

    private func validateMissingPath() throws -> FixtureResult {
        let missing = root.appendingPathComponent("missing")
        let posixCode = try failedDirectoryOpenErrno(missing.path)
        guard posixCode == ENOENT else {
            throw ProbeError.fixtureMismatch("missing path open returned errno \(posixCode), expected ENOENT")
        }
        let attempt = try enumerate(missing)
        guard attempt.error?.category == .folderNotFound else {
            throw ProbeError.fixtureMismatch("missing path was not classified as folderNotFound")
        }
        return FixtureResult(
            name: "missing-path",
            expectedCategory: FolderAccessCategory.folderNotFound.rawValue,
            entryCount: nil,
            enumerationError: attempt.error,
            posixProbeErrno: posixCode,
            generation: attempt.generation,
            executedOnMainThread: attempt.executedOnMainThread
        )
    }

    private func validateFileAsDirectory() throws -> FixtureResult {
        let file = root.appendingPathComponent("regular-file")
        try createFile(file)
        let posixCode = try failedDirectoryOpenErrno(file.path)
        guard posixCode == ENOTDIR else {
            throw ProbeError.fixtureMismatch("file-as-directory open returned errno \(posixCode), expected ENOTDIR")
        }
        let attempt = try enumerate(file)
        guard attempt.error?.category == .notDirectory else {
            throw ProbeError.fixtureMismatch("regular file was not classified as notDirectory")
        }
        return FixtureResult(
            name: "file-as-directory",
            expectedCategory: FolderAccessCategory.notDirectory.rawValue,
            entryCount: nil,
            enumerationError: attempt.error,
            posixProbeErrno: posixCode,
            generation: attempt.generation,
            executedOnMainThread: attempt.executedOnMainThread
        )
    }

    private func validatePermissionDenied() throws -> FixtureResult {
        let directory = root.appendingPathComponent("permission-denied")
        try createDirectory(directory)
        try createFile(directory.appendingPathComponent("child"))
        guard chmod(directory.path, 0o000) == 0 else {
            throw ProbeError.filesystem("chmod 000 failed with errno \(errno)")
        }

        let validation: Result<FixtureResult, Error>
        do {
            let posixCode = try failedDirectoryOpenErrno(directory.path)
            guard posixCode == EACCES || posixCode == EPERM else {
                throw ProbeError.fixtureMismatch(
                    "permission fixture open returned errno \(posixCode), expected EACCES or EPERM"
                )
            }
            let attempt = try enumerate(directory)
            guard attempt.error?.category == .permissionDenied else {
                throw ProbeError.fixtureMismatch(
                    "chmod 000 directory did not produce a real permissionDenied enumeration"
                )
            }
            validation = .success(FixtureResult(
                name: "permission-denied",
                expectedCategory: FolderAccessCategory.permissionDenied.rawValue,
                entryCount: nil,
                enumerationError: attempt.error,
                posixProbeErrno: posixCode,
                generation: attempt.generation,
                executedOnMainThread: attempt.executedOnMainThread
            ))
        } catch {
            validation = .failure(error)
        }

        let restoration: Result<Void, Error>
        do {
            try restoreAction(directory.path)
            restoration = .success(())
        } catch {
            restoration = .failure(error)
        }

        switch (validation, restoration) {
        case (.success(let result), .success): return result
        case (.failure(let error), .success): throw error
        case (.success, .failure(let error)): throw error
        case (.failure(let primary), .failure(let secondary)):
            throw ProbeError.combined(
                primary: String(describing: primary),
                secondary: String(describing: secondary)
            )
        }
    }
}

func runOwnedFixtureTransaction(
    root: URL,
    counter: GenerationCounter,
    enumerator: BackgroundEnumerator,
    restoreAction: @escaping @Sendable (String) throws -> Void = restoreDirectoryPermissions,
    enumerationTimeoutSeconds: Double = 5,
    convergenceTimeoutSeconds: Double = 2,
    cleanupAction: @Sendable (URL) throws -> Void = removeOwnedRoot
) throws -> [FixtureResult] {
    try createDirectory(root)
    let execution: Result<[FixtureResult], Error>
    do {
        execution = .success(try FixtureValidator(
            root: root,
            counter: counter,
            enumerator: enumerator,
            restoreAction: restoreAction,
            enumerationTimeoutSeconds: enumerationTimeoutSeconds
        ).validateAll())
    } catch {
        execution = .failure(error)
    }

    guard enumerator.waitUntilIdle(timeoutSeconds: convergenceTimeoutSeconds) else {
        let convergence = ProbeError.backgroundTimeout(
            "fixture worker did not converge; owned root was intentionally left for outer-process cleanup"
        )
        switch execution {
        case .success: throw convergence
        case .failure(let primary):
            throw ProbeError.combined(
                primary: String(describing: primary),
                secondary: String(describing: convergence)
            )
        }
    }

    let cleanupResult: Result<Void, Error>
    do {
        try cleanupAction(root)
        cleanupResult = .success(())
    } catch {
        cleanupResult = .failure(error)
    }

    return try resolveTransaction(execution: execution, cleanup: cleanupResult)
}

func resolveTransaction<Value>(
    execution: Result<Value, Error>,
    cleanup: Result<Void, Error>
) throws -> Value {
    switch (execution, cleanup) {
    case (.success(let results), .success): return results
    case (.failure(let error), .success): throw error
    case (.success, .failure(let error)): throw error
    case (.failure(let primary), .failure(let secondary)):
        throw ProbeError.combined(
            primary: String(describing: primary),
            secondary: String(describing: secondary)
        )
    }
}

func restoreDirectoryPermissions(_ path: String) throws {
    guard chmod(path, 0o700) == 0 else {
        throw ProbeError.restoration("chmod 700 failed for owned fixture with errno \(errno)")
    }
}

func removeOwnedRoot(_ root: URL) throws {
    do { try FileManager.default.removeItem(at: root) }
    catch { throw ProbeError.cleanup("remove owned root failed: \(error)") }
}

private func createDirectory(_ url: URL) throws {
    do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
    catch { throw ProbeError.filesystem("create directory failed: \(error)") }
}

private func createFile(_ url: URL) throws {
    let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
        throw ProbeError.filesystem("create file failed with errno \(errno)")
    }
    guard Darwin.close(descriptor) == 0 else {
        throw ProbeError.filesystem("close file failed with errno \(errno)")
    }
}

private func failedDirectoryOpenErrno(_ path: String) throws -> Int32 {
    let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    if descriptor >= 0 {
        let closeResult = Darwin.close(descriptor)
        if closeResult != 0 {
            throw ProbeError.filesystem("unexpected directory open also failed to close with errno \(errno)")
        }
        throw ProbeError.fixtureMismatch("expected directory open to fail")
    }
    return errno
}
