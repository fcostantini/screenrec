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
        // The claim lives on the .partial companion; nothing that looks finished exists yet.
        #expect(fileManager.fileExists(atPath: OutputLocation.partialURL(for: first).path))
        #expect(!fileManager.fileExists(atPath: first.path))
    }

    @Test func reserveSkipsNamesWhoseFinalFileExists() throws {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("reserve-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }
        let location = OutputLocation(directory: dir)

        try Data().write(to: dir.appendingPathComponent("Recording 2026-07-14 at 10.12.34.mov"))
        let reserved = try location.reserveRecordingURL(date: Self.fixedDate, timeZone: Self.utc)
        #expect(reserved.lastPathComponent == "Recording 2026-07-14 at 10.12.34 2.mov")
    }

    @Test func finalizePartialRenamesAndResolvesCollisions() throws {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("finalize-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }

        let partial = dir.appendingPathComponent("Recording A.mov.partial")
        try Data("movie".utf8).write(to: partial)
        let final = try OutputLocation.finalizePartial(partial)
        #expect(final.lastPathComponent == "Recording A.mov")
        #expect(!fileManager.fileExists(atPath: partial.path))

        // A second partial finalizing into an occupied name steps to ` 2`.
        try Data("movie2".utf8).write(to: partial)
        let second = try OutputLocation.finalizePartial(partial)
        #expect(second.lastPathComponent == "Recording A 2.mov")
    }

    @Test func recoverySalvagesOrphansAndSweepsPlaceholders() throws {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("recover-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }
        let location = OutputLocation(directory: dir)
        let staleDate = Date(timeIntervalSinceNow: -300)

        let orphan = dir.appendingPathComponent("Recording crashed.mov.partial")
        try Data("fragments".utf8).write(to: orphan)
        try fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: orphan.path)
        let placeholder = dir.appendingPathComponent("Recording empty.mov.partial")
        try Data().write(to: placeholder)                       // 0-byte reservation, no recording
        try fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: placeholder.path)
        let bystander = dir.appendingPathComponent("Recording done.mov")
        try Data("done".utf8).write(to: bystander)
        // Fresh mtime = possibly another process's LIVE recording; recovery must not touch it.
        let live = dir.appendingPathComponent("Recording live.mov.partial")
        try Data("growing".utf8).write(to: live)

        let recovered = location.recoverOrphanedPartials()
        #expect(recovered.map(\.lastPathComponent) == ["Recording crashed.mov"])
        #expect(!fileManager.fileExists(atPath: orphan.path))
        #expect(!fileManager.fileExists(atPath: placeholder.path))   // litter swept
        #expect(fileManager.fileExists(atPath: bystander.path))      // untouched
        #expect(fileManager.fileExists(atPath: live.path))           // live partial left alone
    }

    @Test func recoveryDeletesAbandonedExportPartialsInsteadOfRenamingThem() throws {
        // A `.mov.partial` is an already-playable fragmented movie, so recovery is a rename. An
        // export's partial is a torn file with no such property — renaming one would present
        // unplayable bytes as a rescued recording (M15-T3).
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("exportsweep-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }
        let location = OutputLocation(directory: dir)
        let staleDate = Date(timeIntervalSinceNow: -300)

        let recording = dir.appendingPathComponent("Recording crashed.mov.partial")
        let mp4 = dir.appendingPathComponent("Clip.mp4.partial")
        let gif = dir.appendingPathComponent("Clip.gif.partial")
        for url in [recording, mp4, gif] {
            try Data("bytes".utf8).write(to: url)
            try fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: url.path)
        }

        let recovered = location.recoverOrphanedPartials()

        #expect(recovered.map(\.lastPathComponent) == ["Recording crashed.mov"])
        #expect(!fileManager.fileExists(atPath: mp4.path))    // deleted, not renamed
        #expect(!fileManager.fileExists(atPath: gif.path))
        #expect(!fileManager.fileExists(atPath: dir.appendingPathComponent("Clip.mp4").path))
        #expect(!fileManager.fileExists(atPath: dir.appendingPathComponent("Clip.gif").path))
    }

    @Test(arguments: [
        // Recoverable: a fragmented movie, or the CLI's extension-less exact path.
        ("Recording.mov.partial", true), ("take1.partial", true),
        // Not: exports are torn share files, not playable fragments.
        ("Clip.mp4.partial", false), ("Clip.gif.partial", false),
    ])
    func onlyRecordingPartialsAreRecoverable(name: String, recoverable: Bool) {
        #expect(OutputLocation.isRecoverablePartial(name) == recoverable)
    }

    @Test(arguments: [
        ("Clip.mp4.partial", true), ("Clip.gif.partial", true),
        ("Recording.mov.partial", false), ("take1.partial", false), ("notes.txt.partial", false),
    ])
    func onlyExportPartialsAreSweptAsLitter(name: String, abandoned: Bool) {
        #expect(OutputLocation.isAbandonedExportPartial(name) == abandoned)
    }

    @Test func recoverySparesUnrecognizedPartialsRatherThanDeletingThem() throws {
        // Deletion is irreversible, so a partial we don't recognize is left where it is.
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("unknown-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }

        let unknown = dir.appendingPathComponent("notes.txt.partial")
        try Data("bytes".utf8).write(to: unknown)
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -300)], ofItemAtPath: unknown.path)

        let recovered = OutputLocation(directory: dir).recoverOrphanedPartials()

        #expect(recovered.isEmpty)
        #expect(fileManager.fileExists(atPath: unknown.path))
    }

    @Test func finalizePartialKeepsExtensionlessNamesIntact() throws {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("noext-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }

        let partial = dir.appendingPathComponent("take1.partial")
        try Data("movie".utf8).write(to: partial)
        let final = try OutputLocation.finalizePartial(partial)
        #expect(final.lastPathComponent == "take1")   // no trailing dot
    }

    @Test func reserveExactNamesTheInterruptedRecordingInItsError() throws {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("exact-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }

        let target = dir.appendingPathComponent("demo.mov")
        try Data("leftover".utf8).write(to: OutputLocation.partialURL(for: target))
        #expect {
            try OutputLocation.reserveExact(target)
        } throws: { error in
            guard case OutputLocation.ReservationError.interruptedRecordingInTheWay(let path) = error
            else { return false }
            return path.hasSuffix("demo.mov.partial")
        }
    }
}
