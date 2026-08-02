import Darwin
import Dispatch
import Foundation

private enum HarnessError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self { case .message(let value): return value }
    }
}

private final class PipeCapture: @unchecked Sendable {
    let pipe = Pipe()
    private let lock = NSLock()
    private let completion = DispatchGroup()
    private var data = Data()
    private var reachedEOF = false
    private var writeEndClosed = false

    init() {
        completion.enter()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.receive(handle.availableData)
        }
    }

    func closeParentWriteEnd() throws {
        let shouldClose = lock.withLock {
            guard !writeEndClosed else { return false }
            writeEndClosed = true
            return true
        }
        if shouldClose { try pipe.fileHandleForWriting.close() }
    }

    func string(timeoutSeconds: Double) throws -> String {
        guard completion.wait(
            timeout: .now() + .milliseconds(Int(timeoutSeconds * 1_000))
        ) == .success else {
            throw HarnessError.message("pipe drain timed out")
        }
        return lock.withLock { String(decoding: data, as: UTF8.self) }
    }

    func cancel() throws {
        pipe.fileHandleForReading.readabilityHandler = nil
        let shouldComplete = lock.withLock {
            guard !reachedEOF else { return false }
            reachedEOF = true
            return true
        }
        var errors: [String] = []
        do { try pipe.fileHandleForReading.close() }
        catch { errors.append("read end: \(error)") }
        do { try closeParentWriteEnd() }
        catch { errors.append("write end: \(error)") }
        if shouldComplete { completion.leave() }
        if !errors.isEmpty {
            throw HarnessError.message("pipe cancellation failed: \(errors.joined(separator: "; "))")
        }
    }

    private func receive(_ chunk: Data) {
        if chunk.isEmpty {
            pipe.fileHandleForReading.readabilityHandler = nil
            let shouldComplete = lock.withLock {
                guard !reachedEOF else { return false }
                reachedEOF = true
                return true
            }
            if shouldComplete { completion.leave() }
        } else {
            lock.withLock { data.append(chunk) }
        }
    }
}

private struct ProcessOutput {
    let exitCode: Int32
    let terminationReason: Process.TerminationReason
    let stdout: String
    let stderr: String
    let watchdogExpired: Bool
    let childTempWasEmpty: Bool
}

private func ownedDirectoryEntryCount(_ path: String) throws -> Int {
    guard let directory = Darwin.opendir(path) else {
        throw HarnessError.message("opendir failed with errno \(errno)")
    }
    var count = 0
    var readError: Int32?
    errno = 0
    while let entry = Darwin.readdir(directory) {
        let name = withUnsafePointer(to: entry.pointee.d_name) { tuplePointer in
            tuplePointer.withMemoryRebound(
                to: CChar.self,
                capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)
            ) { String(cString: $0) }
        }
        if name != ".", name != ".." { count += 1 }
        errno = 0
    }
    if errno != 0 { readError = errno }
    let closeResult = Darwin.closedir(directory)
    let closeError = closeResult == 0 ? nil : errno
    switch (readError, closeError) {
    case (nil, nil): return count
    case (let read?, nil): throw HarnessError.message("readdir failed with errno \(read)")
    case (nil, let close?): throw HarnessError.message("closedir failed with errno \(close)")
    case (let read?, let close?):
        throw HarnessError.message(
            "readdir failed with errno \(read); closedir failed with errno \(close)"
        )
    }
}

@MainActor
private final class TestHarness {
    private let probe: String
    private var passed = 0
    private var failed = 0
    private var failures: [String] = []

    init(probe: String) { self.probe = probe }

    func run() -> Int32 {
        runTest("protected location evidence", protectedLocations)
        runTest("owned fixture evidence", fixtures)
        runTest("all command consistency", allCommand)
        runTest("classifier preserves raw metadata", classifierMetadata)
        runTest("stale generation is rejected", staleGeneration)
        runTest("background enumeration timeout is bounded", backgroundTimeout)
        runTest("restoration failure is fatal", restorationFailure)
        runTest("cleanup failure is fatal", cleanupFailure)
        runTest("active worker prevents transaction cleanup", transactionConvergence)
        runTest("combined transaction errors preserve both causes", combinedErrors)
        runTest("invalid arguments fail closed", invalidArguments)
        runTest("runner drains large output", largeOutput)
        runTest("runner uses TERM then SIGKILL", watchdog)
        failures.forEach { print($0) }
        print("Assertions passed: \(passed)")
        print("Assertions failed: \(failed)")
        return failed == 0 ? 0 : 1
    }

