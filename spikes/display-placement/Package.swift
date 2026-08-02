// swift-tools-version: 6.0
// Package.swift — Alcove Spike 0.2A Display Placement Geometry
//
// Pure model and XCTest suite for movable-range-normalized placement math.
// UI-free: imports CoreGraphics and Foundation only; no AppKit dependency.

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
    ],
    targets: [
        .target(
            name: "DisplayPlacement",
            path: "Sources/DisplayPlacement"
        ),
        .testTarget(
            name: "DisplayPlacementTests",
            dependencies: ["DisplayPlacement"],
            path: "Tests/DisplayPlacementTests"
        ),
    ]
)
