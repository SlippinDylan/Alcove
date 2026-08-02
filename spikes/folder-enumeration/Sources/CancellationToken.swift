// CancellationToken.swift — Phase 0.5C1 background directory enumeration
// Cooperative cancellation token for enumeration requests.

import Foundation

/// Cooperative cancellation token for an enumeration request.
///
/// Cancellation may suppress acceptance before or after a synchronous
/// enumeration call, but does not interrupt that call midway. The caller checks
/// `isCancelled` before starting work and after the blocking call returns.
/// If cancelled, the caller returns a typed cancelled outcome without
/// publishing state.
final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    /// Marks the token as cancelled. This is idempotent and thread-safe.
    func markCancelled() {
        lock.withLock { cancelled = true }
    }

    /// Whether the token has been marked as cancelled.
    var isCancelled: Bool {
        lock.withLock { cancelled }
    }
}
