import Darwin
import Dispatch
import Foundation

private enum Candidate: String, Codable, CaseIterable {
    case dispatch
    case fsevents
}

private enum Scenario: String, Codable, CaseIterable {
    case independentRoots = "independent-roots"
    case sharedRoot = "shared-root"
    case mutationLoad = "mutation-load"
    case lifecycleChurn = "lifecycle-churn"
}

private struct ProcessUsage: Codable {
    let userCPUSeconds: Double
    let systemCPUSeconds: Double
    let maxRSSBytesHighWater: Int64
}

private struct RegistrationEvidence: Codable {
    let index: Int
    let generation: UInt64
    let registrationIdentity: String?
    let expectedMarkerPath: String
    let received: Bool
    let matchedMarkerPath: String?
    let callbackCount: Int
    let recordCount: Int
    let callbackBatchCount: Int?
}

private struct LoadResult: Codable {
    let candidate: Candidate
    let scenario: Scenario
    let observerCount: Int
    let requiredEvidenceCount: Int
    let receivedEvidenceCount: Int
    let registrations: [RegistrationEvidence]
    let mutationRegularFileCount: Int
    let finalEnumerationCount: Int?
    let mutationDurationSeconds: Double?
    let knownDroppedFlagCount: Int
    let rootChangeFlagCount: Int
    let processUsageBefore: ProcessUsage
    let processUsageAfter: ProcessUsage
    let descriptorBaseline: Int
    let descriptorBeforeTeardown: Int
    let descriptorAfterSettling: Int
    let descriptorDeltaFromBaseline: Int
    let descriptorSettleDurationSeconds: Double
    let descriptorReturnedToBaseline: Bool
    let postCycleDescriptorCounts: [Int]
    let bridgeFailureCount: Int
    let teardownState: String
    let timeoutExpired: Bool
    let cleanupOK: Bool
}

private enum TestError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let value): return value }
    }
}

private struct ProcessOutput {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let watchdogExpired: Bool
    let childTempWasEmpty: Bool
}

private final class PipeCapture: @unchecked Sendable {
    let pipe = Pipe()

    private let lock = NSLock()
    private let completion = DispatchGroup()
    private var data = Data()
    private var didReachEOF = false
    private var parentWriteEndIsClosed = false

    init() {
        completion.enter()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.receive(handle.availableData)
        }
    }

    func closeParentWriteEnd() throws {
        let shouldClose = lock.withLock {
            guard !parentWriteEndIsClosed else { return false }
            parentWriteEndIsClosed = true
            return true
        }
        if shouldClose { try pipe.fileHandleForWriting.close() }
    }

    func collectedString(timeoutSeconds: Double) throws -> String {
        let result = completion.wait(
            timeout: .now() + .milliseconds(Int(timeoutSeconds * 1_000))
        )
        guard result == .success else {
            throw TestError.message("timed out draining child process pipe")
        }
        return lock.withLock { String(decoding: data, as: UTF8.self) }
    }

    func cancel() throws {
        pipe.fileHandleForReading.readabilityHandler = nil
        let shouldComplete = lock.withLock {
            guard !didReachEOF else { return false }
            didReachEOF = true
            return true
        }
        var errors: [String] = []
        do { try pipe.fileHandleForReading.close() }
        catch { errors.append("read end: \(error)") }
        do { try closeParentWriteEnd() }
        catch { errors.append("write end: \(error)") }
        if shouldComplete { completion.leave() }
        if !errors.isEmpty {
            throw TestError.message("pipe cancellation failed: \(errors.joined(separator: "; "))")
        }
    }

    private func receive(_ chunk: Data) {
        if chunk.isEmpty {
            pipe.fileHandleForReading.readabilityHandler = nil
            let shouldComplete = lock.withLock {
                guard !didReachEOF else { return false }
                didReachEOF = true
                return true
            }
            if shouldComplete { completion.leave() }
        } else {
            lock.withLock { data.append(chunk) }
        }
    }
}

