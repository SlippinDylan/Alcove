// main.swift
// Alcove Spike 0.2B — CLI diagnostic probe entry point.
//
// Thin `@main` wrapper. Command logic lives in `DisplayInventory.ProbeCommands`
// so tests can call `runProbe()` directly.
// Disposable spike code, not production AlcoveCore.

import DisplayInventory
import Foundation

@main
struct ProbeMain {
    static func main() async {
        let code = await runProbe(arguments: CommandLine.arguments)
        if code != 0 {
            exit(code)
        }
    }
}
