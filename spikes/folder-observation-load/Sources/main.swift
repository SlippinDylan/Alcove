import CoreServices
import Darwin
import Dispatch
import Foundation

private enum Candidate: String, Codable, Sendable {
    case dispatch
    case fsevents
}

private enum Scenario: String, Codable, CaseIterable, Sendable {
    case independentRoots = "independent-roots"
    case sharedRoot = "shared-root"
    case mutationLoad = "mutation-load"
    case lifecycleChurn = "lifecycle-churn"
}

private struct ProcessUsage: Codable, Sendable {
    let userCPUSeconds: Double
    let systemCPUSeconds: Double
    let maxRSSBytesHighWater: Int64
}

private struct RegistrationEvidence: Codable, Sendable {
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

private struct LoadResult: Codable, Sendable {
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
    var cleanupOK: Bool
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case filesystem(String)
    case eventTimeout(String)
    case teardown(String)
    case resource(String)
    case cleanup(String)
    case combined(primary: String, secondary: String)

    var description: String {
        switch self {
        case .invalidArguments(let value): return value
        case .filesystem(let value): return "Filesystem error: \(value)"
        case .eventTimeout(let value): return "Event timeout: \(value)"
        case .teardown(let value): return "Teardown error: \(value)"
        case .resource(let value): return "Resource measurement error: \(value)"
        case .cleanup(let value): return "Cleanup error: \(value)"
        case .combined(let primary, let secondary):
            return "Primary error: \(primary); secondary error: \(secondary)"
        }
    }
}

private struct EventSample: Sendable {
    let path: String?
    let rawFlags: UInt64
    let batchIdentity: UUID?
}

private final class EvidenceGate: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var expectedPath: String?
    private var isArmed = false
    private var didReceive = false
    private var matchedPath: String?

    func arm(expectedPath: String?) {
        lock.withLock {
            self.expectedPath = expectedPath.map(canonicalPath)
            isArmed = true
            didReceive = false
            matchedPath = nil
        }
    }

    func record(_ sample: EventSample) {
        let shouldSignal = lock.withLock {
            guard isArmed, !didReceive else { return false }
            if let expectedPath {
                guard let path = sample.path, canonicalPath(path) == expectedPath else {
                    return false
                }
                matchedPath = canonicalPath(path)
            }
            didReceive = true
            return true
        }
        if shouldSignal { signal.signal() }
    }

    func wait(timeoutSeconds: Double) -> Bool {
        signal.wait(timeout: .now() + .milliseconds(Int(timeoutSeconds * 1_000))) == .success
    }

    func close() {
        lock.withLock { isArmed = false }
    }

    var snapshot: (received: Bool, path: String?) {
        lock.withLock { (didReceive, matchedPath) }
    }
}

private final class EventStatistics: @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks = 0
    private var records = 0
    private var batches: Set<UUID> = []
    private var droppedFlags = 0
    private var rootChangeFlags = 0

    func recordDispatch() {
        lock.withLock {
            callbacks += 1
            records += 1
        }
    }

    func recordFSEvents(_ sample: EventSample) {
        lock.withLock {
            records += 1
            if let identity = sample.batchIdentity {
                batches.insert(identity)
                callbacks = batches.count
            }
            let dropped = UInt64(kFSEventStreamEventFlagMustScanSubDirs)
                | UInt64(kFSEventStreamEventFlagUserDropped)
                | UInt64(kFSEventStreamEventFlagKernelDropped)
            if sample.rawFlags & dropped != 0 { droppedFlags += 1 }
            if sample.rawFlags & UInt64(kFSEventStreamEventFlagRootChanged) != 0 {
                rootChangeFlags += 1
            }
        }
    }

    var snapshot: (callbacks: Int, records: Int, batches: Int, dropped: Int, rootChanges: Int) {
        lock.withLock { (callbacks, records, batches.count, droppedFlags, rootChangeFlags) }
    }

    func waitForQuiet(quietSeconds: Double, timeoutSeconds: Double) -> Bool {
        let deadline = monotonicNow() + timeoutSeconds
        var lastCount = snapshot.records
        var stableSince = monotonicNow()
        while monotonicNow() < deadline {
            usleep(10_000)
            let current = snapshot.records
            if current != lastCount {
                lastCount = current
                stableSince = monotonicNow()
            } else if monotonicNow() - stableSince >= quietSeconds {
                return true
            }
        }
        return false
    }
}