@MainActor
private final class TestHarness {
    private let probe: String
    private var passed = 0
    private var failed = 0
    private var failures: [String] = []

    init(probe: String) {
        self.probe = probe
    }

    func run() -> Int32 {
        runTest("invalid arguments fail closed", invalidArguments)
        for candidate in Candidate.allCases {
            for scenario in Scenario.allCases {
                runTest("\(candidate.rawValue) \(scenario.rawValue)") {
                    try validateSuccessful(candidate: candidate, scenario: scenario)
                }
            }
        }
        runTest("real FSEvents event timeout cleans its fixture", runtimeTimeout)
        runTest("runner drains output while the child is active", largeProcessOutput)
        runTest("outer watchdog terminates an active child and runner cleans", outerWatchdog)
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

    private func runProbe(
        arguments: [String],
        outerTimeout: Double,
        waitForChildTempActivity: Bool = false,
        executable: String? = nil
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable ?? probe)
        process.arguments = arguments
        let stdoutCapture = PipeCapture()
        let stderrCapture = PipeCapture()
        process.standardOutput = stdoutCapture.pipe
        process.standardError = stderrCapture.pipe
        let childTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("alcove-load-child-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: childTemp, withIntermediateDirectories: false)
        var environment = ProcessInfo.processInfo.environment
        environment["TMPDIR"] = childTemp.path + "/"
        process.environment = environment

        let execution: Result<(Int32, String, String, Bool), Error>
        var processStarted = false
        do {
            try process.run()
            processStarted = true
            try stdoutCapture.closeParentWriteEnd()
            try stderrCapture.closeParentWriteEnd()
            if waitForChildTempActivity {
                let activityDeadline = DispatchTime.now() + .seconds(2)
                while process.isRunning, DispatchTime.now() < activityDeadline {
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: childTemp,
                        includingPropertiesForKeys: nil
                    )
                    if !contents.isEmpty { break }
                    usleep(10_000)
                }
            }
            let deadline = DispatchTime.now() + .milliseconds(Int(outerTimeout * 1_000))
            waitForExit(process, deadline: deadline)
            let expired = process.isRunning
            if process.isRunning {
                try terminateBounded(process)
            }
            execution = .success((
                process.terminationStatus,
                try stdoutCapture.collectedString(timeoutSeconds: 2),
                try stderrCapture.collectedString(timeoutSeconds: 2),
                expired
            ))
        } catch {
            var secondaryErrors: [String] = []
            if processStarted, process.isRunning {
                do { try terminateBounded(process) }
                catch { secondaryErrors.append("termination: \(error)") }
            }
            do { try stdoutCapture.cancel() }
            catch { secondaryErrors.append("stdout: \(error)") }
            do { try stderrCapture.cancel() }
            catch { secondaryErrors.append("stderr: \(error)") }
            if secondaryErrors.isEmpty {
                execution = .failure(error)
            } else {
                execution = .failure(TestError.message(
                    "process error \(error); secondary errors: \(secondaryErrors.joined(separator: "; "))"
                ))
            }
        }

        let inspection: Result<Bool, Error>
        do {
            inspection = .success(try FileManager.default.contentsOfDirectory(
                at: childTemp,
                includingPropertiesForKeys: nil
            ).isEmpty)
        } catch {
            inspection = .failure(error)
        }
        let cleanup: Result<Void, Error>
        do {
            try FileManager.default.removeItem(at: childTemp)
            cleanup = .success(())
        } catch {
            cleanup = .failure(error)
        }

        switch (execution, inspection, cleanup) {
        case (.success(let raw), .success(let empty), .success):
            return ProcessOutput(
                exitCode: raw.0,
                stdout: raw.1,
                stderr: raw.2,
                watchdogExpired: raw.3,
                childTempWasEmpty: empty
            )
        case (.failure(let error), _, .success): throw error
        case (.failure(let error), _, .failure(let cleanupError)):
            throw TestError.message("process error \(error); cleanup error \(cleanupError)")
        case (.success, .failure(let error), .success): throw error
        case (.success, .failure(let error), .failure(let cleanupError)):
            throw TestError.message("inspection error \(error); cleanup error \(cleanupError)")
        case (.success, .success, .failure(let cleanupError)): throw cleanupError
        }
    }