    private func runTest(_ name: String, _ body: () throws -> Void) {
        print("[TEST] \(name)")
        do { try body() }
        catch {
            failed += 1
            failures.append("FAIL: \(name) threw: \(error)")
        }
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passed += 1 }
        else {
            failed += 1
            failures.append("FAIL: \(message)")
        }
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        timeoutSeconds: Double,
        waitForTempActivity: Bool = false
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdoutCapture = PipeCapture()
        let stderrCapture = PipeCapture()
        process.standardOutput = stdoutCapture.pipe
        process.standardError = stderrCapture.pipe
        let childTemp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "alcove-access-runner-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: childTemp, withIntermediateDirectories: false)
        var environment = ProcessInfo.processInfo.environment
        environment["TMPDIR"] = childTemp.path + "/"
        process.environment = environment

        let execution: Result<(Int32, Process.TerminationReason, String, String, Bool), Error>
        var started = false
        do {
            try process.run()
            started = true
            try stdoutCapture.closeParentWriteEnd()
            try stderrCapture.closeParentWriteEnd()
            if waitForTempActivity {
                let activityDeadline = DispatchTime.now() + .seconds(2)
                var foundActivity = false
                while process.isRunning, DispatchTime.now() < activityDeadline {
                    var metadata = stat()
                    let fixturePath = childTemp.appendingPathComponent("forced-fixture").path
                    if Darwin.lstat(fixturePath, &metadata) == 0 {
                        foundActivity = true
                        break
                    }
                    usleep(10_000)
                }
                guard foundActivity else {
                    throw HarnessError.message("child did not create its expected temporary fixture")
                }
            }
            waitForExit(
                process,
                deadline: .now() + .milliseconds(Int(timeoutSeconds * 1_000))
            )
            let expired = process.isRunning
            if expired { try terminateBounded(process) }
            execution = .success((
                process.terminationStatus,
                process.terminationReason,
                try stdoutCapture.string(timeoutSeconds: 2),
                try stderrCapture.string(timeoutSeconds: 2),
                expired
            ))
        } catch {
            var secondary: [String] = []
            if started, process.isRunning {
                do { try terminateBounded(process) }
                catch { secondary.append("termination: \(error)") }
            }
            do { try stdoutCapture.cancel() }
            catch { secondary.append("stdout: \(error)") }
            do { try stderrCapture.cancel() }
            catch { secondary.append("stderr: \(error)") }
            if secondary.isEmpty { execution = .failure(error) }
            else {
                execution = .failure(HarnessError.message(
                    "process error \(error); secondary: \(secondary.joined(separator: "; "))"
                ))
            }
        }

        let inspection: Result<Bool, Error>
        do {
            inspection = .success(try ownedDirectoryEntryCount(childTemp.path) == 0)
        } catch { inspection = .failure(error) }
        let cleanup: Result<Void, Error>
        do {
            try FileManager.default.removeItem(at: childTemp)
            cleanup = .success(())
        } catch { cleanup = .failure(error) }

