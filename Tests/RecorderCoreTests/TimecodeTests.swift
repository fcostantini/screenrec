import Foundation
import Testing
@testable import RecorderCore

/// One type, three roundings. These cases came from the three formatters it replaced (M22-T4) —
/// same inputs, same strings, so a surface's copy can't have moved by a second.
@Suite struct TimecodeTests {

    // MARK: - cutPoint: `M:SS`, floored

    @Test func cutPointMatchesTheTrimWindowsFormat() {
        #expect(Timecode.cutPoint(0) == "0:00")
        #expect(Timecode.cutPoint(9.9) == "0:09")     // floors, never rounds an in-point up
        #expect(Timecode.cutPoint(61) == "1:01")
        #expect(Timecode.cutPoint(600) == "10:00")
    }

    // MARK: - clock: `HH:MM:SS`, truncated

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
    func clockIsAlwaysHHMMSS(seconds: TimeInterval, expected: String) {
        #expect(Timecode.clock(seconds) == expected)
    }

    @Test func clockTruncatesRatherThanRounds() {
        // A clock that reads 00:00:01 when 0.6 s of media exists would tick before the second
        // it names has happened.
        #expect(Timecode.clock(0.6) == "00:00:00")
        #expect(Timecode.clock(1.9) == "00:00:01")
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func clockSurvivesTheNumbersTheWriterCanProduce(seconds: Double) {
        // `recordedDuration` is `.invalid`/NaN until the first frame starts the session
        // (docs/02 §10) and `Int(nan)` traps. `refreshProgress` sanitizes before this is
        // reached, so this pins the formatter's own contract rather than a live code path —
        // worth having on a public formatter, but don't read it as the only thing standing
        // between the app and that trap.
        #expect(Timecode.clock(seconds) == "00:00:00")
    }

    // MARK: - length: `M:SS` → `H:MM:SS`, rounded

    @Test func lengthsPastAnHourGrowAnHoursField() {
        #expect(Timecode.length(0) == "0:00")
        #expect(Timecode.length(9.6) == "0:10")
        #expect(Timecode.length(600) == "10:00")
        #expect(Timecode.length(3599) == "59:59")
        #expect(Timecode.length(3600) == "1:00:00")
        #expect(Timecode.length(7384) == "2:03:04")
    }

    // MARK: - The reason there are three

    @Test func theSameSecondReadsDifferentlyAsACutPointAndAsALength() {
        // Not an inconsistency — the whole point. A cut point may not name a frame the file
        // doesn't keep; a finished length is a label and reads nearest. Naming the rounding is
        // what stops the next surface from picking whichever it happened to copy (M18-T1 shipped
        // exactly that mismatch inside the Trim window).
        #expect(Timecode.cutPoint(4.9) == "0:04")
        #expect(Timecode.length(4.9) == "0:05")
    }
}
