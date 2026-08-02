// main.swift — Phase 0.5A DispatchSource directory observer probe
// Observes a supplied existing directory for a bounded duration and prints
// typed event diagnostics. Exits nonzero on setup/runtime errors.

import Darwin
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
    fputs("Usage: folder-observer-probe <directory> [duration-seconds]\n", stderr)
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

    // Validate directory exists.
    var statBuf = stat()
    guard stat(directoryPath, &statBuf) == 0 else {
        fputs("Error: Path not found: \(directoryPath)\n", stderr)
        return 1
    }
    guard (statBuf.st_mode & S_IFMT) == S_IFDIR else {
        fputs("Error: Not a directory: \(directoryPath)\n", stderr)
        return 1
    }

    print("=== Alcove Spike 0.5A — DispatchSource Folder Observer Probe ===")
    print("Directory: \(directoryPath)")
    print("Duration:  \(duration)s")
    print("")

    let eventCounter = EventCounter()
    let observer = DispatchSourceFolderObserver { record in
        let count = eventCounter.increment()
        print("[\(String(format: "%.4f", record.timestamp))] Event #\(count)")
        print("  mask:       \(record.eventDescription)")
        print("  generation: \(record.generation)")
    }

    do {
        try observer.start(path: directoryPath)
    } catch {
        fputs("Error: Failed to start observer: \(error)\n", stderr)
        return 1
    }

    print("Observer started. Waiting \(duration)s for events...")
    print("(Create, rename, or delete files in the directory to trigger events.)")
    print("")

    // Run for the specified duration.
    Thread.sleep(forTimeInterval: duration)

    print("")
    print("--- Stopping observer ---")
    do {
        let teardown = try observer.stopAndWait(timeout: .now() + 3)
        guard teardown.descriptorWasOpened, teardown.descriptorWasClosed else {
            fputs("Error: observer teardown did not close an opened descriptor.\n", stderr)
            return 1
        }
    } catch {
        fputs("Error: observer teardown failed: \(error)\n", stderr)
        return 1
    }

    print("Observer stopped.")
    print("Total events: \(eventCounter.value)")
    print("Generation at stop: \(observer.currentGeneration)")

    // Verify descriptor is closed.
    let fdAfterStop = observer.openedFileDescriptor
    if fdAfterStop == -1 {
        print("Descriptor closed: YES")
    } else {
        print("Descriptor closed: NO (fd=\(fdAfterStop))")
        return 1
    }

    print("")
    print("=== Probe Complete ===")
    return 0
}

exit(main())
