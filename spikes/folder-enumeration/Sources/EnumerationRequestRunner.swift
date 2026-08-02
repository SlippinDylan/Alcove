import Dispatch
import Foundation

/// Runs one synchronous enumeration behind the worker boundary.
///
/// Cancellation is checked before scheduling, immediately before filesystem
/// work, and after that work returns. It suppresses publication but cannot
/// interrupt `contentsOfDirectory` while that call is executing.
struct EnumerationRequestRunner: Sendable {
    let worker: WorkerQueue
    let enumerator: DirectoryEnumerator

    func run(
        path: String,
        generation: UInt64,
        token: CancellationToken,
        timeout: DispatchTime = .now() + 5
    ) throws -> DirectorySnapshot {
        guard !token.isCancelled else { throw EnumerationError.cancelled }
        let result = try worker.execute(timeout: timeout) {
            guard !token.isCancelled else { throw EnumerationError.cancelled }
            try DirectoryEnumerator.validatePath(path)
            let snapshot = try DirectorySnapshot.enumerate(
                path: path,
                generation: generation,
                enumerator: enumerator
            )
            guard !token.isCancelled else { throw EnumerationError.cancelled }
            return (snapshot, Thread.isMainThread, worker.isCurrentQueue)
        }
        guard !result.1, result.2 else {
            throw EnumerationError.workerBoundaryViolation
        }
        return result.0
    }
}
