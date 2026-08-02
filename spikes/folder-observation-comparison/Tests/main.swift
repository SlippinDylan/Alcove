// Tests/main.swift — Phase 0.5C2 observer comparison tests
//
// Structural and real-filesystem tests for the comparison probe.
// Runs the probe as a subprocess and validates JSON output, exit codes,
// event receipt, descriptor accounting, resource metrics, and cleanup.

import Darwin
import Dispatch
import Foundation

private enum HarnessError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self {
        case .message(let m): return m
        }
    }
}

@MainActor
private final class TestHarness {
    private var passed = 0
    private var failed = 0
    private var failures: [String] = []

    private let probeBinary: String

    init(probeBinary: String) {
        self.probeBinary = probeBinary
    }

    func run() -> Int32 {
        runTest("invalid arguments return exit 64", testInvalidArguments)
        runTest("dispatch candidate at small item count", testDispatchSmall)
        runTest("fsevents candidate at small item count", testFSEventsSmall)
        runTest("dispatch JSON contains required fields", testDispatchJSONFields)
        runTest("fsevents JSON contains required fields", testFSEventsJSONFields)
        runTest("dispatch receives real event and records latency", testDispatchEventReceipt)
        runTest("fsevents receives real event and records latency", testFSEventsEventReceipt)
        runTest("descriptor accounting returns to baseline", testDescriptorAccounting)
        runTest("resource metrics are non-negative", testResourceMetrics)
        runTest("cleanup removes temporary directory", testCleanupVerification)
        runTest("runtime event timeout fails and cleans up", testRuntimeEventTimeout)
        runTest("outer watchdog terminates a stalled probe", testOuterWatchdog)
        runTest("fsevents bridge failure count is present", testFSEventsBridgeFailure)

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

    // MARK: - Run probe as subprocess

    private struct ProbeOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let outerWatchdogExpired: Bool
        let childTempWasEmpty: Bool
    }

