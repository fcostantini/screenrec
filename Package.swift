// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screenrec",
    platforms: [.macOS(.v15)],
    targets: [
        // All capture/encode/write logic. Must never import AppKit/SwiftUI (ADR in docs/01).
        .target(
            name: "RecorderCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Dev harness and primary verification surface until M4 (ADR-011).
        .executableTarget(
            name: "screenrec-cli",
            dependencies: ["RecorderCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The app's state and view models. Like RecorderCore it imports no AppKit/SwiftUI,
        // which is the point: it keeps everything the UI decides unit-testable without a UI
        // host (there is no Xcode here to run one). Views stay in ScreenRecApp.
        .target(
            name: "AppCore",
            dependencies: ["RecorderCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The app's AppKit shell and SwiftUI windows. A library, not part of the executable, for
        // one reason: SPM cannot link an executable target into a test target, and this is where
        // the menu's decisions live (M29-T1).
        .target(
            name: "AppShell",
            dependencies: ["AppCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Three lines and the bundle's payload. `Resources/` stays here because Scripts/bundle.sh
        // copies it from this path, and it is bundle payload rather than code.
        .executableTarget(
            name: "ScreenRecApp",
            dependencies: ["AppShell"],
            // Both are assembled into the .app bundle by Scripts/bundle.sh, not compiled —
            // exclude them so SPM doesn't treat them as unhandled resources.
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // ⚠️ The one target deliberately left in v5 (M25-T3, Franco's ruling 2026-07-31). Flipping it
        // means rewriting three `DispatchGroup.wait(timeout:)` calls that M15-T1 added so a drain
        // that never leaves *fails* the test instead of hanging it — Swift 6 bans blocking waits in
        // async contexts, and the async equivalent races a continuation against a timeout. This
        // project has twice shipped tests that silently stopped testing; that trade is not worth a
        // uniform setting. Everything that ships is v6.
        .testTarget(
            name: "RecorderCoreTests",
            dependencies: ["RecorderCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // RecorderCore is declared, not inherited: the tests build the `EngineEvent`s they feed
        // in, so relying on it leaking through AppCore's own dependency would break the day
        // that leak closes.
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "RecorderCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Reaches `AppShell` through `@testable`, so the menu's types stay internal (M29-T1).
        .testTarget(
            name: "AppShellTests",
            dependencies: ["AppShell", "AppCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
