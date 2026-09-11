import Foundation

private func writeStandardError(_ message: String) {
    guard let data = "\(message)\n".data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
}

private func run() -> Int32 {
    let arguments = CommandLine.arguments
    guard arguments.count == 2 else {
        writeStandardError("Usage: folder-location-probe <directory>")
        return 64
    }

    do {
        let inspection = try FoundationFolderLocationValidator.inspect(path: arguments[1])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(inspection)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
        return 0
    } catch {
        writeStandardError(String(describing: error))
        return 1
    }
}

exit(run())
