import Foundation
import Testing
@testable import RecorderCore

@Suite struct OutputLocationTests {
    /// 2026-07-14 10:12:34 UTC — fixed so timestamp assertions don't depend on the
    /// machine's clock or zone.
    static let fixedDate: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 14
        components.hour = 10; components.minute = 12; components.second = 34
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }()

    static let utc = TimeZone(identifier: "UTC")!

    @Test func timestampMatchesExpectedFormat() {
        #expect(OutputLocation.timestamp(for: Self.fixedDate, timeZone: Self.utc) == "2026-07-14 at 10.12.34")
    }

    @Test func noCollisionReturnsBaseName() {
        let name = OutputLocation.resolvedFileName(base: "Recording X", ext: "mov") { _ in false }
        #expect(name == "Recording X.mov")
    }

    @Test func firstCollisionAppendsTwo() {
        let name = OutputLocation.resolvedFileName(base: "Recording X", ext: "mov") { $0 == "Recording X.mov" }
        #expect(name == "Recording X 2.mov")
    }

    @Test func consecutiveCollisionsIncrement() {
        let taken: Set<String> = ["Recording X.mov", "Recording X 2.mov"]
        let name = OutputLocation.resolvedFileName(base: "Recording X", ext: "mov") { taken.contains($0) }
        #expect(name == "Recording X 3.mov")
    }

    @Test func defaultDirectoryIsMovies() {
        #expect(OutputLocation.defaultDirectory().lastPathComponent == "Movies")
    }

    @Test func preflightAccessibleForTempDirectory() {
        #expect(OutputLocation.preflight(FileManager.default.temporaryDirectory) == .accessible)
    }

    @Test func preflightMissingDirectoryReportsMissingNotPermissions() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenrec-missing-\(UUID().uuidString)")
        guard case let .inaccessible(reason) = OutputLocation.preflight(missing) else {
            Issue.record("expected .inaccessible for a nonexistent directory")
            return
        }
        // A missing folder must not be misdiagnosed as a TCC/permissions problem.
        #expect(reason.contains("doesn't exist"))
        #expect(!reason.contains("Files and Folders"))
    }

    @Test func preflightInaccessibleForReadOnlyDirectory() throws {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("screenrec-readonly-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? fileManager.removeItem(at: dir)
        }
        // Read+execute but not write: opendir would pass, a write probe must not.
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        guard case let .inaccessible(reason) = OutputLocation.preflight(dir) else {
            Issue.record("expected .inaccessible for a read-only directory")
            return
        }
        #expect(reason.contains("Can't write"))
    }

    @Test func newRecordingURLComposesDirectoryAndName() {
        let dir = FileManager.default.temporaryDirectory
        let url = OutputLocation(directory: dir).newRecordingURL(date: Self.fixedDate, timeZone: Self.utc)
        #expect(url.lastPathComponent == "Recording 2026-07-14 at 10.12.34.mov")
        #expect(url.path.hasPrefix(dir.path))
    }

    @Test func reserveKeepsPlaceholderSoSameSecondNamesDontCollide() throws {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("reserve-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }
        let location = OutputLocation(directory: dir)

        // Same timestamp both times: the kept O_EXCL placeholder from the first reservation
        // forces the second to the ` 2` suffix instead of handing back the same path.
        let first = try location.reserveRecordingURL(date: Self.fixedDate, timeZone: Self.utc)
        let second = try location.reserveRecordingURL(date: Self.fixedDate, timeZone: Self.utc)
        #expect(first.lastPathComponent == "Recording 2026-07-14 at 10.12.34.mov")
        #expect(second.lastPathComponent == "Recording 2026-07-14 at 10.12.34 2.mov")
        #expect(fileManager.fileExists(atPath: first.path))   // placeholder held until the writer
    }
}
