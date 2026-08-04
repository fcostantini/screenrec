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
        #expect(picked.map(\.url.lastPathComponent) == ["newest.mov", "middle.mov", "old.mov"])
    }

    @Test func capsAtTheLimit() {
        let entries = (1...20).map { Self.entry("rec\($0).mov", TimeInterval($0)) }
        #expect(RecentRecordings.newest(entries).count == RecentRecordings.limit)
        #expect(RecentRecordings.limit == 10)         // docs/06 item 10, raised in M28-T5
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

    @Test func capsARealDirectoryAtTheLimit() throws {
        let directory = try makeFixture((1...16).map { ("Recording \($0).mov", TimeInterval($0)) })
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(RecentRecordings.inDirectory(directory).count == 10)
        // The newest ten, not just any ten (the fixture's number is seconds ago, so 1 is newest).
        #expect(RecentRecordings.inDirectory(directory).first?.lastPathComponent == "Recording 1.mov")
        #expect(RecentRecordings.inDirectory(directory).last?.lastPathComponent == "Recording 10.mov")
    }

    @Test func exportsScanKeepsMp4AndGifNewestFirstAndCapsAtItsOwnLimit() throws {
        // The Recent Exports group (M12-T2): the same scan, filtered to the export extensions —
        // recordings are excluded, and its own smaller limit keeps the menu compact.
        let directory = try makeFixture([
            ("clip.mov", 1),               // a recording — excluded from exports
            ("a.mp4", 60), ("b.gif", 50), ("c.mp4", 40), ("d.gif", 30),
            ("e.mp4", 20), ("f.gif", 10),
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        let exports = RecentRecordings.inDirectory(
            directory, extensions: RecentRecordings.exportExtensions,
            limit: RecentRecordings.exportLimit)
        #expect(exports.map(\.lastPathComponent) == ["f.gif", "e.mp4", "d.gif", "c.mp4", "b.gif"])
        // Smaller than the recordings' cap on purpose: derived files must not crowd the menu.
        #expect(RecentRecordings.exportLimit == 5)
        #expect(RecentRecordings.exportLimit < RecentRecordings.limit)
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

    // MARK: - Day headers (M28-T5)

    /// A fixed clock and a fixed calendar: "Today" must not depend on when the suite runs.
    private static let noon = Date(timeIntervalSince1970: 1_754_308_800)   // Mon 2025-08-04 12:00 UTC
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private static func daysBefore(_ days: Double, hours: Double = 0) -> Date {
        noon.addingTimeInterval(-days * 86_400 - hours * 3_600)
    }

    @Test func todayAndYesterdayAreNamedRatherThanDated() {
        let label = { (d: Date) in
            RecentRecordings.dayLabel(
                for: d, now: Self.noon, calendar: Self.utc, locale: Locale(identifier: "en_GB"))
        }
        #expect(label(Self.noon) == "Today")
        #expect(label(Self.daysBefore(0, hours: 11)) == "Today")        // 01:00, same day
        #expect(label(Self.daysBefore(1)) == "Yesterday")
    }

    @Test func aDayInsideTheWeekIsItsWeekdayAndOlderIsADate() {
        let label = { (d: Date) in
            RecentRecordings.dayLabel(
                for: d, now: Self.noon, calendar: Self.utc, locale: Locale(identifier: "en_GB"))
        }
        // The fixture's "now" is a Monday, so three days back is the Friday.
        #expect(label(Self.daysBefore(3)) == "Friday")
        #expect(label(Self.daysBefore(6)) == "Tuesday")
        // Past a week a weekday name stops being unambiguous, so it becomes a date. Seven days back
        // is the *previous* Monday — the case a weekday label would render indistinguishable.
        #expect(label(Self.daysBefore(7)) != "Monday")
        #expect(label(Self.daysBefore(7)).contains("28"))
        #expect(label(Self.daysBefore(30)).contains("5"))
    }

    @Test func midnightIsADayBoundaryNotATwentyFourHourWindow() {
        // 00:30 today and 23:30 yesterday are 60 minutes apart and belong to different days.
        let label = { (d: Date) in
            RecentRecordings.dayLabel(for: d, now: Self.noon, calendar: Self.utc, locale: .init(identifier: "en_GB"))
        }
        #expect(label(Self.daysBefore(0, hours: 11.5)) == "Today")       // 00:30
        #expect(label(Self.daysBefore(0, hours: 12.5)) == "Yesterday")   // 23:30 the day before
    }

    @Test func aFileDatedInTheFutureGetsADateRatherThanToday() {
        // Clock skew, or a file copied in with a future mtime: the day arithmetic goes negative,
        // which must not read as "Today" and must not crash. A plain date is the honest answer.
        let ahead = Self.noon.addingTimeInterval(2 * 86_400)
        let label = RecentRecordings.dayLabel(
            for: ahead, now: Self.noon, calendar: Self.utc, locale: Locale(identifier: "en_GB"))
        #expect(label != "Today")
        #expect(label != "Yesterday")
        #expect(label.contains("6"))        // 6 August, two days on from the fixture's Monday
    }

    @Test func rowsGroupUnderTheirDayInTheOrderGiven() {
        let a = Self.url("a.mov"), b = Self.url("b.mov"), c = Self.url("c.mov")
        let groups = RecentRecordings.grouped(
            [a, b, c],
            dates: [a: Self.noon, b: Self.noon.addingTimeInterval(-60), c: Self.daysBefore(1)],
            now: Self.noon, calendar: Self.utc, locale: Locale(identifier: "en_GB"))

        #expect(groups.map(\.label) == ["Today", "Yesterday"])
        #expect(groups.first?.urls == [a, b])      // same day, one header, order preserved
        #expect(groups.last?.urls == [c])
    }

    @Test func aRowWithNoKnownDateJoinsTheGroupAboveRatherThanInventingOne() {
        let a = Self.url("a.mov"), b = Self.url("b.mov")
        let groups = RecentRecordings.grouped(
            [a, b], dates: [a: Self.noon], now: Self.noon,
            calendar: Self.utc, locale: Locale(identifier: "en_GB"))
        #expect(groups.count == 1)
        #expect(groups.first?.label == "Today")
        #expect(groups.first?.urls == [a, b])
    }

    @Test func anUndatedFirstRowTakesNoHeaderAtAll() {
        // An empty label is how the builder knows to emit no header — better than a wrong one.
        let a = Self.url("a.mov")
        let groups = RecentRecordings.grouped([a], dates: [:], now: Self.noon, calendar: Self.utc)
        #expect(groups.map(\.label) == [""])
    }
}