    private func waitForExit(_ process: Process, deadline: DispatchTime) {
        while process.isRunning, DispatchTime.now() < deadline { usleep(20_000) }
    }

    private func terminateBounded(_ process: Process) throws {
        guard process.isRunning else { return }
        process.terminate()
        waitForExit(process, deadline: .now() + .seconds(2))
        if process.isRunning {
            guard Darwin.kill(process.processIdentifier, SIGKILL) == 0 else {
                throw TestError.message("SIGKILL failed with errno \(errno)")
            }
            waitForExit(process, deadline: .now() + .seconds(2))
        }
        guard !process.isRunning else {
            throw TestError.message("process remained alive after SIGKILL")
        }
    }

    private func decode(_ output: String) throws -> LoadResult {
        let data = Data(output.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        do { return try JSONDecoder().decode(LoadResult.self, from: data) }
        catch { throw TestError.message("strict JSON decode failed: \(error)") }
    }

    private func invalidArguments() throws {
        for arguments in [
            [],
            ["--candidate", "unknown", "--scenario", "shared-root", "--timeout", "5"],
            ["--candidate", "dispatch", "--scenario", "unknown", "--timeout", "5"],
            ["--candidate", "dispatch", "--scenario", "shared-root", "--timeout", "0"]
        ] {
            let output = try runProbe(arguments: arguments, outerTimeout: 5)
            expect(output.exitCode == 64, "invalid arguments should exit 64, got \(output.exitCode)")
            expect(output.stdout.isEmpty, "invalid arguments must not emit success JSON")
            expect(output.childTempWasEmpty, "invalid argument probe should leave private TMPDIR empty")
        }
    }

    private func validateSuccessful(candidate: Candidate, scenario: Scenario) throws {
        let output = try runProbe(
            arguments: [
                "--candidate", candidate.rawValue,
                "--scenario", scenario.rawValue,
                "--timeout", "10"
            ],
            outerTimeout: scenario == .lifecycleChurn ? 30 : 20
        )
        expect(output.exitCode == 0, "\(candidate.rawValue)/\(scenario.rawValue) exit \(output.exitCode): \(output.stderr)")
        expect(!output.watchdogExpired, "successful probe must not hit outer watchdog")
        expect(output.stderr.isEmpty, "successful probe stderr must be empty: \(output.stderr)")
        expect(output.childTempWasEmpty, "successful probe must remove its own fixture")
        guard output.exitCode == 0 else { return }
        let result = try decode(output.stdout)
        expect(result.candidate == candidate, "candidate must round trip")
        expect(result.scenario == scenario, "scenario must round trip")
        expect(result.cleanupOK, "success JSON requires cleanupOK")
        expect(result.teardownState == "stopped", "success JSON requires stopped teardown")
        expect(!result.timeoutExpired, "success JSON must not contradict timeout")
        expect(result.receivedEvidenceCount == result.requiredEvidenceCount, "not every registration received evidence")
        expect(result.registrations.count == result.requiredEvidenceCount, "registration evidence array count differs")
        expect(result.registrations.allSatisfy(\.received), "all registrations must independently receive evidence")
        expect(Set(result.registrations.map(\.index)).count == result.registrations.count, "registration indices must be unique")
        expect(result.registrations.allSatisfy { $0.generation > 0 }, "all generations must be positive")
        expect(result.registrations.allSatisfy { $0.callbackCount > 0 && $0.recordCount > 0 }, "event counts must be positive")
        expect(result.knownDroppedFlagCount >= 0, "dropped flag count must be nonnegative")
        expect(result.rootChangeFlagCount >= 0, "root-change flag count must be nonnegative")
        expect(result.bridgeFailureCount == 0, "bridge failures must be zero")
        expect(result.processUsageBefore.userCPUSeconds >= 0, "initial user CPU must be nonnegative")
        expect(result.processUsageBefore.systemCPUSeconds >= 0, "initial system CPU must be nonnegative")
        expect(result.processUsageBefore.maxRSSBytesHighWater >= 0, "initial ru_maxrss must be nonnegative")
        expect(result.processUsageAfter.userCPUSeconds >= result.processUsageBefore.userCPUSeconds, "user CPU must be monotonic")
        expect(result.processUsageAfter.systemCPUSeconds >= result.processUsageBefore.systemCPUSeconds, "system CPU must be monotonic")
        expect(result.processUsageAfter.maxRSSBytesHighWater >= result.processUsageBefore.maxRSSBytesHighWater, "ru_maxrss high-water must be monotonic")
        expect(result.descriptorBaseline >= 0, "descriptor baseline must be nonnegative")
        expect(result.descriptorBeforeTeardown >= result.descriptorBaseline, "pre-teardown descriptors must not be below baseline")
        expect(result.descriptorAfterSettling == result.descriptorBaseline, "settled descriptor count must equal baseline")
        expect(result.descriptorDeltaFromBaseline == 0, "settled descriptor delta must be zero")
        expect(result.descriptorReturnedToBaseline, "descriptor baseline return must be true")
        expect(result.descriptorSettleDurationSeconds >= 0, "descriptor settle duration must be nonnegative")

        let expectedObserverCount = (scenario == .mutationLoad || scenario == .lifecycleChurn) ? 1 : 8
        expect(result.observerCount == expectedObserverCount, "unexpected maximum simultaneous observer count")
        if scenario == .lifecycleChurn {
            expect(result.observerCount == 1 && result.requiredEvidenceCount == 25, "churn must distinguish concurrent observers from sequential evidence")
        } else {
            expect(result.observerCount == result.requiredEvidenceCount, "non-churn observer and evidence counts must agree")
        }
        if candidate == .dispatch {
            expect(result.registrations.allSatisfy { $0.registrationIdentity == nil }, "DispatchSource has no exposed registration identity")
            expect(result.registrations.allSatisfy { $0.matchedMarkerPath == nil }, "DispatchSource must not claim item-path evidence")
            expect(result.registrations.allSatisfy { $0.callbackBatchCount == nil }, "DispatchSource has no C callback batch count")
            expect(result.registrations.allSatisfy { $0.callbackCount == $0.recordCount }, "Dispatch invalidation callback and record counts must match")
        } else {
            let identities = result.registrations.compactMap(\.registrationIdentity)
            expect(identities.count == result.registrations.count, "FSEvents identity must be present")
            expect(Set(identities).count == identities.count, "FSEvents identities must be distinct")
            expect(result.registrations.allSatisfy { $0.matchedMarkerPath == $0.expectedMarkerPath }, "FSEvents marker paths must match canonically")
            expect(result.registrations.allSatisfy { $0.callbackCount == $0.callbackBatchCount }, "FSE callback and batch counts must match")
            expect(result.registrations.allSatisfy { $0.recordCount >= $0.callbackCount }, "FSE record count must cover callback batches")
        }

        switch scenario {
        case .independentRoots:
            expect(result.requiredEvidenceCount == 8, "independent roots require eight evidence records")
            expect(Set(result.registrations.map(\.index)) == Set(0..<8), "independent roots need indices 0 through 7")
            expect(Set(result.registrations.map(\.expectedMarkerPath)).count == 8, "independent roots need eight unique markers")
            expect(result.mutationRegularFileCount == 8, "independent roots create eight markers")
            expect(result.finalEnumerationCount == nil, "independent roots must not claim enumeration evidence")
            expect(result.mutationDurationSeconds == nil, "independent roots must not claim mutation timing")
            expect(result.postCycleDescriptorCounts.isEmpty, "independent roots must not claim per-cycle descriptors")
        case .sharedRoot:
            expect(result.requiredEvidenceCount == 8, "shared root requires eight evidence records")
            expect(Set(result.registrations.map(\.index)) == Set(0..<8), "shared root needs indices 0 through 7")
            expect(Set(result.registrations.map(\.expectedMarkerPath)).count == 1, "shared root uses one marker")
            expect(result.mutationRegularFileCount == 1, "shared root creates one marker")
            expect(result.finalEnumerationCount == nil, "shared root must not claim enumeration evidence")
            expect(result.mutationDurationSeconds == nil, "shared root must not claim mutation timing")
            expect(result.postCycleDescriptorCounts.isEmpty, "shared root must not claim per-cycle descriptors")
        case .mutationLoad:
            expect(result.requiredEvidenceCount == 1, "mutation load requires one sentinel evidence record")
            expect(result.registrations.map(\.index) == [0], "mutation load needs registration index zero")
            expect(result.mutationRegularFileCount == 1_001, "load creates 1001 files")
            expect(result.finalEnumerationCount == 1_001, "load enumeration must find exactly 1001 files")
            expect((result.mutationDurationSeconds ?? -1) >= 0, "load mutation duration must be monotonic/nonnegative")
            expect(result.postCycleDescriptorCounts.isEmpty, "mutation load must not claim per-cycle descriptors")
        case .lifecycleChurn:
            expect(result.requiredEvidenceCount == 25, "churn requires evidence from all 25 registrations")
            expect(Set(result.registrations.map(\.index)) == Set(0..<25), "churn needs indices 0 through 24")
            expect(result.mutationRegularFileCount == 25, "churn runs 25 cycles")
            expect(result.finalEnumerationCount == nil, "churn must not claim enumeration evidence")
            expect(result.mutationDurationSeconds == nil, "churn must not claim mutation timing")
            expect(result.postCycleDescriptorCounts.count == 25, "churn records every post-cycle descriptor count")
            expect(result.postCycleDescriptorCounts.allSatisfy { $0 == result.descriptorBaseline }, "every cycle must settle to descriptor baseline")
        }
    }

    private func runtimeTimeout() throws {
        let output = try runProbe(
            arguments: [
                "--candidate", "fsevents",
                "--scenario", "independent-roots",
                "--timeout", "0.001"
            ],
            outerTimeout: 10
        )
        expect(output.exitCode == 1, "real event timeout should exit 1, got \(output.exitCode)")
        expect(output.stdout.isEmpty, "failed probe must not emit success JSON")
        expect(output.stderr.contains("Event timeout"), "timeout error should be explicit")
        expect(!output.watchdogExpired, "probe timeout should finish inside outer watchdog")
        expect(output.childTempWasEmpty, "failed probe must clean its own fixture")
    }

    private func largeProcessOutput() throws {
        let output = try runProbe(
            arguments: [
                "-c",
                "i=0; while [ $i -lt 20000 ]; do printf '012345678901234567890123456789\\n'; i=$((i+1)); done"
            ],
            outerTimeout: 10,
            executable: "/bin/sh"
        )
        expect(output.exitCode == 0, "large-output child must exit successfully")
        expect(!output.watchdogExpired, "large-output child must not fill the pipe and hit the watchdog")
        expect(output.stdout.utf8.count == 620_000, "runner must drain every stdout byte")
        expect(output.stderr.isEmpty, "large-output child must keep stderr empty")
        expect(output.childTempWasEmpty, "large-output child must leave its private TMPDIR empty")
    }

    private func outerWatchdog() throws {
        let output = try runProbe(
            arguments: ["-c", "mkdir \"$TMPDIR/forced-fixture\" && sleep 5"],
            outerTimeout: 0.05,
            waitForChildTempActivity: true,
            executable: "/bin/sh"
        )
        expect(output.watchdogExpired, "outer watchdog must expire")
        expect(output.exitCode != 0, "terminated process must exit nonzero")
        expect(!output.childTempWasEmpty, "forced probe should leave a fixture for runner cleanup evidence")
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: observer-load-tests <probe>\n", stderr)
    exit(64)
}

private let harness = TestHarness(probe: CommandLine.arguments[1])
exit(harness.run())
