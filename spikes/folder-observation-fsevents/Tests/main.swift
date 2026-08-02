// Structural and real-filesystem tests for Alcove Spike 0.5B FSEvents observer.

import CoreServices
import Darwin
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

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var records: [FSEventRecord] = []

    func append(_ record: FSEventRecord) {
        lock.withLock { records.append(record) }
        semaphore.signal()
    }

    var count: Int {
        lock.withLock { records.count }
    }

    var snapshot: [FSEventRecord] {
        lock.withLock { records }
    }

    /// Waits until at least `target` records have been delivered or timeout.
    func waitForCount(_ target: Int, timeout: DispatchTime) -> Bool {
        while count < target {
            guard semaphore.wait(timeout: timeout) == .success else { return false }
        }
        return true
    }

}

private final class ObserverReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var observer: FSEventsFolderObserver?

    func set(_ observer: FSEventsFolderObserver) {
        lock.withLock { self.observer = observer }
    }

    func stopObserver() {
        let value = lock.withLock { observer }
        value?.stop()
    }
}

@MainActor
private final class TestHarness {
    private var passed = 0
    private var failed = 0
    private var failures: [String] = []

    func run() -> Int32 {
        runTest("open errors and path validation", testOpenErrors)
        runTest("deterministic lifecycle", testLifecycle)
        runTest("child create delivery", testChildCreate)
        runTest("child rename delivery", testChildRename)
        runTest("child delete delivery", testChildDelete)
        runTest("monotonic first-event latency", testLatency)
        runTest("root rename with WatchRoot", testRootRename)
        runTest("root delete with WatchRoot", testRootDelete)
        runTest("directory replacement follows pathname", testDirectoryReplacement)
        runTest("rapid operations and coalescing", testCoalescing)
        runTest("callback-initiated stop does not deadlock", testCallbackStop)
        runTest("teardown wait and repeated stop", testTeardownWait)
        runTest("post-teardown event suppression", testPostTeardown)
        runTest("callback context lifetime", testContextLifetime)
        runTest("deinit releases callback context", testDeinitTeardown)
        runTest("transactional fixture cleanup", testFixtureCleanup)

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

    // MARK: - Test: open errors

    private func testOpenErrors() throws {
        // Missing path retains POSIX evidence.
        let missingPath = NSTemporaryDirectory() + "alcove-fse-missing-\(UUID().uuidString)"
        let missingObserver = FSEventsFolderObserver { _ in }
        do {
            try missingObserver.start(path: missingPath)
            expect(false, "missing path should fail to start")
        } catch let error as FSEventError {
            guard case .pathNotFound(let path, let code) = error else {
                expect(false, "missing path should map to pathNotFound, got \(error)")
                return
            }
            expect(path == missingPath, "pathNotFound should retain the failing path")
            expect(code == ENOENT, "missing path should retain ENOENT")
        }
        expect(missingObserver.lifecycleState == .idle, "failed start should leave the observer idle")

        // Regular file is rejected.
        try withTemporaryDirectory(prefix: "alcove-fse-not-directory") { directory in
            let file = directory.appendingPathComponent("regular-file")
            try createFile(at: file)
            let fileObserver = FSEventsFolderObserver { _ in }
            do {
                try fileObserver.start(path: file.path)
                expect(false, "regular file should be rejected")
            } catch let error as FSEventError {
                guard case .notADirectory(let path) = error else {
                    expect(false, "regular file should map to notADirectory, got \(error)")
                    return
                }
                expect(path == file.path, "notADirectory should retain the path")
            }
            expect(fileObserver.lifecycleState == .idle, "rejected file should leave observer idle")
        }
    }

    // MARK: - Test: lifecycle

    private func testLifecycle() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-lifecycle") { directory in
            let observer = FSEventsFolderObserver { _ in }

            // Wait before start should fail.
            do {
                try observer.waitUntilStopped(timeout: .now() + 1)
                expect(false, "wait before stop should be rejected")
            } catch let error as FSEventError {
                expect(error == .teardownNotRequested, "wait before stop should return teardownNotRequested")
            }

            // Start succeeds.
            try observer.start(path: directory.path)
            expect(observer.lifecycleState == .running, "start should commit running state")
            expect(observer.currentGeneration == 1, "first registration should use generation one")
            expect(observer.currentRegistrationIdentity != nil, "start should set registration identity")

            // Duplicate start fails.
            do {
                try observer.start(path: directory.path)
                expect(false, "duplicate start should fail")
            } catch let error as FSEventError {
                expect(error == .alreadyRunning, "duplicate start should return alreadyRunning")
            }

            // Stop schedules teardown; bounded wait proves completion.
            observer.stop()
            expect(observer.lifecycleState == .stopping || observer.lifecycleState == .stopped,
                   "stop should invalidate running state immediately")
            try observer.waitUntilStopped(timeout: .now() + 3)
            expect(observer.lifecycleState == .stopped, "teardown wait should reach stopped state")

            // Repeated stop is safe.
            observer.stop()
            expect(observer.lifecycleState == .stopped, "repeated stop should remain stopped")

            // Restart after terminal stop fails.
            do {
                try observer.start(path: directory.path)
                expect(false, "terminal observer should reject restart")
            } catch let error as FSEventError {
                expect(error == .stopped, "restart should return stopped")
            }
        }
    }

    // MARK: - Test: child create

    private func testChildCreate() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-child-create") { directory in
            let recorder = EventRecorder()
            let observer = FSEventsFolderObserver(onEvent: recorder.append)
            try observer.start(path: directory.path)

            // Drain any initial events from stream setup.
            let baseline = drainInitialEvents(recorder: recorder, timeout: .now() + 1)

            try createFile(at: directory.appendingPathComponent("created"))

            expect(recorder.waitForCount(baseline + 1, timeout: .now() + 5),
                   "child create should deliver at least one new record")

            let newRecords = Array(recorder.snapshot.dropFirst(baseline))
            let createRecords = newRecords.filter { $0.path.contains("created") }
            expect(!createRecords.isEmpty, "new record should reference the created file path")

            expect(createRecords.contains(where: { $0.decodedFlags.contains("ItemCreated") }),
                   "created path should carry ItemCreated")
            expect(createRecords.contains(where: { $0.decodedFlags.contains("ItemIsFile") }),
                   "created path should carry ItemIsFile")

            print("  new create records: \(newRecords.map(\.flagDescription))")
            _ = try observer.stopAndWait(timeout: .now() + 3)
            expect(observer.bridgeFailureCount == 0,
                   "child create callbacks should bridge every delivered path")
        }
    }

    // MARK: - Test: child rename

    private func testChildRename() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-child-rename") { directory in
            try createFile(at: directory.appendingPathComponent("original"))

            let recorder = EventRecorder()
            let observer = FSEventsFolderObserver(onEvent: recorder.append)
            try observer.start(path: directory.path)

            // Drain initial events. Then wait a bit more to let the
            // initial file creation event settle.
            _ = drainInitialEvents(recorder: recorder, timeout: .now() + 1)
            usleep(200_000)
            let baseline = recorder.count

            try FileManager.default.moveItem(
                at: directory.appendingPathComponent("original"),
                to: directory.appendingPathComponent("renamed")
            )

            expect(recorder.waitForCount(baseline + 1, timeout: .now() + 5),
                   "child rename should deliver at least one new record")

            let newRecords = Array(recorder.snapshot.dropFirst(baseline))
            let renamedRecords = newRecords.filter { $0.decodedFlags.contains("ItemRenamed") }
            expect(renamedRecords.contains(where: { $0.path.hasSuffix("/original") }),
                   "rename should report the original path")
            expect(renamedRecords.contains(where: { $0.path.hasSuffix("/renamed") }),
                   "rename should report the renamed path")

            print("  new rename records: \(newRecords.map(\.flagDescription))")
            print("  new rename paths: \(newRecords.map(\.path))")
            _ = try observer.stopAndWait(timeout: .now() + 3)
            expect(observer.bridgeFailureCount == 0,
                   "child rename callbacks should bridge every delivered path")
        }
    }

    // MARK: - Test: child delete

    private func testChildDelete() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-child-delete") { directory in
            try createFile(at: directory.appendingPathComponent("deleted"))

            let recorder = EventRecorder()
            let observer = FSEventsFolderObserver(onEvent: recorder.append)
            try observer.start(path: directory.path)

            // Drain initial events and wait for the file-creation event to settle.
            _ = drainInitialEvents(recorder: recorder, timeout: .now() + 1)
            usleep(200_000)
            let baseline = recorder.count

            try FileManager.default.removeItem(at: directory.appendingPathComponent("deleted"))

            expect(recorder.waitForCount(baseline + 1, timeout: .now() + 5),
                   "child delete should deliver at least one new record")

            let newRecords = Array(recorder.snapshot.dropFirst(baseline))
            let removedRecords = newRecords.filter { $0.path.hasSuffix("/deleted") }
            expect(removedRecords.contains(where: { $0.decodedFlags.contains("ItemRemoved") }),
                   "deleted path should carry ItemRemoved")
            expect(removedRecords.contains(where: { $0.decodedFlags.contains("ItemIsFile") }),
                   "deleted path should retain ItemIsFile evidence")

            print("  new delete records: \(newRecords.map(\.flagDescription))")
            _ = try observer.stopAndWait(timeout: .now() + 3)
            expect(observer.bridgeFailureCount == 0,
                   "child delete callbacks should bridge every delivered path")
        }
    }

    // MARK: - Test: latency

    private func testLatency() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-latency") { directory in
            let recorder = EventRecorder()
            let observer = FSEventsFolderObserver(onEvent: recorder.append)
            try observer.start(path: directory.path)

            // Drain initial events from stream setup.
            let baseline = drainInitialEvents(recorder: recorder, timeout: .now() + 1)

            let mutationStart = FSEventsFolderObserver.monotonicNow()
            try createFile(at: directory.appendingPathComponent("latency-marker"))

            expect(recorder.waitForCount(baseline + 1, timeout: .now() + 5),
                   "latency mutation should deliver a new event")
            guard let first = recorder.snapshot.dropFirst(baseline).first else {
                expect(false, "latency test should retain its first new event")
                _ = try observer.stopAndWait(timeout: .now() + 3)
                return
            }
            let latency = first.timestamp - mutationStart
            print("  observed first-event latency: \(String(format: "%.6f", latency)) seconds")
            expect(latency >= 0, "monotonic event time should not precede mutation start")
            expect(latency < 5, "observed latency should remain inside test timeout")
            _ = try observer.stopAndWait(timeout: .now() + 3)
            expect(observer.bridgeFailureCount == 0,
                   "latency callbacks should bridge every delivered path")
        }
    }

    // MARK: - Test: root rename

    private func testRootRename() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-root-rename") { root in
            let observed = root.appendingPathComponent("observed")
            try FileManager.default.createDirectory(at: observed, withIntermediateDirectories: false)

            let recorder = EventRecorder()
            let observer = FSEventsFolderObserver(onEvent: recorder.append)
            try observer.start(path: observed.path)

            usleep(100_000)

            let renamed = root.appendingPathComponent("renamed-root")
            try FileManager.default.moveItem(at: observed, to: renamed)

            expect(recorder.waitForCount(1, timeout: .now() + 5),
                   "root rename should deliver at least one record")

            let records = recorder.snapshot
            let hasRootChanged = records.contains {
                $0.path.hasSuffix("/observed") && $0.decodedFlags.contains("RootChanged")
            }
            expect(hasRootChanged, "root rename should carry RootChanged flag with WatchRoot")

            let hasRenamed = records.contains { $0.decodedFlags.contains("ItemRenamed") }
            print("  root-rename flags: \(records.map(\.flagDescription))")
            print("  root-rename paths: \(records.map(\.path))")
            print("  has RootChanged: \(hasRootChanged), has ItemRenamed: \(hasRenamed)")

            _ = try observer.stopAndWait(timeout: .now() + 3)
            expect(observer.bridgeFailureCount == 0,
                   "root rename callbacks should bridge every delivered path")
            // The renamed directory is inside the root fixture and will be
            // cleaned up by withTemporaryDirectory.
        }
    }

    // MARK: - Test: root delete

    private func testRootDelete() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-root-delete") { root in
            let observed = root.appendingPathComponent("observed")
            try FileManager.default.createDirectory(at: observed, withIntermediateDirectories: false)

            let recorder = EventRecorder()
            let observer = FSEventsFolderObserver(onEvent: recorder.append)
            try observer.start(path: observed.path)

            usleep(100_000)

            try FileManager.default.removeItem(at: observed)

            expect(recorder.waitForCount(1, timeout: .now() + 5),
                   "root delete should deliver at least one record")

            let records = recorder.snapshot
            let hasRootChanged = records.contains { $0.decodedFlags.contains("RootChanged") }
            let hasRemoved = records.contains { $0.decodedFlags.contains("ItemRemoved") }
            print("  root-delete flags: \(records.map(\.flagDescription))")
            print("  has RootChanged: \(hasRootChanged), has ItemRemoved: \(hasRemoved)")
            // Root delete may carry RootChanged, ItemRemoved, or both depending on timing.
            expect(hasRootChanged || hasRemoved,
                   "root delete should carry RootChanged or ItemRemoved flag")

            _ = try observer.stopAndWait(timeout: .now() + 3)
            expect(observer.bridgeFailureCount == 0,
                   "root delete callbacks should bridge every delivered path")
        }
    }

    // MARK: - Test: directory replacement

    private func testDirectoryReplacement() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-replacement") { root in
            let observed = root.appendingPathComponent("mapped")
            try FileManager.default.createDirectory(at: observed, withIntermediateDirectories: false)

            let originalIdentity = try fileIdentity(at: observed)

            let recorder = EventRecorder()
            let observer = FSEventsFolderObserver(onEvent: recorder.append)
            try observer.start(path: observed.path)

            usleep(100_000)

            // Move the original aside, then create a replacement at the same
            // path so both the old inode and replacement remain mutable.
            let displaced = root.appendingPathComponent("displaced")
            try FileManager.default.moveItem(at: observed, to: displaced)
            expect(waitForRecord(recorder: recorder, timeout: .now() + 5) {
                $0.path.hasSuffix("/mapped") && $0.decodedFlags.contains("RootChanged")
            }, "moving the observed root should produce RootChanged before replacement")
            let replacementBaseline = recorder.count

            try FileManager.default.createDirectory(at: observed, withIntermediateDirectories: false)

            let displacedIdentity = try fileIdentity(at: displaced)
            let replacementIdentity = try fileIdentity(at: observed)
            expect(displacedIdentity == originalIdentity,
                   "the displaced original should retain its inode identity")
            expect(replacementIdentity != originalIdentity,
                   "replacement path should resolve to a different inode")

            let displacedChild = displaced.appendingPathComponent("displaced-child")
            let replacementChild = observed.appendingPathComponent("replacement-child")
            try createFile(at: displacedChild)
            try createFile(at: replacementChild)
            expect(waitForRecord(recorder: recorder, timeout: .now() + 5) {
                $0.path.hasSuffix("/replacement-child")
                    && $0.decodedFlags.contains("ItemCreated")
            }, "stream should deliver a child event from the replacement pathname")
            usleep(500_000)

            let records = Array(recorder.snapshot.dropFirst(replacementBaseline))
            print("  replacement records: \(records.count)")
            print("  replacement flags: \(records.map(\.flagDescription))")
            print("  replacement paths: \(records.map(\.path))")

            expect(records.contains(where: { $0.path.hasSuffix("/replacement-child") }),
                   "post-move records should include the unique replacement child")
            expect(!records.contains(where: { $0.path.hasSuffix("/displaced-child") }),
                   "stream should not deliver mutation from the displaced original inode")
            _ = try observer.stopAndWait(timeout: .now() + 3)
            expect(observer.bridgeFailureCount == 0,
                   "replacement callbacks should bridge every delivered path")
        }
    }

    // MARK: - Test: coalescing

    private func testCoalescing() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-coalesce") { directory in
            let recorder = EventRecorder()
            let observer = FSEventsFolderObserver(onEvent: recorder.append)
            try observer.start(path: directory.path)
            let baseline = drainInitialEvents(recorder: recorder, timeout: .now() + 1)

            let operationCount = 20
            for index in 0..<operationCount {
                try createFile(at: directory.appendingPathComponent("rapid-\(index)"))
            }

            expect(waitForRecord(recorder: recorder, timeout: .now() + 5) {
                $0.path.contains("/rapid-")
            }, "rapid operations should produce at least one matching child record")
            usleep(500_000)

            let records = Array(recorder.snapshot.dropFirst(baseline)).filter {
                $0.path.contains("/rapid-")
            }
            let uniquePaths = Set(records.map(\.path))
            let callbackBatches = Set(records.map(\.callbackBatchIdentity))
            print("  operations: \(operationCount), records: \(records.count), callback batches: \(callbackBatches.count)")
            expect(uniquePaths.count == operationCount,
                   "FileEvents should report all 20 unique rapid child paths in this local run")
            expect(!callbackBatches.isEmpty, "matching records should retain callback batch identity")

            _ = try observer.stopAndWait(timeout: .now() + 3)
            expect(observer.bridgeFailureCount == 0,
                   "rapid-operation callbacks should bridge every delivered path")
        }
    }

    // MARK: - Test: callback-initiated stop

    private func testCallbackStop() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-callback-stop") { directory in
            let recorder = EventRecorder()
            let reference = ObserverReference()
            let callbackReturned = DispatchSemaphore(value: 0)

            let observer = FSEventsFolderObserver { record in
                recorder.append(record)
                reference.stopObserver()
                callbackReturned.signal()
            }
            reference.set(observer)
            try observer.start(path: directory.path)

            usleep(100_000)

            try createFile(at: directory.appendingPathComponent("trigger"))

            expect(callbackReturned.wait(timeout: .now() + 5) == .success,
                   "event callback should return after initiating stop without deadlock")
            try observer.waitUntilStopped(timeout: .now() + 3)
            expect(observer.lifecycleState == .stopped,
                   "callback-initiated stop should complete through external wait")

            let countAfterStop = recorder.count

            try createFile(at: directory.appendingPathComponent("after-callback-stop"))
            usleep(400_000)
            expect(recorder.count == countAfterStop,
                   "new mutations should not deliver after callback-initiated teardown")
            expect(observer.bridgeFailureCount == 0,
                   "callback-stop delivery should not hide bridge failures")
        }
    }

    private func testTeardownWait() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-teardown-wait") { directory in
            let callbackEntered = DispatchSemaphore(value: 0)
            let releaseCallback = DispatchSemaphore(value: 0)
            let observer = FSEventsFolderObserver { _ in
                callbackEntered.signal()
                _ = releaseCallback.wait(timeout: .now() + 3)
            }
            try observer.start(path: directory.path)
            try createFile(at: directory.appendingPathComponent("trigger"))
            expect(callbackEntered.wait(timeout: .now() + 5) == .success,
                   "blocking callback should begin before teardown")

            observer.stop()
            observer.stop()
            expect(observer.lifecycleState == .stopping,
                   "repeated stop should share the in-progress teardown")
            do {
                try observer.waitUntilStopped(timeout: .now() + .milliseconds(100))
                expect(false, "wait should time out while the lifecycle callback is blocked")
            } catch let error as FSEventError {
                expect(error == .teardownTimedOut, "blocked teardown should return teardownTimedOut")
            }

            releaseCallback.signal()
            try observer.waitUntilStopped(timeout: .now() + 3)
            expect(observer.lifecycleState == .stopped,
                   "all waiters should observe stopped only after resource teardown")
        }
    }

    // MARK: - Test: post-teardown suppression

    private func testPostTeardown() throws {
        try withTemporaryDirectory(prefix: "alcove-fse-post-teardown") { directory in
            let recorder = EventRecorder()
            let observer = FSEventsFolderObserver(onEvent: recorder.append)
            try observer.start(path: directory.path)

            usleep(100_000)

            // Produce one event to confirm the observer is live.
            try createFile(at: directory.appendingPathComponent("before-stop"))
            expect(recorder.waitForCount(1, timeout: .now() + 5),
                   "pre-stop event should be delivered")
            let countBeforeStop = recorder.count

            _ = try observer.stopAndWait(timeout: .now() + 3)
            expect(observer.lifecycleState == .stopped, "stopAndWait should complete teardown")

            // Mutate after teardown.
            try createFile(at: directory.appendingPathComponent("after-stop"))
            usleep(400_000)

            expect(recorder.count == countBeforeStop,
                   "mutations after completed teardown should not reach user callback")
            expect(observer.bridgeFailureCount == 0,
                   "post-teardown fixture should not hide bridge failures")
        }
    }

    // MARK: - Test: ownership counter

    private func testContextLifetime() throws {
        CallbackContext.lifetimeCounter.reset()

        try withTemporaryDirectory(prefix: "alcove-fse-ownership") { directory in
            let observer = FSEventsFolderObserver { _ in }
            try observer.start(path: directory.path)

            let afterStart = CallbackContext.lifetimeCounter.snapshot()
            expect(afterStart.created == 1, "start should create one callback context")
            expect(afterStart.destroyed == 0, "running stream should keep its callback context alive")

            _ = try observer.stopAndWait(timeout: .now() + 3)

            let afterStop = CallbackContext.lifetimeCounter.snapshot()
            expect(afterStop.created == 1, "teardown should not create another context")
            expect(afterStop.destroyed == 1, "completed teardown should destroy the one context")
        }
    }

    // MARK: - Test: deinit teardown

    private func testDeinitTeardown() throws {
        CallbackContext.lifetimeCounter.reset()

        try withTemporaryDirectory(prefix: "alcove-fse-deinit") { directory in
            var observer: FSEventsFolderObserver? = FSEventsFolderObserver { _ in }
            try observer?.start(path: directory.path)

            let afterStart = CallbackContext.lifetimeCounter.snapshot()
            expect(afterStart.created == 1 && afterStart.destroyed == 0,
                   "deinit test should begin with one live context")

            observer = nil

            // After deinit, the context should be released.
            let deadline = FSEventsFolderObserver.monotonicNow() + 3
            var released = false
            while FSEventsFolderObserver.monotonicNow() < deadline {
                let snapshot = CallbackContext.lifetimeCounter.snapshot()
                if snapshot.destroyed >= 1 {
                    released = true
                    break
                }
                usleep(1_000)
            }
            expect(released, "deinit should release callback context within the timeout")

            let final = CallbackContext.lifetimeCounter.snapshot()
            expect(final.created == final.destroyed,
                   "context creation/destruction should balance after deinit teardown")
        }
    }

    // MARK: - Test: fixture cleanup

    private func testFixtureCleanup() throws {
        var fixturePath = ""
        try withTemporaryDirectory(prefix: "alcove-fse-cleanup") { directory in
            fixturePath = directory.path
            try createFile(at: directory.appendingPathComponent("fixture"))
            expect(FileManager.default.fileExists(atPath: fixturePath),
                   "fixture should exist inside its transaction")
        }
        expect(!FileManager.default.fileExists(atPath: fixturePath),
               "successful fixture transaction should remove its directory")
    }

    // MARK: - Helpers

    /// Waits briefly for any initial events from stream setup, then returns
    /// the baseline event count. This prevents initial setup events from
    /// being misidentified as mutation events in child-mutation tests.
    private func drainInitialEvents(recorder: EventRecorder, timeout: DispatchTime) -> Int {
        // Wait up to the timeout for any initial events to arrive.
        let deadline = timeout
        while DispatchTime.now() < deadline {
            usleep(50_000)
        }
        return recorder.count
    }

    private func withTemporaryDirectory(
        prefix: String,
        body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)

        do {
            try body(directory)
        } catch {
            let bodyDescription = String(describing: error)
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                throw HarnessError.message(
                    "test failed (\(bodyDescription)); fixture cleanup also failed: \(error)"
                )
            }
            throw HarnessError.message(bodyDescription)
        }
        try FileManager.default.removeItem(at: directory)
    }

    private func waitForRecord(
        recorder: EventRecorder,
        timeout: DispatchTime,
        matching predicate: (FSEventRecord) -> Bool
    ) -> Bool {
        while !recorder.snapshot.contains(where: predicate) {
            let nextCount = recorder.count + 1
            guard recorder.waitForCount(nextCount, timeout: timeout) else { return false }
        }
        return true
    }

    private func createFile(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw HarnessError.message("open create failed for \(url.path): errno \(errno)")
        }
        guard Darwin.close(descriptor) == 0 else {
            throw HarnessError.message("close created file failed for \(url.path): errno \(errno)")
        }
    }

    private func fileIdentity(at url: URL) throws -> (dev: UInt64, ino: UInt64) {
        var metadata = stat()
        guard Darwin.lstat(url.path, &metadata) == 0 else {
            throw HarnessError.message("lstat failed for \(url.path): errno \(errno)")
        }
        return (dev: UInt64(metadata.st_dev), ino: UInt64(metadata.st_ino))
    }
}

let exitCode = MainActor.assumeIsolated {
    TestHarness().run()
}
exit(exitCode)
