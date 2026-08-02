import CoreServices
import Darwin
import Dispatch
import Foundation

private enum Candidate: String, Codable, Sendable {
    case dispatch
    case fsevents
}

private enum Scenario: String, Codable, CaseIterable, Sendable {
    case missingRoot = "missing-root"
    case symlinkRoot = "symlink-root"
    case childSymlink = "child-symlink"
    case rootRename = "root-rename"
    case pathReplacement = "path-replacement"
}

private struct FileIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

private struct StartFailure: Codable, Sendable {
    let category: String
    let code: Int32
}

private struct StepEvidence: Codable, Sendable {
    let name: String
    let required: Bool
    let received: Bool
    let latencySeconds: Double?
    let flags: String?
    let path: String?
    let expectedPath: String?
}

private struct ScenarioResult: Codable, Sendable {
    let candidate: Candidate
    let scenario: Scenario
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
    var cleanupOK: Bool
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case filesystem(String)
    case unexpectedStartError(String)
    case eventTimedOut(String)
    case teardown(String)
    case cleanup(String)
    case combined(primary: String, secondary: String)

    var description: String {
        switch self {
        case .invalidArguments(let message): return message
        case .filesystem(let message): return "Filesystem error: \(message)"
        case .unexpectedStartError(let message): return "Unexpected start error: \(message)"
        case .eventTimedOut(let step): return "Timed out waiting for required evidence: \(step)"
        case .teardown(let message): return "Teardown error: \(message)"
        case .cleanup(let message): return "Cleanup error: \(message)"
        case .combined(let primary, let secondary):
            return "Primary error: \(primary); secondary error: \(secondary)"
        }
    }
}

private struct ObserverEvent: Sendable {
    let rawFlags: UInt64
    let flags: String
    let path: String?
}

private final class EvidenceToken: @unchecked Sendable {
    let id = UUID()
    let name: String
    let required: Bool
    let expectedPath: String?
    let requiredFlags: UInt64
    private let start = DispatchTime.now().uptimeNanoseconds
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var isClosed = false
    private var event: ObserverEvent?
    private var latency: Double?

    init(name: String, required: Bool, expectedPath: String?, requiredFlags: UInt64) {
        self.name = name
        self.required = required
        self.expectedPath = expectedPath.map(Self.canonicalPath)
        self.requiredFlags = requiredFlags
    }

    func accept(_ candidate: ObserverEvent) {
        let shouldSignal = lock.withLock {
            guard !isClosed, event == nil else { return false }
            if requiredFlags != 0, candidate.rawFlags & requiredFlags == 0 { return false }
            if let expectedPath {
                guard let path = candidate.path,
                      Self.canonicalPath(path) == expectedPath else { return false }
            }
            event = candidate
            latency = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            return true
        }
        if shouldSignal { semaphore.signal() }
    }

    func wait(seconds: Double) -> Bool {
        semaphore.wait(timeout: .now() + .milliseconds(Int(seconds * 1_000))) == .success
    }

    func close() { lock.withLock { isClosed = true } }

    func evidence() -> StepEvidence {
        lock.withLock {
            StepEvidence(
                name: name,
                required: required,
                received: event != nil,
                latencySeconds: latency,
                flags: event?.flags,
                path: event?.path,
                expectedPath: expectedPath
            )
        }
    }

    private static func canonicalPath(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized == "/private/var" { return "/var" }
        if standardized.hasPrefix("/private/var/") { return String(standardized.dropFirst(8)) }
        return standardized
    }
}

private final class EvidenceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active: EvidenceToken?

    func arm(name: String, required: Bool, expectedPath: String?, requiredFlags: UInt64) -> EvidenceToken {
        let token = EvidenceToken(
            name: name,
            required: required,
            expectedPath: expectedPath,
            requiredFlags: requiredFlags
        )
        lock.withLock { active = token }
        return token
    }

    func record(_ event: ObserverEvent) {
        let token = lock.withLock { active }
        token?.accept(event)
    }

    func disarm(_ token: EvidenceToken) {
        lock.withLock {
            if active?.id == token.id { active = nil }
        }
    }
}

private final class CandidateObserver: @unchecked Sendable {
    private let candidate: Candidate
    private let dispatchObserver: DispatchSourceFolderObserver?
    private let fseventsObserver: FSEventsFolderObserver?

