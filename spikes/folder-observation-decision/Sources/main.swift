import CoreServices
import Foundation

private struct RecoveryProbeOutput: Encodable {
    let rawFlags: UInt32
    let decodedFlags: [String]
    let action: FSEventsRecoveryAction
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

private func run() -> Int32 {
    let arguments = CommandLine.arguments
    guard arguments.count == 2,
          let rawFlags = UInt32(arguments[1]) else {
        writeError("Usage: fsevents-recovery-probe <raw-flags-uint32>")
        return 64
    }

    do {
        let output = RecoveryProbeOutput(
            rawFlags: rawFlags,
            decodedFlags: decodeFSEventFlags(rawFlags),
            action: FSEventsRecoveryPolicy.action(for: rawFlags)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data([0x0a]))
        return 0
    } catch {
        writeError(String(describing: error))
        return 1
    }
}

exit(run())
