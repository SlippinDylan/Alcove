// main.swift — Phase 0.5C1 background directory enumeration probe
// Enumerates a supplied existing directory on a background worker queue
// and prints a deterministic snapshot with generation/worker diagnostics.
// Exits nonzero on failure.

import Dispatch
import Foundation

func usage() {
    fputs("Usage: folder-enumeration-probe <directory>\n", stderr)
    fputs("  directory: Path to an existing directory to enumerate.\n", stderr)
}

func main() -> Int32 {
    let args = CommandLine.arguments
    guard args.count == 2 else {
        usage()
        return 64
    }

    let directoryPath = args[1]

    print("=== Alcove Spike 0.5C1 — Background Directory Enumeration Probe ===")
    print("Directory: \(directoryPath)")
    print("")

    let worker = WorkerQueue(label: "com.alcove.spike.folder-enumeration.probe")
    let coordinator = Coordinator()
    let enumerator = DirectoryEnumerator.defaultManager()
    let runner = EnumerationRequestRunner(worker: worker, enumerator: enumerator)

    print("Worker queue: \(worker.queue.label)")
    print("Worker is current queue at probe start: \(worker.isCurrentQueue ? "YES" : "NO")")
    print("Main thread: \(Thread.isMainThread ? "YES" : "NO")")
    print("")

    let generation: UInt64
    do {
        generation = try coordinator.submit()
    } catch {
        fputs("Error: \(error)\n", stderr)
        return 1
    }
    let token = CancellationToken()

    // Run enumeration on the worker queue (off MainActor).
    let snapshot: DirectorySnapshot
    do {
        snapshot = try runner.run(
            path: directoryPath,
            generation: generation,
            token: token
        )
    } catch {
        fputs("Error: Enumeration failed: \(error)\n", stderr)
        return 1
    }

    // Accept into coordinator.
    let accepted = coordinator.accept(snapshot: snapshot, token: token)
    guard accepted else {
        fputs("Error: Coordinator rejected the snapshot.\n", stderr)
        return 1
    }

    guard let published = coordinator.currentSnapshot else {
        fputs("Error: Coordinator did not publish the snapshot.\n", stderr)
        return 1
    }

    print("Snapshot: \(published)")
    print("Generation: \(published.generation)")
    print("Current coordinator generation: \(coordinator.currentGeneration)")
    print("Published matches accepted: \(published == snapshot ? "YES" : "NO")")
    print("")

    // Print deterministic child list.
    print("--- Immediate Children (\(published.count)) ---")
    for (index, entry) in published.entries.enumerated() {
        print("  [\(index)] \(entry)")
    }

    if !published.metadataErrors.isEmpty {
        print("")
        print("--- Metadata Errors (\(published.metadataErrors.count)) ---")
        for error in published.metadataErrors {
            print("  \(error)")
        }
    }

    // Verify no grandchildren (entries should only be direct children).
    print("")
    print("--- Verification ---")
    let targetPath = URL(fileURLWithPath: directoryPath).standardizedFileURL.path
    for entry in published.entries {
        let entryParentPath = entry.url.deletingLastPathComponent().standardizedFileURL.path
        guard entryParentPath == targetPath else {
            fputs("Error: Entry \(entry.name) is not an immediate child of \(directoryPath)\n", stderr)
            return 1
        }
    }
    print("All entries are immediate children: YES")
    print("Snapshot accepted into coordinator: YES")
    print("Worker queue label: \(worker.queue.label)")
    print("")
    print("=== Probe Complete ===")
    return 0
}

exit(main())