    init(candidate: Candidate, gate: EvidenceGate) {
        self.candidate = candidate
        switch candidate {
        case .dispatch:
            dispatchObserver = DispatchSourceFolderObserver { record in
                gate.record(ObserverEvent(
                    rawFlags: UInt64(record.rawEventMask),
                    flags: record.eventDescription,
                    path: nil
                ))
            }
            fseventsObserver = nil
        case .fsevents:
            dispatchObserver = nil
            fseventsObserver = FSEventsFolderObserver { record in
                gate.record(ObserverEvent(
                    rawFlags: UInt64(record.rawFlags),
                    flags: record.flagDescription,
                    path: record.path
                ))
            }
        }
    }

    func start(path: String) throws {
        switch candidate {
        case .dispatch:
            guard let dispatchObserver else { throw ProbeError.unexpectedStartError("missing DispatchSource observer") }
            try dispatchObserver.start(path: path)
        case .fsevents:
            guard let fseventsObserver else { throw ProbeError.unexpectedStartError("missing FSEvents observer") }
            try fseventsObserver.start(path: path)
        }
    }

    var observedIdentity: FileIdentity? {
        guard let identity = dispatchObserver?.observedFileIdentity else { return nil }
        return FileIdentity(device: identity.device, inode: identity.inode)
    }

    var bridgeFailureCount: Int? { fseventsObserver?.bridgeFailureCount }

    func stopAndWait() throws {
        switch candidate {
        case .dispatch:
            guard let observer = dispatchObserver else { throw ProbeError.teardown("missing DispatchSource observer") }
            let result = try observer.stopAndWait(timeout: .now() + 3)
            guard result.descriptorWasOpened, result.descriptorWasClosed else {
                throw ProbeError.teardown("DispatchSource descriptor did not close")
            }
        case .fsevents:
            guard let observer = fseventsObserver else { throw ProbeError.teardown("missing FSEvents observer") }
            let state = try observer.stopAndWait(timeout: .now() + 3)
            guard state == .stopped else { throw ProbeError.teardown("FSEvents state is \(state)") }
        }
    }
}

private func fileIdentity(at path: String) throws -> FileIdentity {
    var metadata = stat()
    guard Darwin.lstat(path, &metadata) == 0 else {
        throw ProbeError.filesystem("stat \(path): errno \(errno)")
    }
    return FileIdentity(device: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino))
}

private func createDirectory(_ url: URL) throws {
    do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
    catch { throw ProbeError.filesystem("create directory \(url.path): \(error)") }
}

private func createSymlink(_ url: URL, target: URL) throws {
    do { try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target) }
    catch { throw ProbeError.filesystem("create symlink \(url.path): \(error)") }
}

private func move(_ source: URL, to destination: URL) throws {
    do { try FileManager.default.moveItem(at: source, to: destination) }
    catch { throw ProbeError.filesystem("move \(source.path) to \(destination.path): \(error)") }
}

private func createFile(_ url: URL) throws {
    let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw ProbeError.filesystem("open \(url.path): errno \(errno)") }
    guard Darwin.close(descriptor) == 0 else {
        throw ProbeError.filesystem("close \(url.path): errno \(errno)")
    }
}

private func removeFixture(_ url: URL) throws {
    do { try FileManager.default.removeItem(at: url) }
    catch { throw ProbeError.cleanup("\(url.path): \(error)") }
}

private func runWindow(
    gate: EvidenceGate,
    name: String,
    required: Bool,
    expectedPath: String?,
    requiredFlags: UInt64,
    timeoutSeconds: Double,
    mutation: () throws -> Void
) throws -> StepEvidence {
    let token = gate.arm(
        name: name,
        required: required,
        expectedPath: expectedPath,
        requiredFlags: requiredFlags
    )
    do {
        try mutation()
    } catch {
        token.close()
        gate.disarm(token)
        throw error
    }
    let received = token.wait(seconds: required ? timeoutSeconds : min(timeoutSeconds, 0.75))
    token.close()
    gate.disarm(token)
    let evidence = token.evidence()
    if required, !received { throw ProbeError.eventTimedOut(name) }
    return evidence
}