private final class ManagedObserver: @unchecked Sendable {
    let index: Int
    let gate = EvidenceGate()
    let statistics = EventStatistics()

    private let candidate: Candidate
    private let dispatchObserver: DispatchSourceFolderObserver?
    private let fseventsObserver: FSEventsFolderObserver?

    init(candidate: Candidate, index: Int) {
        self.candidate = candidate
        self.index = index
        switch candidate {
        case .dispatch:
            fseventsObserver = nil
            dispatchObserver = DispatchSourceFolderObserver(
                queueLabel: "com.alcove.spike.load.dispatch.\(index)"
            ) { [gate, statistics] _ in
                statistics.recordDispatch()
                gate.record(EventSample(path: nil, rawFlags: 0, batchIdentity: nil))
            }
        case .fsevents:
            dispatchObserver = nil
            fseventsObserver = FSEventsFolderObserver(
                queueLabel: "com.alcove.spike.load.fsevents.\(index)"
            ) { [gate, statistics] record in
                let sample = EventSample(
                    path: record.path,
                    rawFlags: UInt64(record.rawFlags),
                    batchIdentity: record.callbackBatchIdentity
                )
                statistics.recordFSEvents(sample)
                gate.record(sample)
            }
        }
    }

    func start(path: String) throws {
        switch candidate {
        case .dispatch:
            guard let observer = dispatchObserver else {
                throw ProbeError.filesystem("DispatchSource observer was not constructed")
            }
            try observer.start(path: path)
        case .fsevents:
            guard let observer = fseventsObserver else {
                throw ProbeError.filesystem("FSEvents observer was not constructed")
            }
            try observer.start(path: path)
        }
    }

    var generation: UInt64 {
        dispatchObserver?.currentGeneration ?? fseventsObserver?.currentGeneration ?? 0
    }

    var registrationIdentity: String? {
        fseventsObserver?.currentRegistrationIdentity?.uuidString
    }

    var bridgeFailureCount: Int {
        fseventsObserver?.bridgeFailureCount ?? 0
    }

    func stopAndWait() throws {
        switch candidate {
        case .dispatch:
            guard let observer = dispatchObserver else {
                throw ProbeError.teardown("missing DispatchSource observer")
            }
            let teardown = try observer.stopAndWait(timeout: .now() + .seconds(3))
            guard teardown.descriptorWasOpened, teardown.descriptorWasClosed,
                  observer.lifecycleState == .stopped else {
                throw ProbeError.teardown("DispatchSource descriptor or lifecycle did not stop")
            }
        case .fsevents:
            guard let observer = fseventsObserver else {
                throw ProbeError.teardown("missing FSEvents observer")
            }
            let state = try observer.stopAndWait(timeout: .now() + .seconds(3))
            guard state == .stopped else {
                throw ProbeError.teardown("FSEvents lifecycle is \(state)")
            }
        }
    }
}

private func canonicalPath(_ path: String) -> String {
    let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
    if standardized == "/private/var" { return "/var" }
    if standardized.hasPrefix("/private/var/") { return String(standardized.dropFirst(8)) }
    return standardized
}

private func monotonicNow() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}

private func processUsage() throws -> ProcessUsage {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw ProbeError.resource("getrusage failed with errno \(errno)")
    }
    func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }
    return ProcessUsage(
        userCPUSeconds: seconds(usage.ru_utime),
        systemCPUSeconds: seconds(usage.ru_stime),
        maxRSSBytesHighWater: Int64(usage.ru_maxrss)
    )
}

private func descriptorCount() throws -> Int {
    do {
        return try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    } catch {
        throw ProbeError.resource("cannot enumerate /dev/fd: \(error)")
    }
}

