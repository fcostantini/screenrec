import Foundation
import Testing
@testable import AppCore
import RecorderCore

@Suite struct MenuHeaderTests {

    @Test(arguments: [
        (0.0, "00:00:00"),
        (1.0, "00:00:01"),
        (59.0, "00:00:59"),
        (60.0, "00:01:00"),
        (3599.0, "00:59:59"),
        (3600.0, "01:00:00"),
        (5_425.0, "01:30:25"),          // a real 90-minute-ish capture
        (359_999.0, "99:59:59"),
    ])
    func elapsedIsAlwaysHHMMSS(seconds: TimeInterval, expected: String) {
        #expect(MenuHeader.elapsed(seconds) == expected)
    }

    @Test func elapsedTruncatesRatherThanRounds() {
        // A clock that reads 00:00:01 when 0.6 s of media exists would tick before the second
        // it names has happened.
        #expect(MenuHeader.elapsed(0.6) == "00:00:00")
        #expect(MenuHeader.elapsed(1.9) == "00:00:01")
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func elapsedSurvivesTheNumbersTheWriterCanProduce(seconds: Double) {
        // `recordedDuration` is `.invalid`/NaN until the first frame starts the session
        // (docs/02 §10) and `Int(nan)` traps. `refreshProgress` sanitizes before this is
        // reached, so this pins the formatter's own contract rather than a live code path —
        // worth having on a public formatter, but don't read it as the only thing standing
        // between the app and that trap.
        #expect(MenuHeader.elapsed(seconds) == "00:00:00")
    }

    @Test func recordingDetailNamesTheCodec() {
        // docs/06's recording header: `<size> · HEVC`.
        #expect(MenuHeader.recordingDetail(bytes: 0).hasSuffix(" · HEVC"))
        #expect(MenuHeader.recordingDetail(bytes: 41_200_000).contains("MB"))
    }

    @Test func recordingDetailTreatsAMissingFileAsZeroNotNegative() {
        #expect(MenuHeader.recordingDetail(bytes: -1) == MenuHeader.recordingDetail(bytes: 0))
    }

    @Test func readyReadsReady() {
        #expect(MenuHeader.idleStatus(.ready) == "Ready")
    }

    @Test(arguments: [
        RecordingReadiness.needsScreenRecording,
        .needsMicrophone,
        .blocked(reason: "Screen Recording is turned off for this app. Turn it on in System "
            + "Settings → Privacy & Security → Screen & System Audio Recording, then quit and "
            + "reopen the app."),
    ])
    func everyBlockedVerdictCollapsesToOneShortPhrase(readiness: RecordingReadiness) {
        // docs/06 item 1 gives the header one short phrase. `blocked` carries a full remedy
        // sentence for the onboarding window (M4-T3) — putting that in a disabled menu row would
        // blow out the menu's width to say something the user can't act on from there.
        #expect(MenuHeader.idleStatus(readiness) == "Permissions needed…")
    }

    @Test func recordingsFolderIsHomeRelative() {
        // Built from NSHomeDirectory so the abbreviation has the same home to match against.
        let movies = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        #expect(MenuHeader.recordingsFolder(movies) == "~/Movies")
    }

    @Test func recordingsFolderOutsideHomeStaysAbsolute() {
        // An external drive can't be shortened — the user sees exactly where it goes.
        #expect(MenuHeader.recordingsFolder(URL(fileURLWithPath: "/Volumes/Ext/Recordings"))
            == "/Volumes/Ext/Recordings")
    }
}
