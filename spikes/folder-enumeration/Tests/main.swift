// Tests/main.swift — Phase 0.5C1 background directory enumeration tests
// Transactional temporary directories, explicit timeouts, real filesystem evidence.

import Dispatch
import Foundation

private enum HarnessError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}

/// Thread-safe boolean flag for cross-queue signaling.
private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    func get() -> Bool {
        lock.withLock { value }
    }

    func set(_ newValue: Bool) {
        lock.withLock { value = newValue }
    }
}

/// Thread-safe optional box for cross-queue result passing.
private final class LockedOptional<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    init() {}

    func get() -> Value? {
        lock.withLock { value }
    }

    func set(_ newValue: Value?) {
        lock.withLock { value = newValue }
    }
}

@MainActor
private final class TestHarness {
    private var passed = 0
    private var failed = 0
    private var failures: [String] = []

    func run() -> Int32 {
        runTest("empty and populated enumeration with deterministic ordering", testBasicEnumeration)
        runTest("no recursive grandchildren in the result", testNoGrandchildren)
        runTest("missing path and regular-file errors", testPathErrors)
        runTest("enumeration runs off main thread on configured worker queue", testWorkerQueueBoundary)
        runTest("worker timeout is bounded and does not cancel the call", testWorkerTimeout)
        runTest("stale generation N rejected after N+1 accepted", testStaleResultRejection)
        runTest("cancellation before worker execution suppresses acceptance", testCancellationBeforeCall)
        runTest("cancellation during blocking call does not interrupt; result rejected after", testCancellationDuringCall)
        runTest("later successful request works after stale and cancelled requests", testRecoveryAfterStaleAndCancelled)
        runTest("fixture cleanup errors are propagated", testFixtureCleanup)

        failures.forEach { print($0) }
        print("Assertions passed: \(passed)")
        print("Assertions failed: \(failed)")
        return failed == 0 ? 0 : 1
    }