private func settledDescriptorCount(baseline: Int) throws -> (count: Int, duration: Double, returned: Bool) {
    let start = monotonicNow()
    let deadline = start + 2
    var count = try descriptorCount()
    while count != baseline, monotonicNow() < deadline {
        usleep(10_000)
        count = try descriptorCount()
    }
    return (count, monotonicNow() - start, count == baseline)
}

private func createDirectory(_ url: URL) throws {
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    } catch {
        throw ProbeError.filesystem("create directory \(url.path): \(error)")
    }
}

private func createFile(_ url: URL) throws {
    let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
        throw ProbeError.filesystem("open \(url.path): errno \(errno)")
    }
    guard Darwin.close(descriptor) == 0 else {
        throw ProbeError.filesystem("close \(url.path): errno \(errno)")
    }
}

private func removeFixture(_ url: URL) throws {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        throw ProbeError.cleanup("remove \(url.path): \(error)")
    }
}

private func stopAll(_ observers: [ManagedObserver]) throws {
    var errors: [String] = []
    for observer in observers.reversed() {
        do { try observer.stopAndWait() }
        catch { errors.append("observer \(observer.index): \(error)") }
    }
    if !errors.isEmpty { throw ProbeError.teardown(errors.joined(separator: "; ")) }
}

private func withStartedObservers<T>(
    candidate: Candidate,
    paths: [String],
    body: ([ManagedObserver]) throws -> T
) throws -> T {
    var started: [ManagedObserver] = []
    do {
        for (index, path) in paths.enumerated() {
            let observer = ManagedObserver(candidate: candidate, index: index)
            try observer.start(path: path)
            started.append(observer)
        }
        let value = try body(started)
        try stopAll(started)
        return value
    } catch {
        do { try stopAll(started) }
        catch let teardownError {
            throw ProbeError.combined(
                primary: String(describing: error),
                secondary: String(describing: teardownError)
            )
        }
        throw error
    }
}

private func armAndCreate(
    observers: [ManagedObserver],
    markers: [URL],
    candidate: Candidate,
    timeout: Double
) throws {
    guard observers.count == markers.count else {
        throw ProbeError.filesystem("observer and marker counts differ")
    }
    for (observer, marker) in zip(observers, markers) {
        observer.gate.arm(expectedPath: candidate == .fsevents ? marker.path : nil)
    }
    var createdPaths: Set<String> = []
    for marker in markers where createdPaths.insert(marker.path).inserted {
        try createFile(marker)
    }
    for observer in observers {
        guard observer.gate.wait(timeoutSeconds: timeout) else {
            throw ProbeError.eventTimeout("registration \(observer.index)")
        }
        observer.gate.close()
    }
}

private func evidence(
    observers: [ManagedObserver],
    markers: [URL],
    candidate: Candidate
) -> [RegistrationEvidence] {
    zip(observers, markers).map { observer, marker in
        let gate = observer.gate.snapshot
        let stats = observer.statistics.snapshot
        return RegistrationEvidence(
            index: observer.index,
            generation: observer.generation,
            registrationIdentity: observer.registrationIdentity,
            expectedMarkerPath: canonicalPath(marker.path),
            received: gate.received,
            matchedMarkerPath: gate.path,
            callbackCount: stats.callbacks,
            recordCount: stats.records,
            callbackBatchCount: candidate == .fsevents ? stats.batches : nil
        )
    }
}

private struct ScenarioMeasurements {
    let observers: [RegistrationEvidence]
    let maximumSimultaneousObserverCount: Int
    let mutationCount: Int
    let enumerationCount: Int?
    let mutationDuration: Double?
    let dropped: Int
    let rootChanges: Int
    let bridgeFailures: Int
    let descriptorBeforeTeardown: Int
    let postCycleDescriptors: [Int]
}

