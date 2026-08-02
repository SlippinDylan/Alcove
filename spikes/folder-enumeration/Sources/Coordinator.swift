// Coordinator.swift — Phase 0.5C1 background directory enumeration
// Generation-based coordinator that rejects stale and cancelled results.

import Foundation

/// Thread-safe coordinator that manages generation-based enumeration requests.
///
/// Every request receives a monotonically increasing generation. Only the
/// current generation may be accepted into coordinator state. Stale and
/// cancelled results are rejected without publishing.
final class Coordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var acceptedSnapshot: DirectorySnapshot?

    init(initialGeneration: UInt64 = 0) {
        generation = initialGeneration
    }

    /// The currently accepted snapshot, if any.
    var currentSnapshot: DirectorySnapshot? {
        lock.withLock { acceptedSnapshot }
    }

    /// The current generation counter.
    var currentGeneration: UInt64 {
        lock.withLock { generation }
    }

    /// Submits a new request and returns its generation.
    ///
    /// Each call increments the generation monotonically. The caller passes this
    /// generation to the worker so the result carries the correct generation tag.
    @discardableResult
    func submit() throws -> UInt64 {
        try lock.withLock {
            guard generation < UInt64.max else {
                throw EnumerationError.generationExhausted
            }
            generation += 1
            return generation
        }
    }

    /// Attempts to accept a snapshot into coordinator state.
    ///
    /// The snapshot is rejected when:
    /// - The token is cancelled (cancellation suppresses acceptance).
    /// - The snapshot's generation does not match the current generation (stale).
    ///
    /// Returns `true` when the snapshot was accepted, `false` when rejected.
    @discardableResult
    func accept(
        snapshot: DirectorySnapshot,
        token: CancellationToken
    ) -> Bool {
        lock.withLock {
            guard !token.isCancelled else { return false }
            guard snapshot.generation == generation else { return false }
            acceptedSnapshot = snapshot
            return true
        }
    }
}
