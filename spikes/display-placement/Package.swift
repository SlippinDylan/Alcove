// swift-tools-version: 6.0
// Package.swift — Alcove Spike 0.2 Display Placement
//
// Phase 0.2A: pure placement geometry (UI-free).
// Phase 0.2B: AppKit-backed display inventory and notification probe.
// Disposable spike code, not production AlcoveCore.

import PackageDescription

let package = Package(
    name: "DisplayPlacement",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "DisplayPlacement",
            targets: ["DisplayPlacement"]
        ),
        .library(
            name: "DisplayInventory",
            targets: ["DisplayInventory"]
        ),
        .executable(
            name: "DisplayProbe",
            targets: ["DisplayProbe"]
        ),
    ],
    targets: [
        // Phase 0.2A — UI-free placement geometry (unchanged).
        .target(
            name: "DisplayPlacement",
            path: "Sources/DisplayPlacement"
        ),
        // Phase 0.2B — AppKit-backed display inventory library.
        .target(
            name: "DisplayInventory",
            dependencies: [],
            path: "Sources/DisplayInventory"
        ),
        // Phase 0.2B — CLI diagnostic probe.
        .executableTarget(
            name: "DisplayProbe",
            dependencies: ["DisplayInventory"],
            path: "Sources/DisplayProbe"
        ),
        // Phase 0.2A tests (unchanged).
        .testTarget(
            name: "DisplayPlacementTests",
            dependencies: ["DisplayPlacement"],
            path: "Tests/DisplayPlacementTests"
        ),
        // Phase 0.2B tests.
        .testTarget(
            name: "DisplayInventoryTests",
            dependencies: ["DisplayInventory"],
            path: "Tests/DisplayInventoryTests"
        ),
    ]
)