        switch (execution, inspection, cleanup) {
        case (.success(let raw), .success(let empty), .success):
            return ProcessOutput(
                exitCode: raw.0,
                terminationReason: raw.1,
                stdout: raw.2,
                stderr: raw.3,
                watchdogExpired: raw.4,
                childTempWasEmpty: empty
            )
        case (.failure(let error), _, .success): throw error
        case (.failure(let error), _, .failure(let cleanupError)):
            throw HarnessError.message("process error \(error); cleanup error \(cleanupError)")
        case (.success, .failure(let error), .success): throw error
        case (.success, .failure(let error), .failure(let cleanupError)):
            throw HarnessError.message("inspection error \(error); cleanup error \(cleanupError)")
        case (.success, .success, .failure(let error)): throw error
        }
    }

    private func waitForExit(_ process: Process, deadline: DispatchTime) {
        while process.isRunning, DispatchTime.now() < deadline { usleep(20_000) }
    }

    private func terminateBounded(_ process: Process) throws {
        guard process.isRunning else { return }
        process.terminate()
        waitForExit(process, deadline: .now() + .seconds(1))
        if process.isRunning {
            guard Darwin.kill(process.processIdentifier, SIGKILL) == 0 else {
                throw HarnessError.message("SIGKILL failed with errno \(errno)")
            }
            waitForExit(process, deadline: .now() + .seconds(2))
        }
        guard !process.isRunning else {
            throw HarnessError.message("process remained alive after SIGKILL")
        }
    }

    private func probe(_ arguments: [String], timeout: Double = 15) throws -> ProcessOutput {
        try runProcess(executable: probe, arguments: arguments, timeoutSeconds: timeout)
    }

    private func decode(_ output: String) throws -> FullOutput {
        do { return try JSONDecoder().decode(FullOutput.self, from: Data(output.utf8)) }
        catch { throw HarnessError.message("required JSON decode failed: \(error)") }
    }

    private func expectStrictRejection(
        _ original: String,
        replacing target: String,
        with replacement: String,
        message: String
    ) throws {
        let mutated = original.replacingOccurrences(of: target, with: replacement)
        guard mutated != original else {
            throw HarnessError.message("could not construct strict-decoding fixture: \(message)")
        }
        do {
            _ = try decode(mutated)
            expect(false, message)
        } catch {
            expect(true, message)
        }
    }

    private func protectedLocations() throws {
        let output = try probe(["protected-locations"])
        expect(output.exitCode == 0, "protected-locations exit must be zero: \(output.stderr)")
        expect(output.stderr.isEmpty, "protected-locations stderr must be empty")
        expect(output.childTempWasEmpty, "protected-locations must not mutate private TMPDIR")
        let result = try decode(output.stdout)
        let trimmed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.last == "}" else {
            throw HarnessError.message("protected JSON did not end with an object")
        }
        let unknownKeyJSON = String(trimmed.dropLast()) + ",\"unknownReviewKey\":1}"
        do {
            _ = try decode(unknownKeyJSON)
            expect(false, "strict decoder must reject unknown top-level keys")
        } catch {
            expect(true, "strict decoder rejected an unknown top-level key")
        }
        try expectStrictRejection(
            output.stdout,
            replacing: "\"category\":\"desktop\"",
            with: "\"unknownLocationKey\":1,\"category\":\"desktop\"",
            message: "LocationResult must reject unknown keys"
        )
        expect(result.probe == "folder-access-errors", "probe identifier must match")
        expect(result.fixtureResults.isEmpty, "protected command must not claim fixtures")
        expect(result.fixtureCleanupOK, "successful output must report cleanup")
        expect(result.protectedLocations.count == 3, "must report exactly three protected categories")
        expect(Set(result.protectedLocations.map(\.category)) == Set(["desktop", "documents", "downloads"]), "protected categories must match")
        expect(Set(result.protectedLocations.map(\.requestedGeneration)).count == 3, "each protected request needs a unique generation")
        for location in result.protectedLocations {
            expect(location.requestedGeneration == location.returnedGeneration, "returned generation must match request")
            expect(location.generationAccepted, "generation must be accepted")
            expect(!location.executedOnMainThread, "enumeration must run off main thread")
            expect((location.entryCount == nil) != (location.error == nil), "location success/error fields must be mutually exclusive")
            if let error = location.error {
                expect(!error.metadata.domain.isEmpty, "failure must preserve raw domain")
            }
        }
    }

    private func fixtures() throws {
        let output = try probe(["fixtures"])
        expect(output.exitCode == 0, "fixtures exit must be zero: \(output.stderr)")
        expect(output.stderr.isEmpty, "fixtures stderr must be empty")
        expect(output.childTempWasEmpty, "probe must remove its owned fixture")
        let result = try decode(output.stdout)
        try expectStrictRejection(
            output.stdout,
            replacing: "\"category\":\"folderNotFound\"",
            with: "\"unknownClassifiedKey\":1,\"category\":\"folderNotFound\"",
            message: "ClassifiedFolderAccessError must reject unknown keys"
        )
        try expectStrictRejection(
            output.stdout,
            replacing: "\"code\":260",
            with: "\"unknownMetadataKey\":1,\"code\":260",
            message: "ErrorMetadata must reject unknown keys"
        )
        try expectStrictRejection(
            output.stdout,
            replacing: "\"expectedCategory\":\"folderNotFound\"",
            with: "\"unknownFixtureKey\":1,\"expectedCategory\":\"folderNotFound\"",
            message: "FixtureResult must reject unknown keys"
        )
        expect(result.protectedLocations.isEmpty, "fixtures command must not claim protected results")
        expect(result.fixtureCleanupOK, "fixture cleanup must complete before JSON")
        expect(result.fixtureResults.count == 4, "must report exactly four fixtures")
        expect(Set(result.fixtureResults.map(\.generation)).count == 4, "fixture generations must be unique")
        var byName: [String: FixtureResult] = [:]
        for fixture in result.fixtureResults {
            if byName[fixture.name] != nil {
                expect(false, "fixture names must not repeat")
            } else {
                byName[fixture.name] = fixture
            }
        }
        expect(byName.count == 4, "fixture names must be unique")
        expect(byName["accessible-directory"]?.entryCount == 2, "accessible fixture must enumerate two entries")
        expect(byName["accessible-directory"]?.enumerationError == nil, "accessible fixture must not claim an error")
        expect(byName["accessible-directory"]?.posixProbeErrno == nil, "accessible fixture must not claim POSIX failure")
        try checkFixture(byName["missing-path"], category: .folderNotFound, errno: ENOENT)
        try checkFixture(byName["file-as-directory"], category: .notDirectory, errno: ENOTDIR)
        let permission = byName["permission-denied"]
        guard let permissionCode = permission?.posixProbeErrno else {
            throw HarnessError.message("permission fixture did not record real POSIX errno")
        }
        expect(permissionCode == EACCES || permissionCode == EPERM, "permission probe must record EACCES/EPERM")
        expect(permission?.enumerationError?.category == .permissionDenied, "permission enumeration must be classified")
        expect(permission?.entryCount == nil, "permission failure must not claim an entry count")
        expect(permission?.enumerationError?.metadata.domain == NSCocoaErrorDomain, "permission raw domain must be Cocoa")
        expect(permission?.enumerationError?.metadata.code == NSFileReadNoPermissionError, "permission raw code must be 257")
        expect(permission?.enumerationError?.metadata.underlyingDomain == NSPOSIXErrorDomain, "permission underlying domain must be POSIX")
        expect(permission?.enumerationError?.metadata.underlyingCode == Int(EACCES), "permission underlying code must be EACCES")
        for fixture in result.fixtureResults {
            expect(!fixture.executedOnMainThread, "every fixture enumeration must run off main thread")
            expect(fixture.generation > 0, "every fixture must carry a generation")
        }
    }

    private func checkFixture(
        _ fixture: FixtureResult?,
        category: FolderAccessCategory,
        errno expectedErrno: Int32
    ) throws {
        guard let fixture else { throw HarnessError.message("missing fixture \(category.rawValue)") }
        expect(fixture.expectedCategory == category.rawValue, "expected category must match")
        expect(fixture.entryCount == nil, "error fixture must not claim an entry count")
        expect(fixture.enumerationError?.category == category, "enumeration category must match")
        expect(fixture.posixProbeErrno == expectedErrno, "independent POSIX probe errno must match")
        expect(fixture.enumerationError?.metadata.domain.isEmpty == false, "raw NSError domain must be retained")
        switch category {
        case .folderNotFound:
            expect(fixture.enumerationError?.metadata.domain == NSCocoaErrorDomain, "missing raw domain must be Cocoa")
            expect(fixture.enumerationError?.metadata.code == NSFileReadNoSuchFileError, "missing raw code must be 260")
            expect(fixture.enumerationError?.metadata.underlyingDomain == NSOSStatusErrorDomain, "missing underlying domain must be OSStatus")
            expect(fixture.enumerationError?.metadata.underlyingCode == -43, "missing underlying code must be -43")
        case .notDirectory:
            expect(fixture.enumerationError?.metadata.domain == NSCocoaErrorDomain, "not-directory raw domain must be Cocoa")
            expect(fixture.enumerationError?.metadata.code == NSFileReadUnknownError, "not-directory raw code must be 256")
            expect(fixture.enumerationError?.metadata.underlyingDomain == NSPOSIXErrorDomain, "not-directory underlying domain must be POSIX")
            expect(fixture.enumerationError?.metadata.underlyingCode == Int(ENOTDIR), "not-directory underlying code must be ENOTDIR")
        case .permissionDenied, .enumerationFailed:
            break
        }
    }

    private func allCommand() throws {
        let output = try probe(["all"])
        expect(output.exitCode == 0, "all exit must be zero: \(output.stderr)")
        let result = try decode(output.stdout)
        expect(result.protectedLocations.count == 3, "all must include protected results")
        expect(result.fixtureResults.count == 4, "all must include fixtures")
        expect(result.fixtureCleanupOK, "all must clean fixture before success")
        expect(output.childTempWasEmpty, "all must leave private TMPDIR empty")
    }

    private func classifierMetadata() throws {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
        let raw = NSError(
            domain: "AlcoveReviewDomain",
            code: 991,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        let classified = classifyEnumerationError(raw)
        expect(classified.category == .enumerationFailed, "unknown error must remain generic")
        expect(classified.metadata.domain == "AlcoveReviewDomain", "top-level domain must be preserved")
        expect(classified.metadata.code == 991, "top-level code must be preserved")
        expect(classified.metadata.underlyingDomain == NSPOSIXErrorDomain, "underlying domain must be preserved")
        expect(classified.metadata.underlyingCode == Int(EIO), "underlying code must be preserved")
        expect(classified.observedPOSIXCode == EIO, "observed underlying POSIX code must be retained")

        let cocoaMissing = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        let missing = classifyEnumerationError(cocoaMissing)
        expect(missing.category == .folderNotFound, "Cocoa missing-file code must classify")
        expect(missing.metadata.domain == NSCocoaErrorDomain, "Cocoa domain must not be rewritten")
        expect(missing.metadata.code == NSFileReadNoSuchFileError, "Cocoa code must not be rewritten")
        expect(missing.observedPOSIXCode == nil, "classifier must not invent POSIX errno")
    }

    private func staleGeneration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "alcove-stale-generation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let counter = GenerationCounter()
        let requested = counter.next()
        let attempt = try BackgroundEnumerator(
            label: "com.alcove.spike.stale-generation"
        ).enumerate(path: root.path, generation: requested, timeoutSeconds: 2)
        _ = counter.next()
        do {
            try requireCurrent(attempt, currentGeneration: counter.current)
            expect(false, "stale result must throw")
        } catch ProbeError.staleResult(let returned, let current) {
            expect(returned == requested, "stale error must preserve returned generation")
            expect(current == requested + 1, "stale error must preserve current generation")
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { throw HarnessError.message("stale fixture cleanup failed: \(error)") }
        expect(!FileManager.default.fileExists(atPath: root.path), "stale fixture must be removed")
    }

    private func restorationFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "alcove-restore-seam-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            _ = try runOwnedFixtureTransaction(
                root: root,
                counter: GenerationCounter(),
                enumerator: BackgroundEnumerator(label: "com.alcove.spike.restore-seam"),
                restoreAction: { path in
                    try restoreDirectoryPermissions(path)
                    throw ProbeError.restoration("injected post-restore failure")
                }
            )
            expect(false, "restoration failure must prevent transaction success")
        } catch ProbeError.restoration(let message) {
            expect(message == "injected post-restore failure", "restoration error must be preserved")
        }
        expect(!FileManager.default.fileExists(atPath: root.path), "failed restoration transaction must still clean its root")
    }

    private func backgroundTimeout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "alcove-background-timeout-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let enumerator = BackgroundEnumerator(
            label: "com.alcove.spike.background-timeout",
            beforeEnumeration: {
                entered.signal()
                release.wait()
            }
        )
        do {
            _ = try enumerator.enumerate(
                path: root.path,
                generation: 1,
                timeoutSeconds: 0.05
            )
            expect(false, "blocked enumeration must time out")
        } catch ProbeError.backgroundTimeout {
            expect(entered.wait(timeout: .now()) == .success, "background work must actually start")
        }
        release.signal()
        expect(enumerator.waitUntilIdle(timeoutSeconds: 2), "timed-out work must be allowed to converge before cleanup")
        do { try FileManager.default.removeItem(at: root) }
        catch { throw HarnessError.message("timeout fixture cleanup failed: \(error)") }
        expect(!FileManager.default.fileExists(atPath: root.path), "timeout fixture must be removed")
    }

    private func cleanupFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "alcove-cleanup-seam-\(UUID().uuidString)",
            isDirectory: true
        )
        let counter = GenerationCounter()
        let enumerator = BackgroundEnumerator(label: "com.alcove.spike.cleanup-seam")
        do {
            _ = try runOwnedFixtureTransaction(
                root: root,
                counter: counter,
                enumerator: enumerator,
                cleanupAction: { _ in throw ProbeError.cleanup("injected cleanup failure") }
            )
            expect(false, "cleanup failure must prevent success")
        } catch ProbeError.cleanup(let message) {
            expect(message == "injected cleanup failure", "cleanup error must be preserved")
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { throw HarnessError.message("test cleanup failed: \(error)") }
        expect(!FileManager.default.fileExists(atPath: root.path), "test seam must remove its leftover fixture")
    }

    private func transactionConvergence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "alcove-convergence-seam-\(UUID().uuidString)",
            isDirectory: true
        )
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let cleanupCalled = LockedBox<Bool>()
        let enumerator = BackgroundEnumerator(
            label: "com.alcove.spike.convergence-seam",
            beforeEnumeration: {
                entered.signal()
                release.wait()
            }
        )
        var capturedError: Error?
        do {
            _ = try runOwnedFixtureTransaction(
                root: root,
                counter: GenerationCounter(),
                enumerator: enumerator,
                enumerationTimeoutSeconds: 0.05,
                convergenceTimeoutSeconds: 0.05,
                cleanupAction: { url in
                    cleanupCalled.set(true)
                    try removeOwnedRoot(url)
                }
            )
        } catch {
            capturedError = error
        }
        expect(entered.wait(timeout: .now()) == .success, "transaction worker must actually start")
        expect(cleanupCalled.get() != true, "transaction must not clean while worker is active")
        expect(capturedError is ProbeError, "transaction timeout must remain typed")
        expect(FileManager.default.fileExists(atPath: root.path), "outer runner must retain the active fixture")
        release.signal()
        expect(enumerator.waitUntilIdle(timeoutSeconds: 2), "released transaction worker must converge")
        do { try FileManager.default.removeItem(at: root) }
        catch { throw HarnessError.message("convergence fixture cleanup failed: \(error)") }
        expect(!FileManager.default.fileExists(atPath: root.path), "convergence fixture must be removed after idle")
    }

    private func combinedErrors() throws {
        let execution: Result<Int, Error> = .failure(
            ProbeError.fixtureMismatch("primary fixture failure")
        )
        let cleanup: Result<Void, Error> = .failure(
            ProbeError.cleanup("secondary cleanup failure")
        )
        do {
            _ = try resolveTransaction(execution: execution, cleanup: cleanup)
            expect(false, "two transaction failures must throw")
        } catch ProbeError.combined(let primary, let secondary) {
            expect(primary.contains("primary fixture failure"), "combined error must preserve primary")
            expect(secondary.contains("secondary cleanup failure"), "combined error must preserve cleanup")
        }
    }

    private func invalidArguments() throws {
        for arguments in [[], ["bogus"], ["fixtures", "extra"]] {
            let output = try probe(arguments)
            expect(output.exitCode == 64, "invalid arguments must exit 64")
            expect(output.stdout.isEmpty, "invalid arguments must not emit JSON")
            expect(!output.stderr.isEmpty, "invalid arguments must explain usage")
            expect(output.childTempWasEmpty, "invalid argument process must leave TMPDIR empty")
        }
    }

    private func largeOutput() throws {
        let output = try runProcess(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "i=0; while [ $i -lt 20000 ]; do printf '012345678901234567890123456789\\n'; i=$((i+1)); done"
            ],
            timeoutSeconds: 10
        )
        expect(output.exitCode == 0, "large-output child must exit zero")
        expect(!output.watchdogExpired, "active pipe draining must avoid watchdog")
        expect(output.stdout.utf8.count == 620_000, "runner must drain all stdout bytes")
        expect(output.stderr.isEmpty, "large-output stderr must be empty")
        expect(output.childTempWasEmpty, "large-output child must leave TMPDIR empty")
    }

    private func watchdog() throws {
        let output = try runProcess(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "trap '' TERM; mkdir \"$TMPDIR/forced-fixture\"; while :; do :; done"
            ],
            timeoutSeconds: 0.05,
            waitForTempActivity: true
        )
        expect(output.watchdogExpired, "watchdog must expire")
        expect(output.terminationReason == .uncaughtSignal, "forced child must end by signal")
        expect(output.exitCode == SIGKILL, "TERM-resistant child must require SIGKILL")
        expect(!output.childTempWasEmpty, "runner must observe and then clean forced fixture")
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: folder-access-tests <probe>\n", stderr)
    exit(64)
}

private let harness = TestHarness(probe: CommandLine.arguments[1])
exit(harness.run())
