import Dispatch
import Foundation

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func rejectUnknownKeys<Key: CodingKey & CaseIterable>(
    _ decoder: Decoder,
    allowed: Key.Type
) throws where Key.AllCases: Collection {
    let dynamic = try decoder.container(keyedBy: DynamicCodingKey.self)
    let names = Set(Key.allCases.map(\.stringValue))
    if let unknown = dynamic.allKeys.first(where: { !names.contains($0.stringValue) }) {
        throw DecodingError.dataCorruptedError(
            forKey: unknown,
            in: dynamic,
            debugDescription: "Unknown key: \(unknown.stringValue)"
        )
    }
}

enum ProbeError: Error, CustomStringConvertible, Sendable {
    case invalidArguments
    case backgroundTimeout(String)
    case backgroundResultMissing
    case staleResult(returned: UInt64, current: UInt64)
    case filesystem(String)
    case fixtureMismatch(String)
    case restoration(String)
    case cleanup(String)
    case combined(primary: String, secondary: String)

    var description: String {
        switch self {
        case .invalidArguments: return "invalid arguments"
        case .backgroundTimeout(let label): return "background enumeration timed out: \(label)"
        case .backgroundResultMissing: return "background enumeration produced no result"
        case .staleResult(let returned, let current):
            return "stale generation \(returned); current generation is \(current)"
        case .filesystem(let value): return "filesystem error: \(value)"
        case .fixtureMismatch(let value): return "fixture mismatch: \(value)"
        case .restoration(let value): return "permission restoration error: \(value)"
        case .cleanup(let value): return "cleanup error: \(value)"
        case .combined(let primary, let secondary):
            return "primary error: \(primary); secondary error: \(secondary)"
        }
    }
}

struct EnumerationAttempt: Codable, Equatable, Sendable {
    let generation: UInt64
    let executedOnMainThread: Bool
    let entryCount: Int?
    let error: ClassifiedFolderAccessError?
}

struct LocationResult: Codable, Equatable, Sendable {
    let category: String
    let requestedGeneration: UInt64
    let returnedGeneration: UInt64
    let generationAccepted: Bool
    let executedOnMainThread: Bool
    let entryCount: Int?
    let error: ClassifiedFolderAccessError?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case category, requestedGeneration, returnedGeneration, generationAccepted
        case executedOnMainThread, entryCount, error
    }

    init(
        category: String,
        requestedGeneration: UInt64,
        returnedGeneration: UInt64,
        generationAccepted: Bool,
        executedOnMainThread: Bool,
        entryCount: Int?,
        error: ClassifiedFolderAccessError?
    ) {
        self.category = category
        self.requestedGeneration = requestedGeneration
        self.returnedGeneration = returnedGeneration
        self.generationAccepted = generationAccepted
        self.executedOnMainThread = executedOnMainThread
        self.entryCount = entryCount
        self.error = error
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(String.self, forKey: .category)
        requestedGeneration = try container.decode(UInt64.self, forKey: .requestedGeneration)
        returnedGeneration = try container.decode(UInt64.self, forKey: .returnedGeneration)
        generationAccepted = try container.decode(Bool.self, forKey: .generationAccepted)
        executedOnMainThread = try container.decode(Bool.self, forKey: .executedOnMainThread)
        entryCount = try container.decodeIfPresent(Int.self, forKey: .entryCount)
        error = try container.decodeIfPresent(ClassifiedFolderAccessError.self, forKey: .error)
    }
}

struct FixtureResult: Codable, Equatable, Sendable {
    let name: String
    let expectedCategory: String
    let entryCount: Int?
    let enumerationError: ClassifiedFolderAccessError?
    let posixProbeErrno: Int32?
    let generation: UInt64
    let executedOnMainThread: Bool

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name, expectedCategory, entryCount, enumerationError
        case posixProbeErrno, generation, executedOnMainThread
    }

    init(
        name: String,
        expectedCategory: String,
        entryCount: Int?,
        enumerationError: ClassifiedFolderAccessError?,
        posixProbeErrno: Int32?,
        generation: UInt64,
        executedOnMainThread: Bool
    ) {
        self.name = name
        self.expectedCategory = expectedCategory
        self.entryCount = entryCount
        self.enumerationError = enumerationError
        self.posixProbeErrno = posixProbeErrno
        self.generation = generation
        self.executedOnMainThread = executedOnMainThread
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        expectedCategory = try container.decode(String.self, forKey: .expectedCategory)
        entryCount = try container.decodeIfPresent(Int.self, forKey: .entryCount)
        enumerationError = try container.decodeIfPresent(
            ClassifiedFolderAccessError.self,
            forKey: .enumerationError
        )
        posixProbeErrno = try container.decodeIfPresent(Int32.self, forKey: .posixProbeErrno)
        generation = try container.decode(UInt64.self, forKey: .generation)
        executedOnMainThread = try container.decode(Bool.self, forKey: .executedOnMainThread)
    }
}

