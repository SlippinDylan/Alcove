// WorkerQueue.swift — Phase 0.5C1 background directory enumeration
// Explicit worker queue boundary: never MainActor.

import Dispatch
import Foundation

/// An explicit background worker queue for blocking directory enumeration.
///
/// The worker queue is a concurrent `DispatchQueue` that is never `MainActor`.
/// The `execute` method dispatches a closure to the worker and blocks the
/// calling thread until the result is available. This guarantees that the
/// caller always receives the result on the same thread that called `execute`,
/// while the closure itself runs on the background queue.
final class WorkerQueue: @unchecked Sendable {
    /// The concurrent queue allows a newer request to complete while an older
    /// synchronous filesystem call is still blocked.
    let queue: DispatchQueue

    /// The dispatch-specific key used to verify that code is running on this queue.
    let queueKey = DispatchSpecificKey<UInt8>()

    init(label: String) {
        queue = DispatchQueue(label: label, attributes: .concurrent)
        queue.setSpecific(key: queueKey, value: 1)
    }

    /// Returns `true` when called from the worker queue itself.
    var isCurrentQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) == 1
    }

    /// Dispatches `work` to the worker queue and blocks the calling thread
    /// until the closure completes. The closure runs on the background queue;
    /// the caller receives the result synchronously on its own thread.
    ///
    /// This design ensures that blocking file-system work never runs on
    /// `MainActor` while the coordinator can still receive and evaluate the
    /// result on the main thread.
    func execute<T: Sendable>(
        timeout: DispatchTime = .now() + 5,
        _ work: @escaping @Sendable () throws -> T
    ) throws -> T {
        let resultBox = LockedValue<Result<T, Error>?>(nil)
        let done = DispatchSemaphore(value: 0)

        queue.async {
            let result: Result<T, Error>
            do {
                result = .success(try work())
            } catch {
                result = .failure(error)
            }
            resultBox.set(result)
            done.signal()
        }

        guard done.wait(timeout: timeout) == .success else {
            throw EnumerationError.workerTimedOut
        }

        // After the semaphore signals, the result is guaranteed to be set.
        // Use force-unwrap-free access: the non-nil check is structural.
        if let result = resultBox.get() {
            return try result.get()
        }
        // This path is unreachable because the semaphore guarantees the result
        // was set. Throw a typed error to satisfy the compiler.
        throw EnumerationError.enumerationFailed(
            path: "(internal)",
            domain: "AlcoveSpike",
            code: -1,
            description: "WorkerQueue.execute: result was not set after semaphore"
        )
    }
}

/// A thread-safe box for passing values across queue boundaries.
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