    private func runTest(_ name: String, _ body: () throws -> Void) {
        print("[TEST] \(name)")
        do {
            try body()
        } catch {
            failed += 1
            failures.append("FAIL: \(name) threw: \(error)")
        }
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            failures.append("FAIL: \(message)")
        }
    }

    // MARK: - Test 1: Empty and populated enumeration

    private func testBasicEnumeration() throws {
        try withTemporaryDirectory(prefix: "alcove-enum-empty") { directory in
            let enumerator = DirectoryEnumerator.defaultManager()
            let snapshot = try enumerateOffMain(
                path: directory.path,
                generation: 1,
                enumerator: enumerator
            )
            expect(snapshot.count == 0, "empty directory should have zero entries")
            expect(snapshot.isEmpty, "empty directory isEmpty should be true")
            expect(snapshot.generation == 1, "snapshot should carry its generation")
            expect(snapshot.path == directory.path, "snapshot should carry the enumerated path")
            expect(snapshot.metadataErrors.isEmpty, "empty directory should have no metadata errors")
        }

        try withTemporaryDirectory(prefix: "alcove-enum-populated") { directory in
            // Create a mix of files and directories with names that test sorting.
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("Zulu"),
                withIntermediateDirectories: false
            )
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("Alpha"),
                withIntermediateDirectories: false
            )
            try createFile(at: directory.appendingPathComponent("mike.txt"))
            try createFile(at: directory.appendingPathComponent("alpha.txt"))
            try createFile(at: directory.appendingPathComponent("hidden-file"))

            let enumerator = DirectoryEnumerator.defaultManager()
            let snapshot = try enumerateOffMain(
                path: directory.path,
                generation: 42,
                enumerator: enumerator
            )
            expect(snapshot.count == 5, "populated directory should list all immediate children")
            expect(!snapshot.isEmpty, "populated directory isEmpty should be false")
            expect(snapshot.generation == 42, "snapshot should carry its generation")

            // Verify directories come first.
            expect(snapshot.entries[0].isDirectory, "first entry should be a directory (Alpha)")
            expect(snapshot.entries[1].isDirectory, "second entry should be a directory (Zulu)")

            // Verify directories use deterministic lexical ordering.
            expect(snapshot.entries[0].name == "Alpha",
                   "directories should be lexically sorted: got \(snapshot.entries[0].name)")
            expect(snapshot.entries[1].name == "Zulu",
                   "directories should be lexically sorted: got \(snapshot.entries[1].name)")

            // Verify files come after directories and are sorted.
            expect(!snapshot.entries[2].isDirectory, "third entry should be a file")
            expect(!snapshot.entries[3].isDirectory, "fourth entry should be a file")
            expect(!snapshot.entries[4].isDirectory, "fifth entry should be a file")

            // Files use locale-independent lexical ordering.
            let fileNames = snapshot.entries[2...].map(\.name)
            expect(fileNames == ["alpha.txt", "hidden-file", "mike.txt"],
                   "files should use deterministic lexical ordering: \(fileNames)")

            // Verify isDirectory and isHidden evidence.
            expect(snapshot.entries[0].name == "Alpha" && snapshot.entries[0].isDirectory,
                   "Alpha should be a directory")
            expect(!snapshot.entries[0].isHidden, "Alpha should not be hidden")
        }
    }

    // MARK: - Test 2: No recursive grandchildren

    private func testNoGrandchildren() throws {
        try withTemporaryDirectory(prefix: "alcove-no-grandchildren") { directory in
            // Create a subdirectory with its own children (grandchildren).
            let subDir = directory.appendingPathComponent("subdir")
            try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: false)
            try createFile(at: subDir.appendingPathComponent("grandchild1.txt"))
            try createFile(at: subDir.appendingPathComponent("grandchild2.txt"))
            try createFile(at: directory.appendingPathComponent("direct-child.txt"))

            let enumerator = DirectoryEnumerator.defaultManager()
            let snapshot = try enumerateOffMain(
                path: directory.path,
                generation: 1,
                enumerator: enumerator
            )

            expect(snapshot.count == 2, "should list only 2 immediate children, got \(snapshot.count)")

            // Verify no grandchildren appear.
            let names = Set(snapshot.entries.map(\.name))
            expect(!names.contains("grandchild1.txt"), "grandchild1 should not appear")
            expect(!names.contains("grandchild2.txt"), "grandchild2 should not appear")
            expect(names.contains("subdir"), "subdir should appear")
            expect(names.contains("direct-child.txt"), "direct-child should appear")

            // Verify every entry is an immediate child.
            let parentName = directory.lastPathComponent
            for entry in snapshot.entries {
                let entryParentName = entry.url.deletingLastPathComponent().lastPathComponent
                expect(entryParentName == parentName,
                       "\(entry.name) should be an immediate child of \(parentName), got parent \(entryParentName)")
            }
        }
    }

    // MARK: - Test 3: Missing path and regular-file errors

    private func testPathErrors() throws {
        let worker = WorkerQueue(label: "com.alcove.spike.test.errors")
        let coordinator = Coordinator()
        let runner = EnumerationRequestRunner(
            worker: worker,
            enumerator: DirectoryEnumerator.defaultManager()
        )
        let missingPath = NSTemporaryDirectory() + "alcove-missing-\(UUID().uuidString)"
        let missingGeneration = try coordinator.submit()
        do {
            _ = try runner.run(
                path: missingPath,
                generation: missingGeneration,
                token: CancellationToken()
            )
            expect(false, "missing path should throw")
        } catch let error as EnumerationError {
            guard case .missingPath(let path, let code) = error else {
                expect(false, "missing path should map to missingPath, got \(error)")
                return
            }
            expect(path == missingPath, "missingPath should retain the failing path")
            expect(code == ENOENT, "missingPath should retain ENOENT, got \(code)")
        }

        // Regular file.
        try withTemporaryDirectory(prefix: "alcove-not-dir") { directory in
            let file = directory.appendingPathComponent("regular-file")
            try createFile(at: file)
            let generation = try coordinator.submit()
            do {
                _ = try runner.run(
                    path: file.path,
                    generation: generation,
                    token: CancellationToken()
                )
                expect(false, "regular file should throw")
            } catch let error as EnumerationError {
                guard case .notADirectory(let path, _) = error else {
                    expect(false, "regular file should map to notADirectory, got \(error)")
                    return
                }
                expect(path == file.path, "notADirectory should retain the path")
            }

            let injected = DirectoryEnumerator { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
            }
            let injectedRunner = EnumerationRequestRunner(worker: worker, enumerator: injected)
            do {
                _ = try injectedRunner.run(
                    path: directory.path,
                    generation: try coordinator.submit(),
                    token: CancellationToken()
                )
                expect(false, "enumeration failure should throw")
            } catch let error as EnumerationError {
                guard case .enumerationFailed(let path, let domain, let code, _) = error else {
                    expect(false, "enumeration failure should retain its typed mapping")
                    return
                }
                expect(path == directory.path, "enumeration failure should retain its path")
                expect(domain == NSCocoaErrorDomain, "enumeration failure should retain its domain")
                expect(code == NSFileReadNoPermissionError, "enumeration failure should retain its code")
            }
        }

        expect(coordinator.currentSnapshot == nil,
               "real failed requests should not publish a snapshot")

        let exhausted = Coordinator(initialGeneration: UInt64.max)
        do {
            _ = try exhausted.submit()
            expect(false, "exhausted generation should throw")
        } catch let error as EnumerationError {
            expect(error == .generationExhausted, "generation overflow should be typed")
        }
    }

    // MARK: - Test 4: Worker queue boundary

    private func testWorkerQueueBoundary() throws {
        try withTemporaryDirectory(prefix: "alcove-worker-boundary") { directory in
            try createFile(at: directory.appendingPathComponent("child.txt"))

            let worker = WorkerQueue(label: "com.alcove.spike.test.worker-boundary")
            let enumerator = DirectoryEnumerator.defaultManager()

            // Verify the closure runs on the worker queue, not the main thread.
            let result = try worker.execute { () -> (Bool, Bool, UInt64) in
                let isMainThread = Thread.isMainThread
                let isWorkerQueue = worker.isCurrentQueue
                let snapshot = try DirectorySnapshot.enumerate(
                    path: directory.path,
                    generation: 1,
                    enumerator: enumerator
                )
                return (isMainThread, isWorkerQueue, UInt64(snapshot.count))
            }

            expect(result.0 == false, "enumeration must NOT run on the main thread")
            expect(result.1 == true, "enumeration must run on the configured worker queue")
            expect(result.2 == 1, "enumeration should find 1 child")
        }
    }

    private func testWorkerTimeout() throws {
        let worker = WorkerQueue(label: "com.alcove.spike.test.timeout")
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        do {
            _ = try worker.execute(timeout: .now() + .milliseconds(100)) {
                entered.signal()
                _ = release.wait(timeout: .now() + 3)
                finished.signal()
                return UInt8(1)
            }
            expect(false, "blocked worker should time out")
        } catch let error as EnumerationError {
            expect(error == .workerTimedOut, "blocked worker should return workerTimedOut")
        }
        expect(entered.wait(timeout: .now()) == .success,
               "timed-out work should have entered its synchronous call")
        release.signal()
        expect(finished.wait(timeout: .now() + 3) == .success,
               "timed-out work should still finish after its call is released")
    }

    // MARK: - Test 5: Stale generation N rejected after N+1 accepted

    private func testStaleResultRejection() throws {
        try withTemporaryDirectory(prefix: "alcove-stale") { directory in
            // Set up two subdirectories: "fast" (N+1) and "slow" (N).
            let fastDir = directory.appendingPathComponent("fast")
            let slowDir = directory.appendingPathComponent("slow")
            try FileManager.default.createDirectory(at: fastDir, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: slowDir, withIntermediateDirectories: false)
            try createFile(at: fastDir.appendingPathComponent("fast-child"))
            try createFile(at: slowDir.appendingPathComponent("slow-child"))

            let worker = WorkerQueue(label: "com.alcove.spike.test.stale")
            let coordinator = Coordinator()
            let enumerator = DirectoryEnumerator.defaultManager()

            // Block N while the concurrent worker remains able to run N+1.
            let blockWorker = DispatchSemaphore(value: 0)
            let workerBlocked = DispatchSemaphore(value: 0)

            // Submit N (slow).
            let genN = try coordinator.submit()
            let tokenN = CancellationToken()

            // Submit N+1 (fast).
            let genN1 = try coordinator.submit()
            let tokenN1 = CancellationToken()

            // Start N on the worker. It will block on the semaphore.
            let nFinished = DispatchSemaphore(value: 0)
            let nError = LockedOptional<Error>()
            let nResult = LockedOptional<DirectorySnapshot>()
            DispatchQueue.global().async {
                do {
                    let snapshot = try worker.execute { () -> DirectorySnapshot in
                        workerBlocked.signal()
                        _ = blockWorker.wait(timeout: .now() + 10)
                        return try DirectorySnapshot.enumerate(
                            path: slowDir.path,
                            generation: genN,
                            enumerator: enumerator
                        )
                    }
                    nResult.set(snapshot)
                } catch {
                    nError.set(error)
                }
                nFinished.signal()
            }

            // Wait for the worker to be blocked.
            expect(workerBlocked.wait(timeout: .now() + 3) == .success,
                   "worker should be blocked by N's request")
            var nJoined = false
            defer {
                if !nJoined {
                    blockWorker.signal()
                    _ = nFinished.wait(timeout: .now() + 5)
                }
            }

            // The concurrent worker must allow N+1 to finish before N.
            let n1Snapshot = try worker.execute {
                try DirectorySnapshot.enumerate(
                    path: fastDir.path,
                    generation: genN1,
                    enumerator: enumerator
                )
            }
            let n1Accepted = coordinator.accept(snapshot: n1Snapshot, token: tokenN1)
            expect(n1Accepted, "N+1 should be accepted (current generation)")
            expect(coordinator.currentSnapshot?.entries.first?.name == "fast-child",
                   "N+1 accepted state should contain fast-child")

            // Unblock N. It finishes after N+1.
            blockWorker.signal()
            expect(nFinished.wait(timeout: .now() + 5) == .success,
                   "N should finish after being unblocked")
            nJoined = true
            expect(nError.get() == nil, "N should finish without an execution error")

            guard let nSnapshot = nResult.get() else {
                throw HarnessError.message("N did not retain its actual worker result")
            }
            let nAccepted = coordinator.accept(snapshot: nSnapshot, token: tokenN)
            expect(!nAccepted, "N's result should be rejected as stale")
            expect(coordinator.currentSnapshot?.entries.first?.name == "fast-child",
                   "coordinator state should still be N+1 (fast-child)")

            // Verify generation ordering.
            expect(genN1 > genN, "N+1 generation should be greater than N")
        }
    }

    // MARK: - Test 6: Cancellation before worker execution

    private func testCancellationBeforeCall() throws {
        try withTemporaryDirectory(prefix: "alcove-cancel-before") { directory in
            try createFile(at: directory.appendingPathComponent("child.txt"))

            let worker = WorkerQueue(label: "com.alcove.spike.test.cancel-before")
            let coordinator = Coordinator()
            let enumerationRan = LockedBool(false)
            let enumerator = DirectoryEnumerator { _ in
                enumerationRan.set(true)
                return []
            }
            let runner = EnumerationRequestRunner(worker: worker, enumerator: enumerator)
            let generation = try coordinator.submit()
            let token = CancellationToken()
            token.markCancelled()
            do {
                _ = try runner.run(path: directory.path, generation: generation, token: token)
                expect(false, "pre-cancelled request should throw")
            } catch let error as EnumerationError {
                expect(error == .cancelled, "pre-cancelled request should return cancelled")
            }
            expect(!enumerationRan.get(), "pre-cancelled request should skip enumeration")
            expect(token.isCancelled, "token should be cancelled before the call")
            expect(coordinator.currentSnapshot == nil,
                   "cancelled result should not be published to the coordinator")
        }
    }

    // MARK: - Test 7: Cancellation during blocking call

    private func testCancellationDuringCall() throws {
        try withTemporaryDirectory(prefix: "alcove-cancel-during") { directory in
            try createFile(at: directory.appendingPathComponent("child.txt"))

            let worker = WorkerQueue(label: "com.alcove.spike.test.cancel-during")
            let coordinator = Coordinator()
            let callEntered = DispatchSemaphore(value: 0)
            let releaseCall = DispatchSemaphore(value: 0)
            let slowEnumerator = DirectoryEnumerator { url in
                callEntered.signal()
                _ = releaseCall.wait(timeout: .now() + 3)
                return try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .isHiddenKey],
                    options: [.skipsSubdirectoryDescendants]
                )
            }

            let generation = try coordinator.submit()
            let token = CancellationToken()
            let runner = EnumerationRequestRunner(worker: worker, enumerator: slowEnumerator)

            // Start the slow enumeration.
            let enumerationDone = DispatchSemaphore(value: 0)
            let resultSnapshot = LockedOptional<DirectorySnapshot>()
            let resultError = LockedOptional<Error>()

            DispatchQueue.global().async {
                do {
                    let snap = try runner.run(
                        path: directory.path,
                        generation: generation,
                        token: token
                    )
                    resultSnapshot.set(snap)
                } catch {
                    resultError.set(error)
                }
                enumerationDone.signal()
            }

            expect(callEntered.wait(timeout: .now() + 3) == .success,
                   "blocking enumeration should start before cancellation")
            token.markCancelled()
            expect(token.isCancelled, "token should be cancelled mid-call")
            expect(enumerationDone.wait(timeout: .now() + .milliseconds(100)) == .timedOut,
                   "cancellation must not pretend to interrupt the synchronous call")
            releaseCall.signal()

            // Wait for the call to complete.
            expect(enumerationDone.wait(timeout: .now() + 5) == .success,
                   "slow enumeration should complete within timeout")

            // The filesystem call completed, but the runner rejects its result.
            let snapshot = resultSnapshot.get()
            let enumerationError = resultError.get()
            expect(snapshot == nil, "post-call cancellation should suppress the snapshot")
            if let error = enumerationError as? EnumerationError {
                expect(error == .cancelled, "post-call cancellation should return cancelled")
            } else {
                expect(false, "post-call cancellation should retain its typed error")
            }
            expect(coordinator.currentSnapshot == nil,
                   "cancelled result should not be published")
        }
    }

    // MARK: - Test 8: Recovery after stale and cancelled

    private func testRecoveryAfterStaleAndCancelled() throws {
        try withTemporaryDirectory(prefix: "alcove-recovery") { directory in
            try createFile(at: directory.appendingPathComponent("recovery-child"))

            let worker = WorkerQueue(label: "com.alcove.spike.test.recovery")
            let coordinator = Coordinator()
            let enumerator = DirectoryEnumerator.defaultManager()

            // First: create a stale situation by accepting a newer generation.
            let oldGen = try coordinator.submit()
            let newGen = try coordinator.submit()
            let newToken = CancellationToken()

            let runner = EnumerationRequestRunner(worker: worker, enumerator: enumerator)
            let newSnapshot = try runner.run(
                path: directory.path,
                generation: newGen,
                token: newToken
            )
            expect(coordinator.accept(snapshot: newSnapshot, token: newToken),
                   "new generation should be accepted")

            // Try to accept the old generation (stale).
            let oldToken = CancellationToken()
            let oldSnapshot = try runner.run(
                path: directory.path,
                generation: oldGen,
                token: oldToken
            )
            expect(!coordinator.accept(snapshot: oldSnapshot, token: oldToken),
                   "old generation should be rejected as stale")

            // Second: create a cancelled situation.
            let cancelGen = try coordinator.submit()
            let cancelToken = CancellationToken()
            cancelToken.markCancelled()

            do {
                _ = try runner.run(
                    path: directory.path,
                    generation: cancelGen,
                    token: cancelToken
                )
                expect(false, "cancelled recovery request should throw")
            } catch let error as EnumerationError {
                expect(error == .cancelled, "cancelled recovery request should be typed")
            }

            // Third: a later successful request should still work.
            let recoveryGen = try coordinator.submit()
            let recoveryToken = CancellationToken()

            let recoverySnapshot = try runner.run(
                path: directory.path,
                generation: recoveryGen,
                token: recoveryToken
            )
            expect(coordinator.accept(snapshot: recoverySnapshot, token: recoveryToken),
                   "recovery request should be accepted after stale and cancelled")
            expect(coordinator.currentSnapshot?.entries.first?.name == "recovery-child",
                   "recovery state should contain the expected entry")
        }
    }

    // MARK: - Test 9: Fixture cleanup errors

    private func testFixtureCleanup() throws {
        // Verify normal cleanup succeeds.
        var fixturePath = ""
        try withTemporaryDirectory(prefix: "alcove-cleanup") { directory in
            fixturePath = directory.path
            try createFile(at: directory.appendingPathComponent("fixture"))
            expect(FileManager.default.fileExists(atPath: fixturePath),
                   "fixture should exist inside its transaction")
        }
        expect(!FileManager.default.fileExists(atPath: fixturePath),
               "successful fixture transaction should remove its directory")

        // Inject a cleanup failure after removing the fixture, so the failure is
        // propagated without leaving test data behind.
        var cleanupErrorCaught = false
        do {
            try withTemporaryDirectory(
                prefix: "alcove-cleanup-error",
                removeDirectory: { directory in
                    try FileManager.default.removeItem(at: directory)
                    throw HarnessError.message("injected cleanup failure")
                }
            ) { _ in
            }
        } catch {
            cleanupErrorCaught = true
            expect(String(describing: error).contains("injected cleanup failure"),
                   "cleanup error should be propagated: \(error)")
        }
        expect(cleanupErrorCaught, "fixture cleanup error should be caught")
    }

    // MARK: - Helpers

    private func enumerateOffMain(
        path: String,
        generation: UInt64,
        enumerator: DirectoryEnumerator
    ) throws -> DirectorySnapshot {
        let worker = WorkerQueue(label: "com.alcove.spike.test.enumerate")
        let runner = EnumerationRequestRunner(worker: worker, enumerator: enumerator)
        return try runner.run(
            path: path,
            generation: generation,
            token: CancellationToken()
        )
    }

    private func withTemporaryDirectory(
        prefix: String,
        removeDirectory: (URL) throws -> Void = { directory in
            try FileManager.default.removeItem(at: directory)
        },
        body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)

        do {
            try body(directory)
        } catch {
            let bodyError = error
            do {
                try removeDirectory(directory)
            } catch {
                throw HarnessError.message(
                    "test failed (\(bodyError)); fixture cleanup also failed: \(error)"
                )
            }
            throw bodyError
        }
        try removeDirectory(directory)
    }

    private func createFile(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw HarnessError.message("createFile failed for \(url.path): errno \(errno)")
        }
        guard Darwin.close(descriptor) == 0 else {
            throw HarnessError.message("close failed for \(url.path): errno \(errno)")
        }
    }
}

let exitCode = MainActor.assumeIsolated {
    TestHarness().run()
}
exit(exitCode)