private func quietPreviousDelivery() { usleep(400_000) }

private func withStartedObserver<T>(
    candidate: Candidate,
    path: String,
    gate: EvidenceGate,
    body: (CandidateObserver) throws -> T
) throws -> T {
    let observer = CandidateObserver(candidate: candidate, gate: gate)
    try observer.start(path: path)
    do {
        let value = try body(observer)
        try observer.stopAndWait()
        return value
    } catch {
        do { try observer.stopAndWait() }
        catch let teardownError {
            throw ProbeError.combined(primary: String(describing: error), secondary: String(describing: teardownError))
        }
        throw error
    }
}

private func missingRootResult(
    candidate: Candidate,
    path: String,
    timeout: Double
) throws -> ScenarioResult {
    let gate = EvidenceGate()
    let observer = CandidateObserver(candidate: candidate, gate: gate)
    let failure: StartFailure
    do {
        try observer.start(path: path)
        do { try observer.stopAndWait() }
        catch { throw ProbeError.combined(primary: "missing root unexpectedly started", secondary: String(describing: error)) }
        throw ProbeError.unexpectedStartError("missing root unexpectedly started")
    } catch FolderObserverError.openFailed(_, let code) where candidate == .dispatch {
        failure = StartFailure(category: "openFailed", code: code)
    } catch FSEventError.pathNotFound(_, let code) where candidate == .fsevents {
        failure = StartFailure(category: "pathNotFound", code: code)
    } catch let error as ProbeError {
        throw error
    } catch {
        throw ProbeError.unexpectedStartError(String(describing: error))
    }
    return ScenarioResult(
        candidate: candidate, scenario: .missingRoot, timeoutSeconds: timeout,
        observerStarted: false, startFailure: failure, observedIdentity: nil,
        initialIdentity: nil, movedIdentity: nil, replacementIdentity: nil,
        targetIdentity: nil, steps: [], bridgeFailureCount: nil,
        teardownState: "notStarted", cleanupOK: false
    )
}

private func symlinkRootResult(candidate: Candidate, root: URL, timeout: Double) throws -> ScenarioResult {
    let target = root.appendingPathComponent("target")
    let link = root.appendingPathComponent("link")
    try createDirectory(target)
    try createSymlink(link, target: target)
    let targetIdentity = try fileIdentity(at: target.path)
    let marker = target.appendingPathComponent("marker-\(UUID().uuidString)")
    let gate = EvidenceGate()
    var observed: FileIdentity?
    var bridge: Int?
    let steps = try withStartedObserver(candidate: candidate, path: link.path, gate: gate) { observer in
        observed = observer.observedIdentity
        let step = try runWindow(
            gate: gate, name: "target-marker", required: true,
            expectedPath: candidate == .fsevents ? marker.path : nil,
            requiredFlags: candidate == .dispatch
                ? UInt64(DispatchSource.FileSystemEvent.write.rawValue)
                : UInt64(kFSEventStreamEventFlagItemCreated),
            timeoutSeconds: timeout
        ) { try createFile(marker) }
        bridge = observer.bridgeFailureCount
        return [step]
    }
    return ScenarioResult(
        candidate: candidate, scenario: .symlinkRoot, timeoutSeconds: timeout,
        observerStarted: true, startFailure: nil, observedIdentity: observed,
        initialIdentity: nil, movedIdentity: nil, replacementIdentity: nil,
        targetIdentity: targetIdentity, steps: steps, bridgeFailureCount: bridge,
        teardownState: "stopped", cleanupOK: false
    )
}

