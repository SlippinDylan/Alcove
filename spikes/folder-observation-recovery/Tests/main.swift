import Darwin
import Dispatch
import Foundation

private enum HarnessError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let value): return value } }
}

private struct FileIdentity: Decodable, Equatable {
    let device: UInt64
    let inode: UInt64
}

private struct StartFailure: Decodable {
    let category: String
    let code: Int32
}

private struct StepEvidence: Decodable {
    let name: String
    let required: Bool
    let received: Bool
    let latencySeconds: Double?
    let flags: String?
    let path: String?
    let expectedPath: String?
}

private struct ScenarioResult: Decodable {
    let candidate: String
    let scenario: String
    let timeoutSeconds: Double
    let observerStarted: Bool
    let startFailure: StartFailure?
    let observedIdentity: FileIdentity?
    let initialIdentity: FileIdentity?
    let movedIdentity: FileIdentity?
    let replacementIdentity: FileIdentity?
    let targetIdentity: FileIdentity?
    let steps: [StepEvidence]
    let bridgeFailureCount: Int?
    let teardownState: String
    let cleanupOK: Bool
}

@MainActor
private final class TestHarness {
    private struct ProbeOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let outerWatchdogExpired: Bool
        let childTempWasEmpty: Bool
    }

    private let probeBinary: String
    private var passed = 0
    private var failed = 0
    private var failures: [String] = []

    init(probeBinary: String) { self.probeBinary = probeBinary }

    func run() -> Int32 {
        runTest("invalid arguments", testInvalidArguments)
        runTest("ten-scenario real-filesystem matrix", testScenarioMatrix)
        runTest("runtime event timeout is typed and cleans up", testRuntimeTimeout)
        runTest("outer watchdog terminates stalled probe", testOuterWatchdog)
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
        else { failed += 1; failures.append("FAIL: \(message)") }
    }

    private func runProbe(args: [String], timeoutSeconds: Double = 60) throws -> ProbeOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: probeBinary)
        process.arguments = args
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let childTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("alcove-recovery-child-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: childTemp, withIntermediateDirectories: false)
        var environment = ProcessInfo.processInfo.environment
        environment["TMPDIR"] = childTemp.path + "/"
        process.environment = environment

        let execution: Result<(Int32, String, String, Bool), Error>
        do {
            try process.run()
            waitForExit(process, deadline: .now() + .milliseconds(Int(timeoutSeconds * 1_000)), interval: 50_000)
            let watchdogExpired = process.isRunning
            if process.isRunning {
                process.terminate()
                waitForExit(process, deadline: .now() + .seconds(2), interval: 10_000)
                if process.isRunning {
                    guard Darwin.kill(process.processIdentifier, SIGKILL) == 0 else {
                        throw HarnessError.message("SIGKILL failed: errno \(errno)")
                    }
                    waitForExit(process, deadline: .now() + .seconds(2), interval: 10_000)
                    guard !process.isRunning else {
                        outputPipe.fileHandleForReading.closeFile()
                        errorPipe.fileHandleForReading.closeFile()
                        throw HarnessError.message("probe remained alive after SIGKILL")
                    }
                }
            }
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errors = errorPipe.fileHandleForReading.readDataToEndOfFile()
            execution = .success((
                process.terminationStatus,
                String(data: output, encoding: .utf8) ?? "",
                String(data: errors, encoding: .utf8) ?? "",
                watchdogExpired
            ))
        } catch { execution = .failure(error) }

        let inspection: Result<Bool, Error>
        do {
            let children = try FileManager.default.contentsOfDirectory(
                at: childTemp,
                includingPropertiesForKeys: nil
            )
            inspection = .success(children.isEmpty)
        } catch { inspection = .failure(error) }

        let cleanup: Result<Void, Error>
        do { try FileManager.default.removeItem(at: childTemp); cleanup = .success(()) }
        catch { cleanup = .failure(error) }

        switch (execution, inspection, cleanup) {
        case (.success(let raw), .success(let empty), .success):
            return ProbeOutput(
                exitCode: raw.0, stdout: raw.1, stderr: raw.2,
                outerWatchdogExpired: raw.3, childTempWasEmpty: empty
            )
        case (.failure(let primary), _, .failure(let cleanupError)):
            throw HarnessError.message("probe: \(primary); cleanup: \(cleanupError)")
        case (.failure(let primary), _, .success): throw primary
        case (.success, .failure(let inspectError), .failure(let cleanupError)):
            throw HarnessError.message("inspection: \(inspectError); cleanup: \(cleanupError)")
        case (.success, .failure(let inspectError), .success): throw inspectError
        case (.success, .success, .failure(let cleanupError)): throw cleanupError
        }
    }

    private func waitForExit(_ process: Process, deadline: DispatchTime, interval: useconds_t) {
        while process.isRunning && DispatchTime.now() < deadline { usleep(interval) }
    }

    private func decode(_ output: ProbeOutput, label: String) -> ScenarioResult? {
        guard let data = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            expect(false, "\(label) output must be UTF-8")
            return nil
        }
        do { return try JSONDecoder().decode(ScenarioResult.self, from: data) }
        catch {
            expect(false, "\(label) must match strict JSON schema: \(error)")
            return nil
        }
    }

    private func testInvalidArguments() throws {
        let cases = [
            [],
            ["--candidate", "bad", "--scenario", "missing-root", "--timeout", "5"],
            ["--candidate", "dispatch", "--scenario", "bad", "--timeout", "5"],
            ["--candidate", "dispatch", "--scenario", "missing-root", "--timeout", "0"]
        ]
        for arguments in cases {
            let output = try runProbe(args: arguments, timeoutSeconds: 5)
            expect(output.exitCode == 64, "invalid arguments must exit 64")
            expect(output.stdout.isEmpty, "invalid arguments must not emit JSON")
            expect(!output.stderr.isEmpty, "invalid arguments must explain the error")
            expect(!output.outerWatchdogExpired, "invalid arguments must exit before watchdog")
            expect(output.childTempWasEmpty, "invalid arguments must not leave a fixture")
        }
    }

    private func testScenarioMatrix() throws {
        let candidates = ["dispatch", "fsevents"]
        let scenarios = ["missing-root", "symlink-root", "child-symlink", "root-rename", "path-replacement"]
        for candidate in candidates {
            for scenario in scenarios {
                let label = "\(candidate)/\(scenario)"
                let output = try runProbe(
                    args: ["--candidate", candidate, "--scenario", scenario, "--timeout", "5"],
                    timeoutSeconds: 15
                )
                expect(output.exitCode == 0, "\(label) must exit 0, got \(output.exitCode)")
                expect(output.stderr.isEmpty, "\(label) stderr must be empty")
                expect(!output.outerWatchdogExpired, "\(label) must finish before watchdog")
                expect(output.childTempWasEmpty, "\(label) probe must remove its fixture")
                guard let result = decode(output, label: label) else { continue }
                validateCommon(result, candidate: candidate, scenario: scenario)
                validateScenario(result)
            }
        }
    }

    private func validateCommon(_ result: ScenarioResult, candidate: String, scenario: String) {
        expect(result.candidate == candidate, "\(candidate)/\(scenario) candidate mismatch")
        expect(result.scenario == scenario, "\(candidate)/\(scenario) scenario mismatch")
        expect(result.timeoutSeconds == 5, "\(candidate)/\(scenario) timeout mismatch")
        expect(result.cleanupOK, "\(candidate)/\(scenario) cleanup must succeed")
        expect(Set(result.steps.map(\.name)).count == result.steps.count,
               "\(candidate)/\(scenario) step names must be unique")

        if scenario == "missing-root" {
            expect(!result.observerStarted, "\(candidate) missing root must not start")
            expect(result.teardownState == "notStarted", "\(candidate) missing root teardown state")
            expect(result.steps.isEmpty, "\(candidate) missing root must have no event steps")
            expect(result.bridgeFailureCount == nil, "\(candidate) missing root bridge count is N/A")
        } else {
            expect(result.observerStarted, "\(candidate)/\(scenario) observer must start")
            expect(result.startFailure == nil, "\(candidate)/\(scenario) startFailure must be nil")
            expect(result.teardownState == "stopped", "\(candidate)/\(scenario) teardown must stop")
            if candidate == "fsevents" {
                expect(result.bridgeFailureCount == 0, "\(candidate)/\(scenario) bridge failures must be zero")
            } else {
                expect(result.bridgeFailureCount == nil, "Dispatch bridge count is N/A")
            }
        }

        for step in result.steps {
            if step.required { expect(step.received, "\(candidate)/\(scenario)/\(step.name) required evidence missing") }
            expect((step.latencySeconds != nil) == step.received,
                   "\(candidate)/\(scenario)/\(step.name) latency presence must match receipt")
            if let latency = step.latencySeconds {
                expect(latency >= 0 && latency <= result.timeoutSeconds,
                       "\(candidate)/\(scenario)/\(step.name) latency must be bounded")
            }
            expect((step.flags != nil) == step.received,
                   "\(candidate)/\(scenario)/\(step.name) flags presence must match receipt")
            if candidate == "fsevents", step.received, let expectedPath = step.expectedPath {
                guard let deliveredPath = step.path else {
                    expect(false, "\(candidate)/\(scenario)/\(step.name) delivered path is missing")
                    continue
                }
                expect(canonicalPath(deliveredPath) == canonicalPath(expectedPath),
                       "\(candidate)/\(scenario)/\(step.name) delivered path must match its marker")
            }
        }
    }

    private func validateScenario(_ result: ScenarioResult) {
        switch result.scenario {
        case "missing-root":
            guard let failure = result.startFailure else {
                expect(false, "\(result.candidate) missing root must have typed failure")
                return
            }
            expect(failure.code == ENOENT, "\(result.candidate) missing root errno must be ENOENT")
            let expected = result.candidate == "dispatch" ? "openFailed" : "pathNotFound"
            expect(failure.category == expected, "\(result.candidate) missing root category must be \(expected)")
        case "symlink-root":
            expectStepNames(result, expected: ["target-marker"])
            expect(result.targetIdentity != nil, "symlink target identity must be present")
            if result.candidate == "dispatch" {
                expect(result.observedIdentity == result.targetIdentity,
                       "Dispatch symlink root must observe target identity")
            }
        case "child-symlink":
            expectStepNames(result, expected: ["child-symlink-created", "external-target-marker"])
            if result.candidate == "fsevents", let first = step(named: "child-symlink-created", in: result) {
                expect(first.flags?.contains("ItemIsSymlink") == true,
                       "FSEvents child creation must identify a symlink record")
            }
        case "root-rename":
            expectStepNames(result, expected: ["root-renamed", "moved-root-marker"])
            expect(result.initialIdentity == result.movedIdentity, "rename must preserve inode identity")
            if let first = step(named: "root-renamed", in: result) {
                let expected = result.candidate == "dispatch" ? "rename" : "RootChanged"
                expect(first.flags?.contains(expected) == true, "root rename must carry \(expected)")
            }
            if result.candidate == "dispatch", let movedMarker = step(named: "moved-root-marker", in: result) {
                expect(movedMarker.received, "DispatchSource must observe moved-inode marker locally")
            }
        case "path-replacement":
            expectStepNames(result, expected: ["root-moved", "old-inode-marker", "replacement-marker"])
            expect(result.initialIdentity == result.movedIdentity, "moved original identity must be preserved")
            expect(result.initialIdentity != result.replacementIdentity, "replacement must have a distinct identity")
            if result.candidate == "dispatch" {
                expect(result.observedIdentity == result.initialIdentity,
                       "Dispatch observed identity must equal initial identity")
                if let old = step(named: "old-inode-marker", in: result) {
                    expect(old.received, "Dispatch must observe old-inode marker locally")
                }
            }
        default:
            expect(false, "unexpected scenario \(result.scenario)")
        }
    }

    private func expectStepNames(_ result: ScenarioResult, expected: [String]) {
        expect(result.steps.map(\.name) == expected,
               "\(result.candidate)/\(result.scenario) step sequence mismatch")
    }

    private func step(named name: String, in result: ScenarioResult) -> StepEvidence? {
        result.steps.first { $0.name == name }
    }

    private func canonicalPath(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized == "/private/var" { return "/var" }
        if standardized.hasPrefix("/private/var/") { return String(standardized.dropFirst(8)) }
        return standardized
    }

    private func testRuntimeTimeout() throws {
        let output = try runProbe(
            args: ["--candidate", "fsevents", "--scenario", "symlink-root", "--timeout", "0.001"],
            timeoutSeconds: 10
        )
        expect(output.exitCode == 1, "runtime timeout must exit 1")
        expect(output.stdout.isEmpty, "runtime timeout must not emit success JSON")
        expect(output.stderr.contains("Timed out waiting for required evidence: target-marker"),
               "runtime timeout must report the typed step")
        expect(!output.outerWatchdogExpired, "runtime timeout must precede outer watchdog")
        expect(output.childTempWasEmpty, "runtime timeout probe must remove its fixture")
    }

    private func testOuterWatchdog() throws {
        let output = try runProbe(
            args: ["--candidate", "fsevents", "--scenario", "symlink-root", "--timeout", "120"],
            timeoutSeconds: 0.05
        )
        expect(output.outerWatchdogExpired, "outer watchdog must expire")
        expect(output.exitCode != 0, "watchdog-terminated probe must not report success")
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: recovery-tests <probe-binary>\n", stderr)
    Darwin.exit(64)
}
let probeBinary = arguments[1]
guard FileManager.default.fileExists(atPath: probeBinary) else {
    fputs("Error: probe binary not found: \(probeBinary)\n", stderr)
    Darwin.exit(1)
}
let exitCode = MainActor.assumeIsolated { TestHarness(probeBinary: probeBinary).run() }
Darwin.exit(exitCode)
