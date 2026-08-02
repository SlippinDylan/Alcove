// main.swift
// Alcove Spike 0.4A — Material Compatibility Boundary Bootstrap
// Application entry point.

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