private func childSymlinkResult(candidate: Candidate, root: URL, timeout: Double) throws -> ScenarioResult {
    let observedRoot = root.appendingPathComponent("observed")
    let external = root.appendingPathComponent("external")
    try createDirectory(observedRoot)
    try createDirectory(external)
    let link = observedRoot.appendingPathComponent("external-link")
    let externalMarker = external.appendingPathComponent("marker-\(UUID().uuidString)")
    let gate = EvidenceGate()
    var bridge: Int?
    let steps = try withStartedObserver(candidate: candidate, path: observedRoot.path, gate: gate) { observer in
        let created = try runWindow(
            gate: gate, name: "child-symlink-created", required: true,
            expectedPath: nil,
            requiredFlags: candidate == .dispatch
                ? UInt64(DispatchSource.FileSystemEvent.write.rawValue)
                : UInt64(kFSEventStreamEventFlagItemIsSymlink),
            timeoutSeconds: timeout
        ) { try createSymlink(link, target: external) }
        quietPreviousDelivery()
        let externalMutation = try runWindow(
            gate: gate, name: "external-target-marker", required: false,
            expectedPath: candidate == .fsevents ? externalMarker.path : nil,
            requiredFlags: candidate == .dispatch ? UInt64(DispatchSource.FileSystemEvent.write.rawValue) : 0,
            timeoutSeconds: timeout
        ) { try createFile(externalMarker) }
        bridge = observer.bridgeFailureCount
        return [created, externalMutation]
    }
    return ScenarioResult(
        candidate: candidate, scenario: .childSymlink, timeoutSeconds: timeout,
        observerStarted: true, startFailure: nil, observedIdentity: nil,
        initialIdentity: nil, movedIdentity: nil, replacementIdentity: nil,
        targetIdentity: nil, steps: steps, bridgeFailureCount: bridge,
        teardownState: "stopped", cleanupOK: false
    )
}

private func rootRenameResult(candidate: Candidate, root: URL, timeout: Double) throws -> ScenarioResult {
    let original = root.appendingPathComponent("original")
    let moved = root.appendingPathComponent("moved")
    try createDirectory(original)
    let initialIdentity = try fileIdentity(at: original.path)
    let marker = moved.appendingPathComponent("marker-\(UUID().uuidString)")
    let gate = EvidenceGate()
    var bridge: Int?
    let steps = try withStartedObserver(candidate: candidate, path: original.path, gate: gate) { observer in
        let renamed = try runWindow(
            gate: gate, name: "root-renamed", required: true,
            expectedPath: nil,
            requiredFlags: candidate == .dispatch
                ? UInt64(DispatchSource.FileSystemEvent.rename.rawValue)
                : UInt64(kFSEventStreamEventFlagRootChanged),
            timeoutSeconds: timeout
        ) { try move(original, to: moved) }
        quietPreviousDelivery()
        let markerStep = try runWindow(
            gate: gate, name: "moved-root-marker", required: false,
            expectedPath: candidate == .fsevents ? marker.path : nil,
            requiredFlags: candidate == .dispatch ? UInt64(DispatchSource.FileSystemEvent.write.rawValue) : 0,
            timeoutSeconds: timeout
        ) { try createFile(marker) }
        bridge = observer.bridgeFailureCount
        return [renamed, markerStep]
    }
    return ScenarioResult(
        candidate: candidate, scenario: .rootRename, timeoutSeconds: timeout,
        observerStarted: true, startFailure: nil, observedIdentity: nil,
        initialIdentity: initialIdentity, movedIdentity: try fileIdentity(at: moved.path),
        replacementIdentity: nil, targetIdentity: nil, steps: steps,
        bridgeFailureCount: bridge, teardownState: "stopped", cleanupOK: false
    )
}

