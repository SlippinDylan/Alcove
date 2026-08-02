// main.swift — Phase 0.5C2 observer comparison probe
//
// Compiles DispatchSource and FSEvents candidate sources directly. Runs one
// candidate in-process, measures resource/latency/event/descriptor evidence,
// and emits a single JSON object on success. Exits nonzero on any error.
//
// Usage: observer-comparison-probe --candidate dispatch|fsevents --items N --timeout S

import Darwin
import Dispatch
import Foundation

// MARK: - Resource measurement

private func getRUsage() throws -> rusage {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw ProbeError.resourceMeasurementFailed("getrusage errno \(errno)")
    }
    return usage
}

private func cpuUserSeconds(_ r: rusage) -> Double {
    Double(r.ru_utime.tv_sec) + Double(r.ru_utime.tv_usec) / 1_000_000
}

private func cpuSystemSeconds(_ r: rusage) -> Double {
    Double(r.ru_stime.tv_sec) + Double(r.ru_stime.tv_usec) / 1_000_000
}

private func maxRSSBytes(_ r: rusage) -> Int64 {
    Int64(r.ru_maxrss)
}

private func currentDescriptorCount() throws -> Int {
    do {
        let contents = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd")
        return contents.count
    } catch {
        throw ProbeError.resourceMeasurementFailed("/dev/fd enumeration: \(error)")
    }
}

// MARK: - JSON helpers

private func jsonDouble(_ value: Double) -> String {
    String(format: "%.9f", value)
}

private func jsonOptionalDouble(_ value: Double?) -> String {
    if let v = value {
        return jsonDouble(v)
    }
    return "null"
}

private func jsonOptionalInt(_ value: Int?) -> String {
    if let v = value {
        return "\(v)"
    }
    return "null"
}

private func jsonBool(_ value: Bool) -> String {
    value ? "true" : "false"
}

private func jsonString(_ value: String) -> String {
    var escaped = value
    escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
    escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
    escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
    escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
    escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
    return "\"\(escaped)\""
}

// MARK: - Thread-safe helpers

private final class ProbeEventCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class ThreadSafeUUIDSet: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Set<UUID>()

    func insert(_ value: UUID) {
        lock.lock()
        defer { lock.unlock() }
        storage.insert(value)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}

private final class MarkerEventLatch: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var expectedPath: String?
    private var mutationStart: UInt64?
    private var latency: Double?

    func prepare(path: String) {
        lock.withLock {
            expectedPath = Self.canonicalPath(path)
            mutationStart = DispatchTime.now().uptimeNanoseconds
        }
    }

    func record(path: String?) {
        let shouldSignal = lock.withLock {
            guard latency == nil, let mutationStart else { return false }
            if let path, Self.canonicalPath(path) != expectedPath { return false }
            latency = Double(DispatchTime.now().uptimeNanoseconds - mutationStart) / 1_000_000_000
            return true
        }
        if shouldSignal { semaphore.signal() }
    }

    func wait(timeoutSeconds: Double) -> Bool {
        semaphore.wait(timeout: .now() + .milliseconds(Int(timeoutSeconds * 1000))) == .success
    }

    var firstLatency: Double? { lock.withLock { latency } }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

// MARK: - Result

private struct ComparisonResult: Sendable {
    let candidate: String
    let itemCount: Int
    let timeoutSeconds: Double
    let setupDurationSeconds: Double
    let observerStartDurationSeconds: Double
    let preStartCPUSecUser: Double
    let preStartCPUSecSystem: Double
    let preStartMaxRSSBytes: Int64
    let preStartDescriptorCount: Int
    let runningCPUSecUser: Double
    let runningCPUSecSystem: Double
    let runningMaxRSSBytes: Int64
    let runningDescriptorCount: Int
    let markerCreated: Bool
    let firstEventReceived: Bool
    let firstEventLatencySeconds: Double?
    let timeoutExpired: Bool
    let callbackCount: Int
    let recordCount: Int
    let callbackBatchCount: Int?
    let postStopCPUSecUser: Double
    let postStopCPUSecSystem: Double
    let postStopMaxRSSBytes: Int64
    let postStopDescriptorCount: Int
    let teardownDurationSeconds: Double
    let teardownState: String
    let postTeardownDescriptorCount: Int
    let descriptorSettleDurationSeconds: Double
    let descriptorReturnedToBaseline: Bool
    let descriptorDeltaFromPreStart: Int
    let bridgeFailureCount: Int?
    let cleanupOK: Bool

