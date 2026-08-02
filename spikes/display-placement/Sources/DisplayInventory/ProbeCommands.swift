// ProbeCommands.swift
// Alcove Spike 0.2B — CLI command logic for the display probe.
//
// Separated from the `@main` entry point so tests can call `runProbe()`
// directly without launching a subprocess.
// Disposable spike code, not production AlcoveCore.

import AppKit
import Foundation

/// Run the probe CLI with the given arguments.
///
/// All `NSScreen`/`NSApplication` access occurs on `MainActor`.
/// Returns an exit code: 0 = success, 1 = error.
@MainActor
public func runProbe(arguments: [String]) async -> Int32 {
    // Ensure NSApplication exists so the run loop is available for
    // notification delivery.
    _ = NSApplication.shared

    let args = arguments

    guard args.count >= 2 else {
        printProbeUsage()
        return 1
    }

    let command = args[1]

    switch command {
    case "snapshot":
        guard args.count == 2 else {
            fputs("Error: snapshot does not accept options\n", stderr)
            return 1
        }
        return runProbeSnapshot()
    case "observe":
        return await runProbeObserve(args: Array(args.dropFirst(2)))
    default:
        fputs("Error: unknown command '\(command)'\n", stderr)
        printProbeUsage()
        return 1
    }
}

// MARK: - Commands

/// Take a one-time snapshot and emit JSON to stdout.
@MainActor
private func runProbeSnapshot() -> Int32 {
    do {
        let records = ScreenInventory.capture()
        let data = try ScreenInventory.encodeJSON(records)
        guard let json = String(data: data, encoding: .utf8) else {
            fputs("Error: JSON encoding produced non-UTF-8 output\n", stderr)
            return 1
        }
        print(json)
        return 0
    } catch {
        fputs("Error: \(error)\n", stderr)
        return 1
    }
}

/// Observe screen-parameter notifications for a bounded duration.
@MainActor
private func runProbeObserve(args: [String]) async -> Int32 {
    guard let seconds = parseProbeDuration(args: args) else {
        return 1
    }

    var events: [ScreenObservationEvent] = []
    let startDate = Date()

    let observer = ScreenObserver { records in
        events.append(
            ScreenObservationEvent(
                sequence: events.count,
                elapsedSeconds: Date().timeIntervalSince(startDate),
                screens: records
            )
        )
    }
    observer.start()
    do {
        try await Task.sleep(for: .seconds(seconds))
    } catch {
        observer.stop()
        fputs("Error: observation was cancelled\n", stderr)
        return 1
    }
    observer.stop()

    do {
        let data = try ScreenInventory.encodeJSON(events)
        guard let json = String(data: data, encoding: .utf8) else {
            fputs("Error: JSON encoding produced non-UTF-8 output\n", stderr)
            return 1
        }
        print(json)
        return 0
    } catch {
        fputs("Error: \(error)\n", stderr)
        return 1
    }
}

// MARK: - Argument Parsing

/// Parse `--seconds <positive finite value>` from argument list.
public func parseProbeDuration(args: [String]) -> Double? {
    guard args.count == 2, args[0] == "--seconds" else {
        fputs("Error: observe requires --seconds <positive value>\n", stderr)
        return nil
    }

    guard let value = Double(args[1]) else {
        fputs("Error: '\(args[1])' is not a valid number\n", stderr)
        return nil
    }

    guard value.isFinite && value > 0 else {
        fputs("Error: duration must be positive and finite, got \(value)\n", stderr)
        return nil
    }

    return value
}

/// One bounded-observation event and its fresh screen snapshot.
public struct ScreenObservationEvent: Codable, Sendable, Equatable {
    public let sequence: Int
    public let elapsedSeconds: Double
    public let screens: [ScreenRecord]

    public init(sequence: Int, elapsedSeconds: Double, screens: [ScreenRecord]) {
        self.sequence = sequence
        self.elapsedSeconds = elapsedSeconds
        self.screens = screens
    }
}

private func printProbeUsage() {
    fputs("""
    Usage: DisplayProbe <command> [options]

    Commands:
      snapshot                Take a one-time display inventory snapshot (JSON)
      observe --seconds <N>  Observe screen-parameter changes for N seconds

    """, stderr)
}