private func runIndependentRoots(
    candidate: Candidate,
    fixture: URL,
    timeout: Double
) throws -> ScenarioMeasurements {
    let roots = (0..<8).map { fixture.appendingPathComponent("root-\($0)") }
    for root in roots { try createDirectory(root) }
    let markers = roots.enumerated().map {
        $0.element.appendingPathComponent("marker-\($0.offset)-\(UUID().uuidString)")
    }
    var captured: [ManagedObserver] = []
    var descriptorBefore = 0
    try withStartedObservers(candidate: candidate, paths: roots.map(\.path)) { observers in
        captured = observers
        try armAndCreate(observers: observers, markers: markers, candidate: candidate, timeout: timeout)
        descriptorBefore = try descriptorCount()
    }
    let registrations = evidence(observers: captured, markers: markers, candidate: candidate)
    let stats = captured.map(\.statistics.snapshot)
    return ScenarioMeasurements(
        observers: registrations,
        maximumSimultaneousObserverCount: captured.count,
        mutationCount: 8,
        enumerationCount: nil,
        mutationDuration: nil,
        dropped: stats.reduce(0) { $0 + $1.dropped },
        rootChanges: stats.reduce(0) { $0 + $1.rootChanges },
        bridgeFailures: captured.reduce(0) { $0 + $1.bridgeFailureCount },
        descriptorBeforeTeardown: descriptorBefore,
        postCycleDescriptors: []
    )
}

private func runSharedRoot(
    candidate: Candidate,
    fixture: URL,
    timeout: Double
) throws -> ScenarioMeasurements {
    let root = fixture.appendingPathComponent("shared")
    try createDirectory(root)
    let marker = root.appendingPathComponent("marker-\(UUID().uuidString)")
    var captured: [ManagedObserver] = []
    var descriptorBefore = 0
    try withStartedObservers(candidate: candidate, paths: Array(repeating: root.path, count: 8)) { observers in
        captured = observers
        try armAndCreate(
            observers: observers,
            markers: Array(repeating: marker, count: 8),
            candidate: candidate,
            timeout: timeout
        )
        descriptorBefore = try descriptorCount()
    }
    let registrations = evidence(
        observers: captured,
        markers: Array(repeating: marker, count: 8),
        candidate: candidate
    )
    let stats = captured.map(\.statistics.snapshot)
    return ScenarioMeasurements(
        observers: registrations,
        maximumSimultaneousObserverCount: captured.count,
        mutationCount: 1,
        enumerationCount: nil,
        mutationDuration: nil,
        dropped: stats.reduce(0) { $0 + $1.dropped },
        rootChanges: stats.reduce(0) { $0 + $1.rootChanges },
        bridgeFailures: captured.reduce(0) { $0 + $1.bridgeFailureCount },
        descriptorBeforeTeardown: descriptorBefore,
        postCycleDescriptors: []
    )
}

private func runMutationLoad(
    candidate: Candidate,
    fixture: URL,
    timeout: Double
) throws -> ScenarioMeasurements {
    let root = fixture.appendingPathComponent("load")
    try createDirectory(root)
    let sentinel = root.appendingPathComponent("sentinel-\(UUID().uuidString)")
    var captured: [ManagedObserver] = []
    var duration = 0.0
    var enumerationCount = 0
    var descriptorBefore = 0
    try withStartedObservers(candidate: candidate, paths: [root.path]) { observers in
        captured = observers
        let start = monotonicNow()
        for batch in 0..<20 {
            for item in 0..<50 {
                let name = String(format: "item-%02d-%02d.dat", batch, item)
                try createFile(root.appendingPathComponent(name))
            }
        }
        duration = monotonicNow() - start
        guard observers[0].statistics.waitForQuiet(quietSeconds: 0.1, timeoutSeconds: timeout) else {
            throw ProbeError.eventTimeout("pre-sentinel quiescence")
        }
        try armAndCreate(
            observers: observers,
            markers: [sentinel],
            candidate: candidate,
            timeout: timeout
        )
        guard observers[0].statistics.waitForQuiet(quietSeconds: 0.1, timeoutSeconds: timeout) else {
            throw ProbeError.eventTimeout("post-sentinel quiescence")
        }
        do {
            enumerationCount = try FileManager.default.contentsOfDirectory(atPath: root.path).count
        } catch {
            throw ProbeError.filesystem("enumerate load root: \(error)")
        }
        guard enumerationCount == 1_001 else {
            throw ProbeError.filesystem("expected 1001 files, found \(enumerationCount)")
        }
        descriptorBefore = try descriptorCount()
    }
    let stats = captured[0].statistics.snapshot
    return ScenarioMeasurements(
        observers: evidence(observers: captured, markers: [sentinel], candidate: candidate),
        maximumSimultaneousObserverCount: captured.count,
        mutationCount: 1_001,
        enumerationCount: enumerationCount,
        mutationDuration: duration,
        dropped: stats.dropped,
        rootChanges: stats.rootChanges,
        bridgeFailures: captured[0].bridgeFailureCount,
        descriptorBeforeTeardown: descriptorBefore,
        postCycleDescriptors: []
    )
}