private func pathReplacementResult(candidate: Candidate, root: URL, timeout: Double) throws -> ScenarioResult {
    let original = root.appendingPathComponent("original")
    let moved = root.appendingPathComponent("moved")
    try createDirectory(original)
    let initialIdentity = try fileIdentity(at: original.path)
    let oldMarker = moved.appendingPathComponent("old-marker-\(UUID().uuidString)")
    let replacementMarker = original.appendingPathComponent("new-marker-\(UUID().uuidString)")
    let gate = EvidenceGate()
    var observed: FileIdentity?
    var bridge: Int?
    let steps = try withStartedObserver(candidate: candidate, path: original.path, gate: gate) { observer in
        observed = observer.observedIdentity
        let movedStep = try runWindow(
            gate: gate, name: "root-moved", required: true,
            expectedPath: nil,
            requiredFlags: candidate == .dispatch
                ? UInt64(DispatchSource.FileSystemEvent.rename.rawValue)
                : UInt64(kFSEventStreamEventFlagRootChanged),
            timeoutSeconds: timeout
        ) { try move(original, to: moved) }
        try createDirectory(original)
        quietPreviousDelivery()
        let oldStep = try runWindow(
            gate: gate, name: "old-inode-marker", required: candidate == .dispatch,
            expectedPath: candidate == .fsevents ? oldMarker.path : nil,
            requiredFlags: candidate == .dispatch ? UInt64(DispatchSource.FileSystemEvent.write.rawValue) : 0,
            timeoutSeconds: timeout
        ) { try createFile(oldMarker) }
        quietPreviousDelivery()
        let replacementStep = try runWindow(
            gate: gate, name: "replacement-marker", required: false,
            expectedPath: candidate == .fsevents ? replacementMarker.path : nil,
            requiredFlags: candidate == .dispatch ? UInt64(DispatchSource.FileSystemEvent.write.rawValue) : 0,
            timeoutSeconds: timeout
        ) { try createFile(replacementMarker) }
        bridge = observer.bridgeFailureCount
        return [movedStep, oldStep, replacementStep]
    }
    return ScenarioResult(
        candidate: candidate, scenario: .pathReplacement, timeoutSeconds: timeout,
        observerStarted: true, startFailure: nil, observedIdentity: observed,
        initialIdentity: initialIdentity, movedIdentity: try fileIdentity(at: moved.path),
        replacementIdentity: try fileIdentity(at: original.path), targetIdentity: nil,
        steps: steps, bridgeFailureCount: bridge, teardownState: "stopped", cleanupOK: false
    )
}

private func runScenario(candidate: Candidate, scenario: Scenario, timeout: Double) throws -> ScenarioResult {
    let fixture = FileManager.default.temporaryDirectory
        .appendingPathComponent("alcove-recovery-\(UUID().uuidString)")
    try createDirectory(fixture)
    do {
        var result: ScenarioResult
        switch scenario {
        case .missingRoot:
            result = try missingRootResult(
                candidate: candidate,
                path: fixture.appendingPathComponent("missing").path,
                timeout: timeout
            )
        case .symlinkRoot: result = try symlinkRootResult(candidate: candidate, root: fixture, timeout: timeout)
        case .childSymlink: result = try childSymlinkResult(candidate: candidate, root: fixture, timeout: timeout)
        case .rootRename: result = try rootRenameResult(candidate: candidate, root: fixture, timeout: timeout)
        case .pathReplacement: result = try pathReplacementResult(candidate: candidate, root: fixture, timeout: timeout)
        }
        try removeFixture(fixture)
        result.cleanupOK = true
        return result
    } catch {
        do { try removeFixture(fixture) }
        catch let cleanupError {
            throw ProbeError.combined(primary: String(describing: error), secondary: String(describing: cleanupError))
        }
        throw error
    }
}

private func parseArguments() throws -> (Candidate, Scenario, Double) {
    let arguments = CommandLine.arguments
    guard arguments.count == 7,
          arguments[1] == "--candidate",
          arguments[3] == "--scenario",
          arguments[5] == "--timeout" else {
        throw ProbeError.invalidArguments("Usage: recovery-probe --candidate dispatch|fsevents --scenario NAME --timeout S")
    }
    guard let candidate = Candidate(rawValue: arguments[2]) else {
        throw ProbeError.invalidArguments("Invalid candidate: \(arguments[2])")
    }
    guard let scenario = Scenario(rawValue: arguments[4]) else {
        throw ProbeError.invalidArguments("Invalid scenario: \(arguments[4])")
    }
    guard let timeout = Double(arguments[6]), timeout > 0, timeout <= 120 else {
        throw ProbeError.invalidArguments("Invalid timeout: \(arguments[6])")
    }
    return (candidate, scenario, timeout)
}

do {
    let (candidate, scenario, timeout) = try parseArguments()
    let result = try runScenario(candidate: candidate, scenario: scenario, timeout: timeout)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(result)
    guard let json = String(data: data, encoding: .utf8) else {
        throw ProbeError.filesystem("could not encode UTF-8 JSON")
    }
    print(json)
    Darwin.exit(0)
} catch ProbeError.invalidArguments(let message) {
    fputs("Error: \(message)\n", stderr)
    Darwin.exit(64)
} catch {
    fputs("Error: \(error)\n", stderr)
    Darwin.exit(1)
}
