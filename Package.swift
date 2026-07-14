// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screenrec",
    platforms: [.macOS(.v15)],
    targets: [
        // All capture/encode/write logic. Must never import AppKit/SwiftUI (ADR in docs/01).
        .target(
            name: "RecorderCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Dev harness and primary verification surface until M4 (ADR-011).
        .executableTarget(
            name: "screenrec-cli",
            dependencies: ["RecorderCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Menu-bar app shell (fleshed out in M4).
        .executableTarget(
            name: "ScreenRecApp",
            dependencies: ["RecorderCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RecorderCoreTests",
            dependencies: ["RecorderCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
