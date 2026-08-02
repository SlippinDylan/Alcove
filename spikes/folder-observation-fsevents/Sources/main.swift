// main.swift — Phase 0.5B FSEvents directory observer probe
// Observes a supplied existing directory for a bounded duration and prints
// typed event diagnostics. Exits nonzero on setup/runtime errors.

import Dispatch
import Foundation

/// Thread-safe counter for the probe's @Sendable event closure.
private final class EventCounter: @unchecked Sendable {
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

func usage() {
    fputs("Usage: folder-observer-fsevents-probe <directory> [duration-seconds]\n", stderr)
    fputs("  directory:        Path to an existing directory to observe.\n", stderr)
    fputs("  duration-seconds: Observation duration (default: 5, max: 60).\n", stderr)
}

func main() -> Int32 {
    let args = CommandLine.arguments
    guard (2...3).contains(args.count) else {
        usage()
        return 64
    }

    let directoryPath = args[1]
    var duration: Double = 5.0

    if args.count >= 3 {
        guard let parsed = Double(args[2]), parsed > 0, parsed <= 60 else {
            fputs("Error: duration must be a positive number ≤ 60.\n", stderr)
            return 64
        }
        duration = parsed
    }

    print("=== Alcove Spike 0.5B — FSEvents Folder Observer Probe ===")
    print("Directory: \(directoryPath)")
    print("Duration:  \(duration)s")
    print("Latency:   \(FSEventsFolderObserver.candidateLatency)s (candidate)")
    print("Flags:     FileEvents | WatchRoot | UseCFTypes")
    print("")

    let eventCounter = EventCounter()
    let observer = FSEventsFolderObserver { record in
        let count = eventCounter.increment()
        print("[\(String(format: "%.4f", record.timestamp))] Event #\(count)")
        print("  path:   \(record.path)")
        print("  id:     \(record.eventID)")
        print("  flags:  \(record.flagDescription)")
        print("  gen:    \(record.generation)")
    }

    do {
        try observer.start(path: directoryPath)
    } catch {
        fputs("Error: Failed to start observer: \(error)\n", stderr)
        return 1
    }

    print("Observer started (generation: \(observer.currentGeneration)).")
    print("Waiting \(duration)s for events...")
    print("(Create, rename, or delete files in the directory to trigger events.)")
    print("")

    // Run for the specified duration.
    Thread.sleep(forTimeInterval: duration)

    print("")
    print("--- Stopping observer ---")
    do {
        try observer.stopAndWait(timeout: .now() + 3)
    } catch {
        fputs("Error: Failed to stop observer cleanly: \(error)\n", stderr)
        return 1
    }
    let finalState = observer.lifecycleState
    guard finalState == .stopped else {
        fputs("Error: observer did not reach stopped state (got \(finalState))\n", stderr)
        return 1
    }

    print("Observer stopped.")
    print("Total events: \(eventCounter.value)")
    print("Generation at stop: \(observer.currentGeneration)")
    print("")
    print("=== Probe Complete ===")
    return 0
}

exit(main())