    func toJSON() -> String {
        var parts: [String] = []
        parts.append("\"bridgeFailureCount\":\(jsonOptionalInt(bridgeFailureCount))")
        parts.append("\"callbackBatchCount\":\(jsonOptionalInt(callbackBatchCount))")
        parts.append("\"callbackCount\":\(callbackCount)")
        parts.append("\"candidate\":\(jsonString(candidate))")
        parts.append("\"cleanupOK\":\(jsonBool(cleanupOK))")
        parts.append("\"descriptorDeltaFromPreStart\":\(descriptorDeltaFromPreStart)")
        parts.append("\"descriptorReturnedToBaseline\":\(jsonBool(descriptorReturnedToBaseline))")
        parts.append("\"descriptorSettleDurationSeconds\":\(jsonDouble(descriptorSettleDurationSeconds))")
        parts.append("\"firstEventLatencySeconds\":\(jsonOptionalDouble(firstEventLatencySeconds))")
        parts.append("\"firstEventReceived\":\(jsonBool(firstEventReceived))")
        parts.append("\"itemCount\":\(itemCount)")
        parts.append("\"markerCreated\":\(jsonBool(markerCreated))")
        parts.append("\"observerStartDurationSeconds\":\(jsonDouble(observerStartDurationSeconds))")
        parts.append("\"postStopCPU\":{\"systemSec\":\(jsonDouble(postStopCPUSecSystem)),\"userSec\":\(jsonDouble(postStopCPUSecUser))}")
        parts.append("\"postStopDescriptorCount\":\(postStopDescriptorCount)")
        parts.append("\"postStopMaxRSSBytes\":\(postStopMaxRSSBytes)")
        parts.append("\"postTeardownDescriptorCount\":\(postTeardownDescriptorCount)")
        parts.append("\"preStartCPU\":{\"systemSec\":\(jsonDouble(preStartCPUSecSystem)),\"userSec\":\(jsonDouble(preStartCPUSecUser))}")
        parts.append("\"preStartDescriptorCount\":\(preStartDescriptorCount)")
        parts.append("\"preStartMaxRSSBytes\":\(preStartMaxRSSBytes)")
        parts.append("\"recordCount\":\(recordCount)")
        parts.append("\"runningCPU\":{\"systemSec\":\(jsonDouble(runningCPUSecSystem)),\"userSec\":\(jsonDouble(runningCPUSecUser))}")
        parts.append("\"runningDescriptorCount\":\(runningDescriptorCount)")
        parts.append("\"runningMaxRSSBytes\":\(runningMaxRSSBytes)")
        parts.append("\"setupDurationSeconds\":\(jsonDouble(setupDurationSeconds))")
        parts.append("\"teardownDurationSeconds\":\(jsonDouble(teardownDurationSeconds))")
        parts.append("\"teardownState\":\(jsonString(teardownState))")
        parts.append("\"timeoutExpired\":\(jsonBool(timeoutExpired))")
        parts.append("\"timeoutSeconds\":\(jsonDouble(timeoutSeconds))")
        return "{" + parts.joined(separator: ",") + "}"
    }
}

// MARK: - Errors

private enum ProbeError: Error, CustomStringConvertible {
    case invalidCandidate(String)
    case invalidItems(String)
    case invalidTimeout(String)
    case prepopulationFailed(path: String, code: Int32)
    case markerCreationFailed(path: String, code: Int32)
    case observerStartFailed(String)
    case markerCloseFailed(path: String, code: Int32)
    case eventTimedOut(candidate: String)
    case teardownFailed(candidate: String, description: String)
    case resourceMeasurementFailed(String)
    case cleanupFailed(path: String, description: String)

    var description: String {
        switch self {
        case .invalidCandidate(let v):
            return "Invalid candidate: \(v). Use 'dispatch' or 'fsevents'."
        case .invalidItems(let v):
            return "Invalid items count: \(v). Must be a positive integer."
        case .invalidTimeout(let v):
            return "Invalid timeout: \(v). Must be a positive number <= 120."
        case .prepopulationFailed(let path, let code):
            return "Failed to create prepopulation file at \(path): errno \(code)"
        case .markerCreationFailed(let path, let code):
            return "Failed to create marker file at \(path): errno \(code)"
        case .observerStartFailed(let msg):
            return "Observer start failed: \(msg)"
        case .markerCloseFailed(let path, let code):
            return "Failed to close marker at \(path): errno \(code)"
        case .eventTimedOut(let candidate):
            return "Timed out waiting for \(candidate) marker evidence"
        case .teardownFailed(let candidate, let description):
            return "\(candidate) teardown failed: \(description)"
        case .resourceMeasurementFailed(let description):
            return "Resource measurement failed: \(description)"
        case .cleanupFailed(let path, let description):
            return "Fixture cleanup failed for \(path): \(description)"
        }
    }
}