private func runLifecycleChurn(
    candidate: Candidate,
    fixture: URL,
    timeout: Double,
    descriptorBaseline: Int
) throws -> ScenarioMeasurements {
    var registrations: [RegistrationEvidence] = []
    var postCycleDescriptors: [Int] = []
    var dropped = 0
    var rootChanges = 0
    var bridgeFailures = 0
    var descriptorBeforeTeardown = descriptorBaseline
    for cycle in 0..<25 {
        let root = fixture.appendingPathComponent("cycle-\(cycle)")
        try createDirectory(root)
        let marker = root.appendingPathComponent("marker-\(cycle)-\(UUID().uuidString)")
        var captured: [ManagedObserver] = []
        try withStartedObservers(candidate: candidate, paths: [root.path]) { observers in
            captured = observers
            try armAndCreate(observers: observers, markers: [marker], candidate: candidate, timeout: timeout)
            descriptorBeforeTeardown = max(descriptorBeforeTeardown, try descriptorCount())
        }
        let item = evidence(observers: captured, markers: [marker], candidate: candidate)[0]
        registrations.append(RegistrationEvidence(
            index: cycle,
            generation: item.generation,
            registrationIdentity: item.registrationIdentity,
            expectedMarkerPath: item.expectedMarkerPath,
            received: item.received,
            matchedMarkerPath: item.matchedMarkerPath,
            callbackCount: item.callbackCount,
            recordCount: item.recordCount,
            callbackBatchCount: item.callbackBatchCount
        ))
        let stats = captured[0].statistics.snapshot
        dropped += stats.dropped
        rootChanges += stats.rootChanges
        bridgeFailures += captured[0].bridgeFailureCount
        let settled = try settledDescriptorCount(baseline: descriptorBaseline)
        guard settled.returned else {
            throw ProbeError.resource(
                "cycle \(cycle) descriptor count \(settled.count) did not return to baseline \(descriptorBaseline)"
            )
        }
        postCycleDescriptors.append(settled.count)
    }
    return ScenarioMeasurements(
        observers: registrations,
        maximumSimultaneousObserverCount: registrations.isEmpty ? 0 : 1,
        mutationCount: 25,
        enumerationCount: nil,
        mutationDuration: nil,
        dropped: dropped,
        rootChanges: rootChanges,
        bridgeFailures: bridgeFailures,
        descriptorBeforeTeardown: descriptorBeforeTeardown,
        postCycleDescriptors: postCycleDescriptors
    )
}

