// Structural and real-filesystem tests for Alcove Spike 0.5A.

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

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var records: [FolderObservationRecord] = []

    func append(_ record: FolderObservationRecord) {
        lock.withLock { records.append(record) }
        semaphore.signal()
    }

    var count: Int {
        lock.withLock { records.count }
    }

    var snapshot: [FolderObservationRecord] {
        lock.withLock { records }
    }

    func waitForCount(_ target: Int, timeout: DispatchTime) -> Bool {
        while count < target {
            guard semaphore.wait(timeout: timeout) == .success else { return false }
        }
        return true
    }
}

private final class ObserverReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var observer: DispatchSourceFolderObserver?

    func set(_ observer: DispatchSourceFolderObserver) {
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
        runTest("open errors and descriptor validation", testOpenErrors)
        runTest("deterministic lifecycle", testLifecycle)
        runTest("child create, rename, and delete delivery", testChildMutations)
        runTest("monotonic first-event latency", testLatency)
        runTest("observed-directory rename and delete", testDirectoryLifecycle)
        runTest("directory replacement remains on original inode", testDirectoryReplacement)
        runTest("callback-initiated stop and late-event suppression", testStopSemantics)
        runTest("external stop waits for an active callback", testExternalStopWaitsForCallback)
        runTest("descriptor close completion", testDescriptorClosure)
        runTest("deinit initiates descriptor teardown", testDeinitTeardown)
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

    private func testOpenErrors() throws {
        let missingPath = NSTemporaryDirectory() + "alcove-missing-\(UUID().uuidString)"
        let missingObserver = DispatchSourceFolderObserver { _ in }
        do {
            try missingObserver.start(path: missingPath)
            expect(false, "missing path should fail to open")
        } catch let error as FolderObserverError {
            guard case .openFailed(let path, let code) = error else {
                expect(false, "missing path should map to openFailed, got \(error)")
                return
            }
            expect(path == missingPath, "open error should retain the failing path")
            expect(code == ENOENT, "missing path should retain ENOENT")
        }
        expect(missingObserver.openedFileDescriptor == -1, "failed open should not own a descriptor")
        expect(missingObserver.lifecycleState == .idle, "failed open should leave the observer idle")

        try withTemporaryDirectory(prefix: "alcove-not-directory") { directory in
            let file = directory.appendingPathComponent("regular-file")
            try createFile(at: file)
            let fileObserver = DispatchSourceFolderObserver { _ in }
            do {
                try fileObserver.start(path: file.path)
                expect(false, "regular file should be rejected")
            } catch let error as FolderObserverError {
                guard case .notADirectory(let path) = error else {
                    expect(false, "regular file should map to notADirectory, got \(error)")
                    return
                }
                expect(path == file.path, "not-directory error should retain the path")
            }
            expect(fileObserver.openedFileDescriptor == -1, "rejected file descriptor should be closed")
        }
    }

    private func testLifecycle() throws {
        try withTemporaryDirectory(prefix: "alcove-lifecycle") { directory in
            let observer = DispatchSourceFolderObserver { _ in }
            do {
                _ = try observer.waitUntilStopped(timeout: .now() + 1)
                expect(false, "wait before stop should be rejected")
            } catch let error as FolderObserverError {
                expect(error == .teardownNotRequested, "wait before stop should return teardownNotRequested")
            }

            try observer.start(path: directory.path)
            expect(observer.lifecycleState == .running, "start should commit running state before returning")
            expect(observer.currentGeneration == 1, "first registration should use generation one")
            do {
                try observer.start(path: directory.path)
                expect(false, "duplicate start should fail")
            } catch let error as FolderObserverError {
                expect(error == .alreadyRunning, "duplicate start should return alreadyRunning")
            }

            let teardown = try observer.stopAndWait(timeout: .now() + 3)
            expect(teardown.descriptorWasOpened && teardown.descriptorWasClosed,
                   "stopAndWait should confirm descriptor teardown")
            expect(observer.lifecycleState == .stopped, "completed cancellation should reach stopped state")
            let repeated = try observer.stopAndWait(timeout: .now() + 1)
            expect(repeated == teardown, "repeated stop should return the completed teardown")
            do {
                try observer.start(path: directory.path)
                expect(false, "terminal observer should reject restart")
            } catch let error as FolderObserverError {
                expect(error == .stopped, "restart should return stopped")
            }
        }
    }

    private func testChildMutations() throws {
        try verifySingleChildMutation(
            prefix: "alcove-child-create",
            prepare: { _ in },
            mutate: { directory in
                try self.createFile(at: directory.appendingPathComponent("created"))
            },
            operation: "create"
        )
        try verifySingleChildMutation(
            prefix: "alcove-child-rename",
            prepare: { directory in
                try self.createFile(at: directory.appendingPathComponent("original"))
            },
            mutate: { directory in
                try FileManager.default.moveItem(
                    at: directory.appendingPathComponent("original"),
                    to: directory.appendingPathComponent("renamed")
                )
            },
            operation: "rename"
        )
        try verifySingleChildMutation(
            prefix: "alcove-child-delete",
            prepare: { directory in
                try self.createFile(at: directory.appendingPathComponent("deleted"))
            },
            mutate: { directory in
                try FileManager.default.removeItem(at: directory.appendingPathComponent("deleted"))
            },
            operation: "delete"
        )
    }

    private func testLatency() throws {
        try withTemporaryDirectory(prefix: "alcove-latency") { directory in
            let recorder = EventRecorder()
            let observer = DispatchSourceFolderObserver(onEvent: recorder.append)
            try observer.start(path: directory.path)

            let mutationStart = DispatchSourceFolderObserver.monotonicNow()
            try createFile(at: directory.appendingPathComponent("latency"))
            expect(recorder.waitForCount(1, timeout: .now() + 3), "latency mutation should deliver an event")
            guard let delivered = recorder.snapshot.first else {
                expect(false, "latency test should retain its first event")
                _ = try observer.stopAndWait(timeout: .now() + 3)
                return
            }
            let latency = delivered.timestamp - mutationStart
            print("Observed first-event latency: \(String(format: "%.6f", latency)) seconds")
            expect(latency >= 0, "monotonic event time should not precede the mutation start")
            expect(latency < 3, "observed latency should remain inside the explicit test timeout")
            _ = try observer.stopAndWait(timeout: .now() + 3)
        }
    }

    private func testDirectoryLifecycle() throws {
        try withTemporaryDirectory(prefix: "alcove-directory-lifecycle") { root in
            let observed = root.appendingPathComponent("observed")
            try FileManager.default.createDirectory(at: observed, withIntermediateDirectories: false)
            let renamed = root.appendingPathComponent("renamed")
            let renameRecorder = EventRecorder()
            let renameObserver = DispatchSourceFolderObserver(onEvent: renameRecorder.append)
            try renameObserver.start(path: observed.path)
            try FileManager.default.moveItem(at: observed, to: renamed)
            expect(renameRecorder.waitForCount(1, timeout: .now() + 3),
                   "renaming the observed directory should deliver an event")
            expect(renameRecorder.snapshot.contains(where: { hasFlag(.rename, in: $0) }),
                   "observed-directory rename should carry rename on this runtime")
            _ = try renameObserver.stopAndWait(timeout: .now() + 3)

            let deleted = root.appendingPathComponent("deleted")
            try FileManager.default.createDirectory(at: deleted, withIntermediateDirectories: false)
            let deleteRecorder = EventRecorder()
            let deleteObserver = DispatchSourceFolderObserver(onEvent: deleteRecorder.append)
            try deleteObserver.start(path: deleted.path)
            try FileManager.default.removeItem(at: deleted)
            expect(deleteRecorder.waitForCount(1, timeout: .now() + 3),
                   "deleting the observed directory should deliver an event")
            expect(deleteRecorder.snapshot.contains(where: { hasFlag(.delete, in: $0) }),
                   "observed-directory deletion should carry delete on this runtime")
            _ = try deleteObserver.stopAndWait(timeout: .now() + 3)
        }
    }

    private func testDirectoryReplacement() throws {
        try withTemporaryDirectory(prefix: "alcove-replacement") { root in
            let observed = root.appendingPathComponent("mapped")
            let displaced = root.appendingPathComponent("displaced")
            try FileManager.default.createDirectory(at: observed, withIntermediateDirectories: false)

            let recorder = EventRecorder()
            let observer = DispatchSourceFolderObserver(onEvent: recorder.append)
            try observer.start(path: observed.path)
            guard let originalIdentity = observer.observedFileIdentity else {
                throw HarnessError.message("observer did not retain its fstat identity")
            }

            try FileManager.default.moveItem(at: observed, to: displaced)
            expect(recorder.waitForCount(1, timeout: .now() + 3),
                   "displacing the observed inode should deliver its rename event")
            let countAfterDisplacement = recorder.count

            try FileManager.default.createDirectory(at: observed, withIntermediateDirectories: false)
            let replacementIdentity = try fileIdentity(at: observed)
            expect(replacementIdentity != originalIdentity, "replacement path should resolve to a different inode")
            try createFile(at: observed.appendingPathComponent("replacement-child"))
            expect(!recorder.waitForCount(countAfterDisplacement + 1, timeout: .now() + .milliseconds(500)),
                   "mutating the replacement inode should not notify the old source")

            try createFile(at: displaced.appendingPathComponent("original-child"))
            expect(recorder.waitForCount(countAfterDisplacement + 1, timeout: .now() + 3),
                   "mutating the displaced original inode should still notify the old source")
            _ = try observer.stopAndWait(timeout: .now() + 3)
        }
    }

    private func testStopSemantics() throws {
        try withTemporaryDirectory(prefix: "alcove-stop") { directory in
            let recorder = EventRecorder()
            let reference = ObserverReference()
            let callbackReturned = DispatchSemaphore(value: 0)
            let observer = DispatchSourceFolderObserver { record in
                recorder.append(record)
                reference.stopObserver()
                callbackReturned.signal()
            }
            reference.set(observer)
            try observer.start(path: directory.path)
            try createFile(at: directory.appendingPathComponent("trigger"))
            expect(callbackReturned.wait(timeout: .now() + 3) == .success,
                   "event callback should return after initiating stop without deadlock")
            let teardown = try observer.waitUntilStopped(timeout: .now() + 3)
            expect(teardown.descriptorWasClosed, "callback-initiated stop should complete descriptor teardown")
            let countAfterStop = recorder.count

            try createFile(at: directory.appendingPathComponent("after-stop"))
            expect(!recorder.waitForCount(countAfterStop + 1, timeout: .now() + .milliseconds(400)),
                   "no user callback should be delivered after teardown completed")
        }
    }

    private func testDescriptorClosure() throws {
        try withTemporaryDirectory(prefix: "alcove-descriptor") { directory in
            let observer = DispatchSourceFolderObserver { _ in }
            try observer.start(path: directory.path)
            let descriptor = observer.openedFileDescriptor
            expect(descriptor >= 0, "running observer should expose its owned descriptor")
            let teardown = try observer.stopAndWait(timeout: .now() + 3)
            expect(teardown.descriptorWasOpened && teardown.descriptorWasClosed,
                   "cancel handler should report an opened and closed descriptor")
            errno = 0
            let descriptorQuery = fcntl(descriptor, F_GETFD)
            let queryError = errno
            expect(descriptorQuery == -1 && queryError == EBADF,
                   "fcntl should confirm the exact captured descriptor is closed with EBADF")
        }
    }

    private func testExternalStopWaitsForCallback() throws {
        try withTemporaryDirectory(prefix: "alcove-stop-waits") { directory in
            let callbackEntered = DispatchSemaphore(value: 0)
            let releaseCallback = DispatchSemaphore(value: 0)
            let stopReturned = DispatchSemaphore(value: 0)
            let observer = DispatchSourceFolderObserver { _ in
                callbackEntered.signal()
                _ = releaseCallback.wait(timeout: .now() + 3)
            }
            try observer.start(path: directory.path)
            try createFile(at: directory.appendingPathComponent("trigger"))
            expect(callbackEntered.wait(timeout: .now() + 3) == .success,
                   "blocking callback should begin before external stop")

            DispatchQueue.global().async {
                observer.stop()
                stopReturned.signal()
            }
            expect(stopReturned.wait(timeout: .now() + .milliseconds(200)) == .timedOut,
                   "external stop should not return while a user callback is active")
            releaseCallback.signal()
            expect(stopReturned.wait(timeout: .now() + 3) == .success,
                   "external stop should return after the active callback exits")
            let teardown = try observer.waitUntilStopped(timeout: .now() + 3)
            expect(teardown.descriptorWasClosed, "external stop should still complete descriptor teardown")
        }
    }

    private func testFixtureCleanup() throws {
        var fixturePath = ""
        try withTemporaryDirectory(prefix: "alcove-cleanup") { directory in
            fixturePath = directory.path
            try createFile(at: directory.appendingPathComponent("fixture"))
            expect(FileManager.default.fileExists(atPath: fixturePath), "fixture should exist inside its transaction")
        }
        expect(!FileManager.default.fileExists(atPath: fixturePath),
               "successful fixture transaction should remove its directory")
    }

    private func testDeinitTeardown() throws {
        try withTemporaryDirectory(prefix: "alcove-deinit") { directory in
            var observer: DispatchSourceFolderObserver? = DispatchSourceFolderObserver { _ in }
            try observer?.start(path: directory.path)
            let descriptor = observer?.openedFileDescriptor ?? -1
            expect(descriptor >= 0, "observer should own a descriptor before deinitialization")
            observer = nil

            let deadline = DispatchSourceFolderObserver.monotonicNow() + 3
            var descriptorWasClosed = false
            repeat {
                errno = 0
                if fcntl(descriptor, F_GETFD) == -1, errno == EBADF {
                    descriptorWasClosed = true
                    break
                }
                usleep(1_000)
            } while DispatchSourceFolderObserver.monotonicNow() < deadline
            expect(descriptorWasClosed, "deinit cancellation should close the captured descriptor within the timeout")
        }
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

    private func verifySingleChildMutation(
        prefix: String,
        prepare: (URL) throws -> Void,
        mutate: (URL) throws -> Void,
        operation: String
    ) throws {
        try withTemporaryDirectory(prefix: prefix) { directory in
            try prepare(directory)
            let recorder = EventRecorder()
            let observer = DispatchSourceFolderObserver(onEvent: recorder.append)
            try observer.start(path: directory.path)
            try mutate(directory)
            expect(recorder.waitForCount(1, timeout: .now() + 3),
                   "child \(operation) should deliver a real event in its isolated fixture")
            expect(recorder.snapshot.contains(where: { hasFlag(.write, in: $0) }),
                   "child \(operation) should yield a directory write flag on this runtime")
            _ = try observer.stopAndWait(timeout: .now() + 3)
        }
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

    private func fileIdentity(at url: URL) throws -> ObservedFileIdentity {
        var metadata = stat()
        guard Darwin.lstat(url.path, &metadata) == 0 else {
            throw HarnessError.message("stat failed for \(url.path): errno \(errno)")
        }
        return ObservedFileIdentity(device: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino))
    }

    private func hasFlag(
        _ flag: DispatchSource.FileSystemEvent,
        in record: FolderObservationRecord
    ) -> Bool {
        record.rawEventMask & flag.rawValue != 0
    }
}

let exitCode = MainActor.assumeIsolated {
    TestHarness().run()
}
exit(exitCode)
