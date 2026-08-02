import Darwin
import Foundation

private enum Command: String {
    case protectedLocations = "protected-locations"
    case fixtures
    case all
}

private func execute(_ command: Command) throws -> FullOutput {
    let counter = GenerationCounter()
    let enumerator = BackgroundEnumerator(label: "com.alcove.spike.folder-access")
    var protectedResults: [LocationResult] = []
    var fixtureResults: [FixtureResult] = []

    if command == .protectedLocations || command == .all {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locations = [
            ("desktop", home.appendingPathComponent("Desktop").path),
            ("documents", home.appendingPathComponent("Documents").path),
            ("downloads", home.appendingPathComponent("Downloads").path)
        ]
        for (category, path) in locations {
            protectedResults.append(try protectedLocationResult(
                category: category,
                path: path,
                counter: counter,
                enumerator: enumerator
            ))
        }
    }

    if command == .fixtures || command == .all {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "alcove-folder-access-\(UUID().uuidString)",
            isDirectory: true
        )
        fixtureResults = try runOwnedFixtureTransaction(
            root: root,
            counter: counter,
            enumerator: enumerator
        )
    }

    return FullOutput(
        probe: "folder-access-errors",
        protectedLocations: protectedResults,
        fixtureResults: fixtureResults,
        fixtureCleanupOK: true
    )
}

private func printUsage() {
    fputs(
        "Usage: folder-access-probe protected-locations|fixtures|all\n",
        stderr
    )
}

guard CommandLine.arguments.count == 2,
      let command = Command(rawValue: CommandLine.arguments[1]) else {
    printUsage()
    exit(64)
}

do {
    let output = try execute(command)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(output)
    guard let json = String(data: data, encoding: .utf8) else {
        throw ProbeError.filesystem("JSON output is not UTF-8")
    }
    print(json)
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