private func createMarker(path: String, latch: MarkerEventLatch) throws {
    latch.prepare(path: path)
    let descriptor = Darwin.open(path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw ProbeError.markerCreationFailed(path: path, code: errno) }
    guard Darwin.close(descriptor) == 0 else {
        throw ProbeError.markerCloseFailed(path: path, code: errno)
    }
}

private func settledDescriptorCount(
    baseline: Int,
    timeout: DispatchTime = .now() + 2
) throws -> (count: Int, duration: Double, returned: Bool) {
    let start = DispatchTime.now().uptimeNanoseconds
    var count = try currentDescriptorCount()
    while count != baseline, DispatchTime.now() < timeout {
        usleep(10_000)
        count = try currentDescriptorCount()
    }
    let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    return (count, duration, count == baseline)
}

private func removeFixture(_ url: URL) throws {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        throw ProbeError.cleanupFailed(path: url.path, description: String(describing: error))
    }
}

// MARK: - Top-level measurement

private func measure(candidate: String, itemCount: Int, timeoutSeconds: Double) throws -> ComparisonResult {
    // 1. Create isolated temp directory.
    let tempBase = FileManager.default.temporaryDirectory
    let tempDir = tempBase.appendingPathComponent("alcove-comparison-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    do {
        // 2. Prepopulate N empty regular files.
        let setupStart = DispatchTime.now().uptimeNanoseconds
        for i in 0..<itemCount {
            let filePath = tempDir.appendingPathComponent("item-\(String(format: "%05d", i))").path
            let fd = Darwin.open(filePath, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
            guard fd >= 0 else {
                throw ProbeError.prepopulationFailed(path: filePath, code: errno)
            }
            guard Darwin.close(fd) == 0 else {
                throw ProbeError.prepopulationFailed(path: filePath, code: errno)
            }
        }
        let setupDuration = Double(DispatchTime.now().uptimeNanoseconds - setupStart) / 1_000_000_000
        let preRUsage = try getRUsage()
        let preDescCount = try currentDescriptorCount()
        let result: ComparisonResult
        if candidate == "dispatch" {
            result = try measureDispatch(
                tempDir: tempDir,
                itemCount: itemCount,
                timeoutSeconds: timeoutSeconds,
                setupDuration: setupDuration,
                preRUsage: preRUsage,
                preDescCount: preDescCount
            )
        } else {
            result = try measureFSEvents(
                tempDir: tempDir,
                itemCount: itemCount,
                timeoutSeconds: timeoutSeconds,
                setupDuration: setupDuration,
                preRUsage: preRUsage,
                preDescCount: preDescCount
            )
        }
        try removeFixture(tempDir)
        return result
    } catch {
        do {
            if FileManager.default.fileExists(atPath: tempDir.path) {
                try removeFixture(tempDir)
            }
        } catch let cleanupError {
            throw ProbeError.cleanupFailed(
                path: tempDir.path,
                description: "primary error: \(error); cleanup error: \(cleanupError)"
            )
        }
        throw error
    }
}

// MARK: - DispatchSource measurement

private func measureDispatch(
    tempDir: URL,
    itemCount: Int,
    timeoutSeconds: Double,
    setupDuration: Double,
    preRUsage: rusage,
    preDescCount: Int
) throws -> ComparisonResult {
    let eventCounter = ProbeEventCounter()
    let markerLatch = MarkerEventLatch()
    let observer = DispatchSourceFolderObserver { _ in
        _ = eventCounter.increment()
        markerLatch.record(path: nil)
    }

    let startBegin = DispatchTime.now().uptimeNanoseconds
    do {
        try observer.start(path: tempDir.path)
    } catch {
        throw ProbeError.observerStartFailed(String(describing: error))
    }

    let startEnd = DispatchTime.now().uptimeNanoseconds
    let startDuration = Double(startEnd - startBegin) / 1_000_000_000

    // "While running" resource snapshot.
    do {
        let runningRUsage = try getRUsage()
        let runningDescCount = try currentDescriptorCount()
        let markerPath = tempDir.appendingPathComponent("marker-\(UUID().uuidString)").path
        try createMarker(path: markerPath, latch: markerLatch)
        guard markerLatch.wait(timeoutSeconds: timeoutSeconds) else {
            throw ProbeError.eventTimedOut(candidate: "dispatch")
        }
        usleep(50_000)
        let callbackCount = eventCounter.value

        let teardownStart = DispatchTime.now().uptimeNanoseconds
        _ = try observer.stopAndWait(timeout: .now() + 3)
        let teardownDuration = Double(DispatchTime.now().uptimeNanoseconds - teardownStart) / 1_000_000_000
        let postStopRUsage = try getRUsage()
        let postStopDescCount = try currentDescriptorCount()
        let settled = try settledDescriptorCount(baseline: preDescCount)

        return ComparisonResult(
        candidate: "dispatch",
        itemCount: itemCount,
        timeoutSeconds: timeoutSeconds,
        setupDurationSeconds: setupDuration,
        observerStartDurationSeconds: startDuration,
        preStartCPUSecUser: cpuUserSeconds(preRUsage),
        preStartCPUSecSystem: cpuSystemSeconds(preRUsage),
        preStartMaxRSSBytes: maxRSSBytes(preRUsage),
        preStartDescriptorCount: preDescCount,
        runningCPUSecUser: cpuUserSeconds(runningRUsage),
        runningCPUSecSystem: cpuSystemSeconds(runningRUsage),
        runningMaxRSSBytes: maxRSSBytes(runningRUsage),
        runningDescriptorCount: runningDescCount,
        markerCreated: true,
        firstEventReceived: true,
        firstEventLatencySeconds: markerLatch.firstLatency,
        timeoutExpired: false,
        callbackCount: callbackCount,
        recordCount: callbackCount,
        callbackBatchCount: nil,
        postStopCPUSecUser: cpuUserSeconds(postStopRUsage),
        postStopCPUSecSystem: cpuSystemSeconds(postStopRUsage),
        postStopMaxRSSBytes: maxRSSBytes(postStopRUsage),
        postStopDescriptorCount: postStopDescCount,
        teardownDurationSeconds: teardownDuration,
        teardownState: "stopped",
        postTeardownDescriptorCount: settled.count,
        descriptorSettleDurationSeconds: settled.duration,
        descriptorReturnedToBaseline: settled.returned,
        descriptorDeltaFromPreStart: settled.count - preDescCount,
        bridgeFailureCount: nil,
        cleanupOK: true
        )
    } catch {
        do {
            _ = try observer.stopAndWait(timeout: .now() + 3)
        } catch let teardownError {
            throw ProbeError.teardownFailed(
                candidate: "dispatch",
                description: "primary error: \(error); teardown error: \(teardownError)"
            )
        }
        throw error
    }
}

// MARK: - FSEvents measurement

private func measureFSEvents(
    tempDir: URL,
    itemCount: Int,
    timeoutSeconds: Double,
    setupDuration: Double,
    preRUsage: rusage,
    preDescCount: Int
) throws -> ComparisonResult {
    let recordCounter = ProbeEventCounter()
    let batchIdentities = ThreadSafeUUIDSet()
    let markerLatch = MarkerEventLatch()

    let observer = FSEventsFolderObserver { record in
        _ = recordCounter.increment()
        batchIdentities.insert(record.callbackBatchIdentity)
        markerLatch.record(path: record.path)
    }

    let startBegin = DispatchTime.now().uptimeNanoseconds
    do {
        try observer.start(path: tempDir.path)
    } catch {
        throw ProbeError.observerStartFailed(String(describing: error))
    }

    let startEnd = DispatchTime.now().uptimeNanoseconds
    let startDuration = Double(startEnd - startBegin) / 1_000_000_000

    // "While running" resource snapshot.
    do {
        let runningRUsage = try getRUsage()
        let runningDescCount = try currentDescriptorCount()
        let markerPath = tempDir.appendingPathComponent("marker-\(UUID().uuidString)").path
        try createMarker(path: markerPath, latch: markerLatch)
        guard markerLatch.wait(timeoutSeconds: timeoutSeconds) else {
            throw ProbeError.eventTimedOut(candidate: "fsevents")
        }
        usleep(50_000)
        let recordCount = recordCounter.value
        let callbackCount = batchIdentities.count

        let teardownStart = DispatchTime.now().uptimeNanoseconds
        try observer.stopAndWait(timeout: .now() + 3)
        let teardownDuration = Double(DispatchTime.now().uptimeNanoseconds - teardownStart) / 1_000_000_000
        let postStopRUsage = try getRUsage()
        let postStopDescCount = try currentDescriptorCount()
        let settled = try settledDescriptorCount(baseline: preDescCount)

        return ComparisonResult(
        candidate: "fsevents",
        itemCount: itemCount,
        timeoutSeconds: timeoutSeconds,
        setupDurationSeconds: setupDuration,
        observerStartDurationSeconds: startDuration,
        preStartCPUSecUser: cpuUserSeconds(preRUsage),
        preStartCPUSecSystem: cpuSystemSeconds(preRUsage),
        preStartMaxRSSBytes: maxRSSBytes(preRUsage),
        preStartDescriptorCount: preDescCount,
        runningCPUSecUser: cpuUserSeconds(runningRUsage),
        runningCPUSecSystem: cpuSystemSeconds(runningRUsage),
        runningMaxRSSBytes: maxRSSBytes(runningRUsage),
        runningDescriptorCount: runningDescCount,
        markerCreated: true,
        firstEventReceived: true,
        firstEventLatencySeconds: markerLatch.firstLatency,
        timeoutExpired: false,
        callbackCount: callbackCount,
        recordCount: recordCount,
        callbackBatchCount: callbackCount,
        postStopCPUSecUser: cpuUserSeconds(postStopRUsage),
        postStopCPUSecSystem: cpuSystemSeconds(postStopRUsage),
        postStopMaxRSSBytes: maxRSSBytes(postStopRUsage),
        postStopDescriptorCount: postStopDescCount,
        teardownDurationSeconds: teardownDuration,
        teardownState: "stopped",
        postTeardownDescriptorCount: settled.count,
        descriptorSettleDurationSeconds: settled.duration,
        descriptorReturnedToBaseline: settled.returned,
        descriptorDeltaFromPreStart: settled.count - preDescCount,
        bridgeFailureCount: observer.bridgeFailureCount,
        cleanupOK: true
        )
    } catch {
        do {
            try observer.stopAndWait(timeout: .now() + 3)
        } catch let teardownError {
            throw ProbeError.teardownFailed(
                candidate: "fsevents",
                description: "primary error: \(error); teardown error: \(teardownError)"
            )
        }
        throw error
    }
}

// MARK: - Main

private func usage() {
    fputs("Usage: observer-comparison-probe --candidate dispatch|fsevents --items N --timeout S\n", stderr)
    fputs("\n", stderr)
    fputs("  --candidate  'dispatch' or 'fsevents'\n", stderr)
    fputs("  --items      Number of prepopulated files (positive integer)\n", stderr)
    fputs("  --timeout    Seconds to wait for first event (positive, <= 120)\n", stderr)
}

private func parseArgs() throws -> (candidate: String, items: Int, timeout: Double) {
    let args = CommandLine.arguments
    var candidate: String?
    var items: String?
    var timeout: String?

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--candidate":
            guard i + 1 < args.count else { throw ProbeError.invalidCandidate("missing value") }
            candidate = args[i + 1]
            i += 2
        case "--items":
            guard i + 1 < args.count else { throw ProbeError.invalidItems("missing value") }
            items = args[i + 1]
            i += 2
        case "--timeout":
            guard i + 1 < args.count else { throw ProbeError.invalidTimeout("missing value") }
            timeout = args[i + 1]
            i += 2
        default:
            throw ProbeError.invalidCandidate("unexpected argument: \(args[i])")
        }
    }

    guard let c = candidate else { throw ProbeError.invalidCandidate("missing --candidate") }
    guard c == "dispatch" || c == "fsevents" else { throw ProbeError.invalidCandidate(c) }

    guard let iStr = items else { throw ProbeError.invalidItems("missing --items") }
    guard let iVal = Int(iStr), iVal > 0 else { throw ProbeError.invalidItems(iStr) }

    guard let tStr = timeout else { throw ProbeError.invalidTimeout("missing --timeout") }
    guard let tVal = Double(tStr), tVal > 0, tVal <= 120 else { throw ProbeError.invalidTimeout(tStr) }

    return (candidate: c, items: iVal, timeout: tVal)
}

do {
    let params = try parseArgs()
    let result = try measure(
        candidate: params.candidate,
        itemCount: params.items,
        timeoutSeconds: params.timeout
    )
    print(result.toJSON())
    Darwin.exit(0)
} catch ProbeError.invalidCandidate(let value) {
    fputs("Error: \(ProbeError.invalidCandidate(value))\n", stderr)
    usage()
    Darwin.exit(64)
} catch ProbeError.invalidItems(let value) {
    fputs("Error: \(ProbeError.invalidItems(value))\n", stderr)
    usage()
    Darwin.exit(64)
} catch ProbeError.invalidTimeout(let value) {
    fputs("Error: \(ProbeError.invalidTimeout(value))\n", stderr)
    usage()
    Darwin.exit(64)
} catch let probeError as ProbeError {
    fputs("Error: \(probeError)\n", stderr)
    Darwin.exit(1)
} catch {
    fputs("Error: \(error)\n", stderr)
    Darwin.exit(1)
}