    private func runProbe(args: [String], timeoutSeconds: Double = 60) throws -> ProbeOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: probeBinary)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let processTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("alcove-comparison-child-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: processTemp, withIntermediateDirectories: false)
        var environment = ProcessInfo.processInfo.environment
        environment["TMPDIR"] = processTemp.path + "/"
        process.environment = environment

        let execution: Result<(Int32, String, String, Bool), Error>
        do {
            try process.run()

            let deadline = DispatchTime.now() + .milliseconds(Int(timeoutSeconds * 1000))
            while process.isRunning && DispatchTime.now() < deadline {
                usleep(50_000)
            }

            let watchdogExpired = process.isRunning
            if process.isRunning {
                process.terminate()
                waitForExit(process, deadline: .now() + .seconds(2))
                if process.isRunning {
                    guard Darwin.kill(process.processIdentifier, SIGKILL) == 0 else {
                        throw HarnessError.message("failed to kill timed-out probe: errno \(errno)")
                    }
                    waitForExit(process, deadline: .now() + .seconds(2))
                    guard !process.isRunning else {
                        outPipe.fileHandleForReading.closeFile()
                        errPipe.fileHandleForReading.closeFile()
                        throw HarnessError.message("probe remained running after SIGKILL")
                    }
                }
            }

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            execution = .success((
                process.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "",
                watchdogExpired
            ))
        } catch {
            execution = .failure(error)
        }

        let tempInspection: Result<Bool, Error>
        do {
            let remaining = try FileManager.default.contentsOfDirectory(
                at: processTemp,
                includingPropertiesForKeys: nil
            )
            tempInspection = .success(remaining.isEmpty)
        } catch {
            tempInspection = .failure(error)
        }

        let cleanup: Result<Void, Error>
        do {
            try FileManager.default.removeItem(at: processTemp)
            cleanup = .success(())
        } catch {
            cleanup = .failure(error)
        }

        switch (execution, tempInspection, cleanup) {
        case (.success(let raw), .success(let childTempWasEmpty), .success):
            return ProbeOutput(
                exitCode: raw.0,
                stdout: raw.1,
                stderr: raw.2,
                outerWatchdogExpired: raw.3,
                childTempWasEmpty: childTempWasEmpty
            )
        case (.failure(let executionError), _, .failure(let cleanupError)):
            throw HarnessError.message("probe error: \(executionError); temp cleanup error: \(cleanupError)")
        case (.failure(let executionError), _, .success):
            throw executionError
        case (.success, .failure(let inspectionError), .failure(let cleanupError)):
            throw HarnessError.message("temp inspection error: \(inspectionError); cleanup error: \(cleanupError)")
        case (.success, .failure(let inspectionError), .success):
            throw HarnessError.message("temp inspection error: \(inspectionError)")
        case (.success, .success, .failure(let cleanupError)):
            throw HarnessError.message("temp cleanup error: \(cleanupError)")
        }
    }

    private func waitForExit(_ process: Process, deadline: DispatchTime) {
        while process.isRunning && DispatchTime.now() < deadline {
            usleep(10_000)
        }
    }

    private func parseJSON(_ string: String) -> NSDictionary? {
        guard let data = string.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            return nil
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            return obj as? NSDictionary
        } catch {
            return nil
        }
    }

    // MARK: - Test: invalid arguments

    private func testInvalidArguments() throws {
        // No arguments.
        let r1 = try runProbe(args: [], timeoutSeconds: 5)
        expect(r1.exitCode == 64, "no arguments should return exit 64, got \(r1.exitCode)")

        // Missing --items.
        let r2 = try runProbe(args: ["--candidate", "dispatch", "--timeout", "5"], timeoutSeconds: 5)
        expect(r2.exitCode != 0, "missing --items should fail")

        // Invalid candidate.
        let r3 = try runProbe(args: ["--candidate", "invalid", "--items", "10", "--timeout", "5"], timeoutSeconds: 5)
        expect(r3.exitCode != 0, "invalid candidate should fail")

        // Negative items.
        let r4 = try runProbe(args: ["--candidate", "dispatch", "--items", "-1", "--timeout", "5"], timeoutSeconds: 5)
        expect(r4.exitCode != 0, "negative items should fail")

        // Zero timeout.
        let r5 = try runProbe(args: ["--candidate", "dispatch", "--items", "10", "--timeout", "0"], timeoutSeconds: 5)
        expect(r5.exitCode != 0, "zero timeout should fail")
    }

    // MARK: - Test: dispatch small run

    private func testDispatchSmall() throws {
        let r = try runProbe(args: ["--candidate", "dispatch", "--items", "10", "--timeout", "10"], timeoutSeconds: 30)
        expect(r.exitCode == 0, "dispatch small run should exit 0, got \(r.exitCode)")
        guard let json = parseJSON(r.stdout) else {
            expect(false, "dispatch small run should produce valid JSON")
            return
        }
        expect(json["candidate"] as? String == "dispatch", "candidate should be 'dispatch'")
        expect(json["itemCount"] as? Int == 10, "itemCount should be 10")
        expect(json["cleanupOK"] as? Bool == true, "cleanup should succeed")
    }

    // MARK: - Test: fsevents small run

    private func testFSEventsSmall() throws {
        let r = try runProbe(args: ["--candidate", "fsevents", "--items", "10", "--timeout", "10"], timeoutSeconds: 30)
        expect(r.exitCode == 0, "fsevents small run should exit 0, got \(r.exitCode)")
        guard let json = parseJSON(r.stdout) else {
            expect(false, "fsevents small run should produce valid JSON")
            return
        }
        expect(json["candidate"] as? String == "fsevents", "candidate should be 'fsevents'")
        expect(json["itemCount"] as? Int == 10, "itemCount should be 10")
        expect(json["cleanupOK"] as? Bool == true, "cleanup should succeed")
    }

    // MARK: - Test: dispatch JSON fields

    private func testDispatchJSONFields() throws {
        let r = try runProbe(args: ["--candidate", "dispatch", "--items", "5", "--timeout", "10"], timeoutSeconds: 30)
        expect(r.exitCode == 0, "dispatch JSON test should exit 0")
        guard let json = parseJSON(r.stdout) else {
            expect(false, "dispatch should produce valid JSON")
            return
        }

        // Required fields present.
        expect(json["candidate"] != nil, "candidate field present")
        expect(json["itemCount"] != nil, "itemCount field present")
        expect(json["timeoutSeconds"] != nil, "timeoutSeconds field present")
        expect(json["setupDurationSeconds"] != nil, "setupDurationSeconds field present")
        expect(json["observerStartDurationSeconds"] != nil, "observerStartDurationSeconds field present")
        expect(json["preStartCPU"] != nil, "preStartCPU field present")
        expect(json["preStartMaxRSSBytes"] != nil, "preStartMaxRSSBytes field present")
        expect(json["preStartDescriptorCount"] != nil, "preStartDescriptorCount field present")
        expect(json["markerCreated"] != nil, "markerCreated field present")
        expect(json["firstEventReceived"] != nil, "firstEventReceived field present")
        expect(json["timeoutExpired"] != nil, "timeoutExpired field present")
        expect(json["callbackCount"] != nil, "callbackCount field present")
        expect(json["recordCount"] != nil, "recordCount field present")
        expect(json["runningCPU"] != nil, "runningCPU field present")
        expect(json["runningDescriptorCount"] != nil, "runningDescriptorCount field present")
        expect(json["runningMaxRSSBytes"] != nil, "runningMaxRSSBytes field present")
        expect(json["postStopCPU"] != nil, "postStopCPU field present")
        expect(json["postStopMaxRSSBytes"] != nil, "postStopMaxRSSBytes field present")
        expect(json["teardownDurationSeconds"] != nil, "teardownDurationSeconds field present")
        expect(json["teardownState"] != nil, "teardownState field present")
        expect(json["postTeardownDescriptorCount"] != nil, "postTeardownDescriptorCount field present")
        expect(json["descriptorSettleDurationSeconds"] != nil, "descriptorSettleDurationSeconds field present")
        expect(json["descriptorReturnedToBaseline"] != nil, "descriptorReturnedToBaseline field present")
        expect(json["descriptorDeltaFromPreStart"] != nil, "descriptorDeltaFromPreStart field present")
        expect(json["cleanupOK"] != nil, "cleanupOK field present")

        // Dispatch-specific: callbackBatchCount and bridgeFailureCount should be null.
        // JSON null is represented as NSNull in Foundation.
        expect(json["callbackBatchCount"] is NSNull, "dispatch callbackBatchCount should be null")
        expect(json["bridgeFailureCount"] is NSNull, "dispatch bridgeFailureCount should be null")
    }

    // MARK: - Test: fsevents JSON fields

    private func testFSEventsJSONFields() throws {
        let r = try runProbe(args: ["--candidate", "fsevents", "--items", "5", "--timeout", "10"], timeoutSeconds: 30)
        expect(r.exitCode == 0, "fsevents JSON test should exit 0")
        guard let json = parseJSON(r.stdout) else {
            expect(false, "fsevents should produce valid JSON")
            return
        }

        expect(json["candidate"] != nil, "candidate field present")
        expect(json["callbackBatchCount"] != nil, "fsevents callbackBatchCount field present")
        expect(json["bridgeFailureCount"] != nil, "fsevents bridgeFailureCount field present")

        // callbackBatchCount should be a number (not null) when events were received.
        if let received = json["firstEventReceived"] as? Bool, received {
            expect(json["callbackBatchCount"] is Int, "fsevents callbackBatchCount should be Int when events received")
            expect(json["bridgeFailureCount"] is Int, "fsevents bridgeFailureCount should be Int")
        }
    }

    // MARK: - Test: dispatch event receipt

    private func testDispatchEventReceipt() throws {
        let r = try runProbe(args: ["--candidate", "dispatch", "--items", "5", "--timeout", "10"], timeoutSeconds: 30)
        expect(r.exitCode == 0, "dispatch event receipt should exit 0")
        guard let json = parseJSON(r.stdout) else {
            expect(false, "dispatch event receipt should produce valid JSON")
            return
        }
        expect(json["firstEventReceived"] as? Bool == true, "dispatch should receive the marker event")
        expect(json["markerCreated"] as? Bool == true, "marker should be created")

        if let latency = json["firstEventLatencySeconds"] as? Double {
            expect(latency >= 0, "latency should be non-negative")
            expect(latency < 10, "latency should be within timeout: \(latency)")
            print("  dispatch latency: \(String(format: "%.6f", latency))s")
        } else {
            expect(false, "latency should be present when event received")
        }

        expect((json["callbackCount"] as? Int ?? 0) >= 1, "callbackCount should be >= 1")
        expect(json["timeoutExpired"] as? Bool == false, "timeout should not have expired")
    }

    // MARK: - Test: fsevents event receipt

    private func testFSEventsEventReceipt() throws {
        let r = try runProbe(args: ["--candidate", "fsevents", "--items", "5", "--timeout", "10"], timeoutSeconds: 30)
        expect(r.exitCode == 0, "fsevents event receipt should exit 0")
        guard let json = parseJSON(r.stdout) else {
            expect(false, "fsevents event receipt should produce valid JSON")
            return
        }
        expect(json["firstEventReceived"] as? Bool == true, "fsevents should receive the marker event")
        expect(json["markerCreated"] as? Bool == true, "marker should be created")

        if let latency = json["firstEventLatencySeconds"] as? Double {
            expect(latency >= 0, "latency should be non-negative")
            expect(latency < 10, "latency should be within timeout: \(latency)")
            print("  fsevents latency: \(String(format: "%.6f", latency))s")
        } else {
            expect(false, "latency should be present when event received")
        }

        expect((json["callbackCount"] as? Int ?? 0) >= 1, "callbackCount should be >= 1")
        expect((json["callbackBatchCount"] as? Int ?? 0) >= 1, "callbackBatchCount should be >= 1")
        expect(json["callbackCount"] as? Int == json["callbackBatchCount"] as? Int,
               "fsevents callbackCount should equal callbackBatchCount")
        expect((json["recordCount"] as? Int ?? 0) >= (json["callbackCount"] as? Int ?? Int.max),
               "fsevents recordCount should be >= callbackCount")
    }

    // MARK: - Test: descriptor accounting

    private func testDescriptorAccounting() throws {
        for candidate in ["dispatch", "fsevents"] {
            let r = try runProbe(args: ["--candidate", candidate, "--items", "5", "--timeout", "10"], timeoutSeconds: 30)
            expect(r.exitCode == 0, "\(candidate) descriptor test should exit 0")
            guard let json = parseJSON(r.stdout) else {
                expect(false, "\(candidate) descriptor test should produce JSON")
                continue
            }

            guard let preStart = json["preStartDescriptorCount"] as? Int,
                  let postTeardown = json["postTeardownDescriptorCount"] as? Int,
                  let delta = json["descriptorDeltaFromPreStart"] as? Int,
                  let settleDuration = json["descriptorSettleDurationSeconds"] as? Double,
                  let returnedToBaseline = json["descriptorReturnedToBaseline"] as? Bool else {
                expect(false, "\(candidate) descriptor fields should be integers")
                continue
            }

            expect(preStart >= 0, "\(candidate) preStart descriptor count should be non-negative")
            expect(postTeardown >= 0, "\(candidate) postTeardown descriptor count should be non-negative")
            expect(delta == postTeardown - preStart, "\(candidate) descriptor delta math should be consistent")
            expect(settleDuration >= 0 && settleDuration <= 2.1,
                   "\(candidate) descriptor settle duration should be bounded")
            expect(returnedToBaseline == (delta == 0),
                   "\(candidate) descriptor baseline flag should match delta")
            expect(returnedToBaseline, "\(candidate) descriptors should return to local baseline")
            print("  \(candidate) descriptors: pre=\(preStart), post=\(postTeardown), delta=\(delta)")
        }
    }

    // MARK: - Test: resource metrics

    private func testResourceMetrics() throws {
        let r = try runProbe(args: ["--candidate", "dispatch", "--items", "5", "--timeout", "10"], timeoutSeconds: 30)
        expect(r.exitCode == 0, "resource metrics test should exit 0")
        guard let json = parseJSON(r.stdout) else {
            expect(false, "resource metrics should produce JSON")
            return
        }

        guard let preCPU = json["preStartCPU"] as? [String: Double],
              let postCPU = json["postStopCPU"] as? [String: Double] else {
            expect(false, "CPU fields should be dictionaries")
            return
        }

        expect((preCPU["userSec"] ?? -1) >= 0, "preStart CPU user should be >= 0")
        expect((preCPU["systemSec"] ?? -1) >= 0, "preStart CPU system should be >= 0")
        expect((postCPU["userSec"] ?? -1) >= 0, "postStop CPU user should be >= 0")
        expect((postCPU["systemSec"] ?? -1) >= 0, "postStop CPU system should be >= 0")

        guard let preRSS = json["preStartMaxRSSBytes"] as? Int64,
              let postRSS = json["postStopMaxRSSBytes"] as? Int64 else {
            expect(false, "RSS fields should be integers")
            return
        }
        expect(preRSS > 0, "preStart max RSS should be positive")
        expect(postRSS > 0, "postStop max RSS should be positive")
    }

    // MARK: - Test: cleanup verification

    private func testCleanupVerification() throws {
        let r = try runProbe(args: ["--candidate", "dispatch", "--items", "5", "--timeout", "10"], timeoutSeconds: 30)
        expect(r.exitCode == 0, "cleanup test should exit 0")
        guard let json = parseJSON(r.stdout) else {
            expect(false, "cleanup test should produce JSON")
            return
        }
        expect(json["cleanupOK"] as? Bool == true, "cleanup should succeed")
        expect(r.childTempWasEmpty, "probe should remove its own fixture before parent cleanup")
        expect(!r.outerWatchdogExpired, "cleanup probe should finish before outer watchdog")
    }

    private func testRuntimeEventTimeout() throws {
        let r = try runProbe(
            args: ["--candidate", "fsevents", "--items", "5", "--timeout", "0.001"],
            timeoutSeconds: 10
        )
        expect(r.exitCode == 1, "runtime event timeout should exit 1, got \(r.exitCode)")
        expect(r.stderr.contains("Timed out waiting for fsevents marker evidence"),
               "runtime timeout should report the typed event timeout")
        expect(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               "failed probe should not emit success JSON")
        expect(!r.outerWatchdogExpired, "probe timeout should complete before outer watchdog")
        expect(r.childTempWasEmpty, "timed-out probe should remove its own fixture")
    }

    private func testOuterWatchdog() throws {
        let r = try runProbe(
            args: ["--candidate", "fsevents", "--items", "5", "--timeout", "120"],
            timeoutSeconds: 0.05
        )
        expect(r.outerWatchdogExpired, "outer watchdog should expire before FSEvents delivery")
        expect(r.exitCode != 0, "watchdog-terminated probe should not report success")
    }

    // MARK: - Test: fsevents bridge failure count

    private func testFSEventsBridgeFailure() throws {
        let r = try runProbe(args: ["--candidate", "fsevents", "--items", "5", "--timeout", "10"], timeoutSeconds: 30)
        expect(r.exitCode == 0, "bridge failure test should exit 0")
        guard let json = parseJSON(r.stdout) else {
            expect(false, "bridge failure test should produce JSON")
            return
        }
        if let bridgeFailures = json["bridgeFailureCount"] as? Int {
            expect(bridgeFailures == 0, "bridge failure count should be 0, got \(bridgeFailures)")
        } else {
            expect(false, "bridgeFailureCount should be present for fsevents")
        }
    }
}

// MARK: - Entry point

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: comparison-tests <probe-binary>\n", stderr)
    exit(64)
}

let probeBinary = args[1]
guard FileManager.default.fileExists(atPath: probeBinary) else {
    fputs("Error: probe binary not found: \(probeBinary)\n", stderr)
    exit(1)
}

let exitCode = MainActor.assumeIsolated {
    TestHarness(probeBinary: probeBinary).run()
}
exit(exitCode)