private func execute(candidate: Candidate, scenario: Scenario, timeout: Double) throws -> LoadResult {
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let fixture = tempRoot.appendingPathComponent("alcove-observer-load-\(UUID().uuidString)", isDirectory: true)
    try createDirectory(fixture)
    let execution: Result<LoadResult, Error>
    do {
        let usageBefore = try processUsage()
        let descriptorBaseline = try descriptorCount()
        let measurements: ScenarioMeasurements
        switch scenario {
        case .independentRoots:
            measurements = try runIndependentRoots(candidate: candidate, fixture: fixture, timeout: timeout)
        case .sharedRoot:
            measurements = try runSharedRoot(candidate: candidate, fixture: fixture, timeout: timeout)
        case .mutationLoad:
            measurements = try runMutationLoad(candidate: candidate, fixture: fixture, timeout: timeout)
        case .lifecycleChurn:
            measurements = try runLifecycleChurn(
                candidate: candidate,
                fixture: fixture,
                timeout: timeout,
                descriptorBaseline: descriptorBaseline
            )
        }
        let settled = try settledDescriptorCount(baseline: descriptorBaseline)
        guard settled.returned else {
            throw ProbeError.resource(
                "descriptor count \(settled.count) did not return to baseline \(descriptorBaseline)"
            )
        }
        let usageAfter = try processUsage()
        let received = measurements.observers.filter(\.received).count
        guard received == measurements.observers.count else {
            throw ProbeError.eventTimeout("only \(received)/\(measurements.observers.count) registrations received evidence")
        }
        if candidate == .fsevents {
            let identities = measurements.observers.compactMap(\.registrationIdentity)
            guard identities.count == measurements.observers.count,
                  Set(identities).count == identities.count else {
                throw ProbeError.filesystem("FSEvents registration identities are missing or not unique")
            }
            guard measurements.observers.allSatisfy({
                $0.matchedMarkerPath == $0.expectedMarkerPath
            }) else {
                throw ProbeError.filesystem("FSEvents marker path mismatch")
            }
        }
        execution = .success(LoadResult(
            candidate: candidate,
            scenario: scenario,
            observerCount: measurements.maximumSimultaneousObserverCount,
            requiredEvidenceCount: measurements.observers.count,
            receivedEvidenceCount: received,
            registrations: measurements.observers,
            mutationRegularFileCount: measurements.mutationCount,
            finalEnumerationCount: measurements.enumerationCount,
            mutationDurationSeconds: measurements.mutationDuration,
            knownDroppedFlagCount: measurements.dropped,
            rootChangeFlagCount: measurements.rootChanges,
            processUsageBefore: usageBefore,
            processUsageAfter: usageAfter,
            descriptorBaseline: descriptorBaseline,
            descriptorBeforeTeardown: measurements.descriptorBeforeTeardown,
            descriptorAfterSettling: settled.count,
            descriptorDeltaFromBaseline: settled.count - descriptorBaseline,
            descriptorSettleDurationSeconds: settled.duration,
            descriptorReturnedToBaseline: settled.returned,
            postCycleDescriptorCounts: measurements.postCycleDescriptors,
            bridgeFailureCount: measurements.bridgeFailures,
            teardownState: "stopped",
            timeoutExpired: false,
            cleanupOK: false
        ))
    } catch {
        execution = .failure(error)
    }

    let cleanup: Result<Void, Error>
    do {
        try removeFixture(fixture)
        cleanup = .success(())
    } catch {
        cleanup = .failure(error)
    }
    switch (execution, cleanup) {
    case (.success(var result), .success):
        result.cleanupOK = true
        return result
    case (.failure(let primary), .success):
        throw primary
    case (.success, .failure(let cleanupError)):
        throw cleanupError
    case (.failure(let primary), .failure(let cleanupError)):
        throw ProbeError.combined(
            primary: String(describing: primary),
            secondary: String(describing: cleanupError)
        )
    }
}

private func parseArguments(_ arguments: [String]) throws -> (Candidate, Scenario, Double) {
    guard arguments.count == 6,
          arguments[0] == "--candidate",
          let candidate = Candidate(rawValue: arguments[1]),
          arguments[2] == "--scenario",
          let scenario = Scenario(rawValue: arguments[3]),
          arguments[4] == "--timeout",
          let timeout = Double(arguments[5]),
          timeout > 0, timeout <= 60 else {
        throw ProbeError.invalidArguments(
            "Usage: observer-load-probe --candidate dispatch|fsevents --scenario independent-roots|shared-root|mutation-load|lifecycle-churn --timeout 0.001...60"
        )
    }
    return (candidate, scenario, timeout)
}

do {
    let (candidate, scenario, timeout) = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    let result = try execute(candidate: candidate, scenario: scenario, timeout: timeout)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(result)
    guard let output = String(data: data, encoding: .utf8) else {
        throw ProbeError.filesystem("could not encode UTF-8 JSON")
    }
    print(output)
} catch let error as ProbeError {
    fputs("Error: \(error)\n", stderr)
    switch error {
    case .invalidArguments: exit(64)
    default: exit(1)
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
