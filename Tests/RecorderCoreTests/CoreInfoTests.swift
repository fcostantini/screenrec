import Foundation
import Testing
@testable import RecorderCore

@Test func versionIsSemver() {
    let parts = CoreInfo.version.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}

/// `#filePath` locates the repo regardless of the test's working directory.
private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // RecorderCoreTests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // repo root
}

private func repoFile(_ name: String) throws -> String {
    try String(contentsOf: repoRoot().appendingPathComponent(name), encoding: .utf8)
}

/// `CoreInfo.version` is a hand-written copy of the repo-root `VERSION` file (the bundle's single
/// source, stamped by bundle.sh). Nothing feeds one from the other, so this pins them together:
/// bump `VERSION`, forget `CoreInfo`, and the gate fails here rather than shipping two versions.
@Test func versionMatchesTheVersionFile() throws {
    let fileVersion = try repoFile("VERSION")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(CoreInfo.version == fileVersion)
}

/// `release.sh` publishes CHANGELOG.md's `## <version>` section as the release notes and has no
/// `git log` to fall back on, so a version with no section would publish a release that says
/// nothing. The script refuses that too; this catches it at commit time instead of release time.
@Test func theChangelogDescribesThisVersion() throws {
    let changelog = try repoFile("CHANGELOG.md")
    let section = changelog
        .components(separatedBy: "\n## ")
        .first { $0.hasPrefix(CoreInfo.version + "\n") }   // + "\n", or 1.17.1 matches 1.17.10
    let body = section?
        .dropFirst(CoreInfo.version.count)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(section != nil, "CHANGELOG.md has no '## \(CoreInfo.version)' section")
    #expect(body?.isEmpty == false, "CHANGELOG.md's \(CoreInfo.version) section is empty")
}
