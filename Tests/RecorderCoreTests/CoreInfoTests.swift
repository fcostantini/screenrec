import Foundation
import Testing
@testable import RecorderCore

@Test func versionIsSemver() {
    let parts = CoreInfo.version.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}

/// `CoreInfo.version` is a hand-written copy of the repo-root `VERSION` file (the bundle's single
/// source, stamped by bundle.sh). Nothing feeds one from the other, so this pins them together:
/// bump `VERSION`, forget `CoreInfo`, and the gate fails here rather than shipping two versions.
/// `#filePath` locates the repo regardless of the test's working directory.
@Test func versionMatchesTheVersionFile() throws {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // RecorderCoreTests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // repo root
    let fileVersion = try String(contentsOf: repoRoot.appendingPathComponent("VERSION"),
                                 encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(CoreInfo.version == fileVersion)
}
