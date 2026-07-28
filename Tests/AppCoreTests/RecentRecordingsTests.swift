import Foundation
import Testing
@testable import AppCore

/// The pure half runs on hand-built entries; the live half runs against a real fixture
/// directory, because the whole point of splitting them is that each is only honest about one
/// thing (M3-T3's lesson — the disk guard's "reads real capacity" test passed for weeks while
/// the behaviour was wrong on every volume but the boot one).
@Suite struct RecentRecordingsTests {

    private static func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Movies/\(name)")
    }

    private static func entry(_ name: String, _ minutesAgo: TimeInterval) -> RecentRecordings.Entry {
        RecentRecordings.Entry(url: url(name), modified: Date(timeIntervalSince1970: -minutesAgo * 60))
    }

    // MARK: - Choosing

    @Test func newestFirst() {
        let picked = RecentRecordings.newest([
            Self.entry("old.mov", 30), Self.entry("newest.mov", 1), Self.entry("middle.mov", 10),
        ])
        #expect(picked.map(\.lastPathComponent) == ["newest.mov", "middle.mov", "old.mov"])
    }

    @Test func capsAtTheLimit() {
        let entries = (1...12).map { Self.entry("rec\($0).mov", TimeInterval($0)) }
        #expect(RecentRecordings.newest(entries).count == RecentRecordings.limit)
        #expect(RecentRecordings.limit == 5)          // docs/06 item 10
    }

    @Test func emptyDirectoryIsNotAnError() {
        #expect(RecentRecordings.newest([]).isEmpty)
    }

    @Test func sameSecondFilesKeepAStableOrder() {
        // Two recordings can land in the same second (the O_EXCL "… 2.mov" suffix exists for
        // exactly that). `sorted(by:)` isn't guaranteed stable, so without the filename
        // tie-break the menu could reshuffle these between openings for no reason.
        //
        // The assertion is *stability*, deliberately not recency: descending by name puts
        // "Recording.mov" above "Recording 2.mov" even though the suffixed one was written
        // second. Pinning the exact order here would encode that quirk as if it were intent.
        let same = Date(timeIntervalSince1970: 1_000)
        let entries = [
            RecentRecordings.Entry(url: Self.url("Recording 2.mov"), modified: same),
            RecentRecordings.Entry(url: Self.url("Recording.mov"), modified: same),
        ]
        #expect(RecentRecordings.newest(entries) == RecentRecordings.newest(entries.reversed()))
    }

    // MARK: - Probing a real directory

    /// Builds a throwaway directory with real files whose modification dates we control.
    private func makeFixture(_ files: [(name: String, minutesAgo: TimeInterval)]) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("recent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            let url = directory.appendingPathComponent(file.name)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -file.minutesAgo * 60)],
                ofItemAtPath: url.path)
        }
        return directory
    }

    @Test func readsARealDirectoryNewestFirstAndIgnoresNonRecordings() throws {
        let directory = try makeFixture([
            ("Recording old.mov", 60),
            ("Recording new.mov", 1),
            ("notes.txt", 2),              // not a recording
            ("Recording mid.mov", 30),
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        let recent = RecentRecordings.inDirectory(directory)
        #expect(recent.map(\.lastPathComponent) == [
            "Recording new.mov", "Recording mid.mov", "Recording old.mov",
        ])
    }

    @Test func capsARealDirectoryAtFive() throws {
        let directory = try makeFixture((1...9).map { ("Recording \($0).mov", TimeInterval($0)) })
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(RecentRecordings.inDirectory(directory).count == 5)
    }

    @Test func exportsScanKeepsMp4AndGifNewestFirstAndCapsAtThree() throws {
        // The Recent Exports group (M12-T2): the same scan, filtered to the export extensions —
        // recordings are excluded, and its own smaller limit keeps the menu compact.
        let directory = try makeFixture([
            ("clip.mov", 1),               // a recording — excluded from exports
            ("a.mp4", 50), ("b.gif", 40), ("c.mp4", 30), ("d.gif", 20),
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        let exports = RecentRecordings.inDirectory(
            directory, extensions: RecentRecordings.exportExtensions,
            limit: RecentRecordings.exportLimit)
        #expect(exports.map(\.lastPathComponent) == ["d.gif", "c.mp4", "b.gif"])
        #expect(RecentRecordings.exportLimit == 3)
        // Symmetry: the default recordings scan ignores the exports.
        #expect(RecentRecordings.inDirectory(directory).map(\.lastPathComponent) == ["clip.mov"])
    }

    @Test func aMissingDirectoryYieldsNoRowsRatherThanThrowing() {
        // The user can point the app at a folder that later goes away (an unmounted volume).
        // The menu still has to open — the failure belongs on the record attempt, where it can
        // be acted on, not on a glance at the menu bar.
        let gone = URL(fileURLWithPath: "/nope/does/not/exist")
        #expect(RecentRecordings.inDirectory(gone).isEmpty)
    }

    // MARK: - Row titles (M18-T3)

    @Test func aRowNamesTheFileItsLengthAndItsSize() {
        // Picking the right take should be one step, so the row carries what distinguishes takes.
        let detail = RecentRecordings.RowDetail(
            byteCount: 5_500_000_000, duration: 1384, modified: Date())
        // The size goes through ByteCountFormatter (docs/06), which is locale-formatted — assert
        // the structure around it, not one machine's decimal separator.
        let size = ByteCountFormatter.string(fromByteCount: 5_500_000_000, countStyle: .file)
        #expect(RecentRecordings.rowTitle(for: Self.url("Recording 2026-07-27 at 13.01.24.mov"),
                                          detail: detail)
            == "Recording 2026-07-27 at 13.01.24.mov — 23:04 · \(size)")
    }

    @Test func aRowStatesWhatIsKnown() {
        // Details arrive after the menu opens, and a file that isn't readable media never gets a
        // length — both states have to read as a row, not as a gap waiting to be filled.
        let url = Self.url("Clip.mov")
        #expect(RecentRecordings.rowTitle(for: url, detail: nil) == "Clip.mov")
        let sizeOnly = RecentRecordings.RowDetail(
            byteCount: 17_000_000, duration: nil, modified: Date())
        let size = ByteCountFormatter.string(fromByteCount: 17_000_000, countStyle: .file)
        #expect(RecentRecordings.rowTitle(for: url, detail: sizeOnly) == "Clip.mov — \(size)")
    }

    @Test func lengthsPastAnHourGrowAnHoursField() {
        #expect(RecentRecordings.clock(0) == "0:00")
        #expect(RecentRecordings.clock(9.6) == "0:10")
        #expect(RecentRecordings.clock(600) == "10:00")
        #expect(RecentRecordings.clock(3599) == "59:59")
        #expect(RecentRecordings.clock(3600) == "1:00:00")
        #expect(RecentRecordings.clock(7384) == "2:03:04")
    }

    @Test func anUnchangedFileIsNeverReadTwice() async throws {
        // The cache is the whole reason the read can ride the menu open (M6-T10): a second open
        // must cost nothing. A changed file must still be re-read, or a re-recording keeps a
        // stale length forever.
        let directory = try makeFixture([(name: "A.mov", minutesAgo: 1)])
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("A.mov")

        let first = await RecentRecordings.details(for: [url], cached: [:])
        let entry = try #require(first[url])
        #expect(entry.byteCount == 1)      // the fixture writes one byte
        #expect(entry.duration == nil)     // …which is not readable media

        // A hit keeps the cached entry rather than re-reading.
        let stamped = RecentRecordings.RowDetail(
            byteCount: 1, duration: 12.5, modified: entry.modified)
        #expect(await RecentRecordings.details(for: [url], cached: [url: stamped])[url]?.duration
            == 12.5)

        // Touching the file invalidates it.
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: url.path)
        #expect(await RecentRecordings.details(for: [url], cached: [url: stamped])[url]?.duration
            == nil)
    }

    @Test func aVanishedFileGetsNoRowDetail() async {
        let details = await RecentRecordings.details(
            for: [Self.url("Gone.mov")], cached: [:])
        #expect(details.isEmpty)
    }
}