struct FullOutput: Codable, Sendable {
    let probe: String
    let protectedLocations: [LocationResult]
    let fixtureResults: [FixtureResult]
    let fixtureCleanupOK: Bool

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case probe, protectedLocations, fixtureResults, fixtureCleanupOK
    }

    init(
        probe: String,
        protectedLocations: [LocationResult],
        fixtureResults: [FixtureResult],
        fixtureCleanupOK: Bool
    ) {
        self.probe = probe
        self.protectedLocations = protectedLocations
        self.fixtureResults = fixtureResults
        self.fixtureCleanupOK = fixtureCleanupOK
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        probe = try container.decode(String.self, forKey: .probe)
        protectedLocations = try container.decode([LocationResult].self, forKey: .protectedLocations)
        fixtureResults = try container.decode([FixtureResult].self, forKey: .fixtureResults)
        fixtureCleanupOK = try container.decode(Bool.self, forKey: .fixtureCleanupOK)
    }
}

final class GenerationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func next() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    var current: UInt64 { lock.withLock { value } }
}

final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func set(_ value: Value) { lock.withLock { self.value = value } }
    func get() -> Value? { lock.withLock { value } }
}

final class BackgroundEnumerator: @unchecked Sendable {
    private let queue: DispatchQueue
    private let activity = DispatchGroup()
    private let beforeEnumeration: @Sendable () -> Void

    init(
        label: String,
        beforeEnumeration: @escaping @Sendable () -> Void = {}
    ) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
        self.beforeEnumeration = beforeEnumeration
    }

    func enumerate(
        path: String,
        generation: UInt64,
        timeoutSeconds: Double
    ) throws -> EnumerationAttempt {
        let completion = DispatchSemaphore(value: 0)
        let box = LockedBox<EnumerationAttempt>()
        activity.enter()
        queue.async { [activity, beforeEnumeration] in
            defer { activity.leave() }
            beforeEnumeration()
            let executedOnMainThread = Thread.isMainThread
            do {
                let entries = try FileManager.default.contentsOfDirectory(atPath: path)
                box.set(EnumerationAttempt(
                    generation: generation,
                    executedOnMainThread: executedOnMainThread,
                    entryCount: entries.count,
                    error: nil
                ))
            } catch {
                box.set(EnumerationAttempt(
                    generation: generation,
                    executedOnMainThread: executedOnMainThread,
                    entryCount: nil,
                    error: classifyEnumerationError(error as NSError)
                ))
            }
            completion.signal()
        }

        let timeout = DispatchTime.now() + .milliseconds(Int(timeoutSeconds * 1_000))
        guard completion.wait(timeout: timeout) == .success else {
            throw ProbeError.backgroundTimeout(path)
        }
        guard let result = box.get() else { throw ProbeError.backgroundResultMissing }
        return result
    }

    func waitUntilIdle(timeoutSeconds: Double) -> Bool {
        activity.wait(
            timeout: .now() + .milliseconds(Int(timeoutSeconds * 1_000))
        ) == .success
    }
}

func requireCurrent(_ attempt: EnumerationAttempt, currentGeneration: UInt64) throws {
    guard attempt.generation == currentGeneration else {
        throw ProbeError.staleResult(
            returned: attempt.generation,
            current: currentGeneration
        )
    }
}

func protectedLocationResult(
    category: String,
    path: String,
    counter: GenerationCounter,
    enumerator: BackgroundEnumerator
) throws -> LocationResult {
    let requested = counter.next()
    let attempt = try enumerator.enumerate(
        path: path,
        generation: requested,
        timeoutSeconds: 5
    )
    try requireCurrent(attempt, currentGeneration: counter.current)
    return LocationResult(
        category: category,
        requestedGeneration: requested,
        returnedGeneration: attempt.generation,
        generationAccepted: true,
        executedOnMainThread: attempt.executedOnMainThread,
        entryCount: attempt.entryCount,
        error: attempt.error
    )
}
