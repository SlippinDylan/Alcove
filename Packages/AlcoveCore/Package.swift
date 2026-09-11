// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AlcoveCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AlcoveCore", targets: ["AlcoveCore"])
    ],
    targets: [
        .target(name: "AlcoveCore"),
        .testTarget(name: "AlcoveCoreTests", dependencies: ["AlcoveCore"])
    ]
)
