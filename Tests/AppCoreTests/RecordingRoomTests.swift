import Foundation
import Testing
@testable import AppCore

/// The disk figure the menu shows before a recording (M18-T4). Pure arithmetic and pure copy —
/// the honesty of the *rate* it is given is `BitrateModel`'s business.
@Suite struct RecordingRoomTests {

    @Test func secondsFallOutOfFreeSpaceAndRate() {
        // 33.3 Mbps is the measured High/60fps rate for this display; 752 GB was free when the
        // task was written, which is ~50 hours.
        let seconds = try? #require(RecordingRoom.seconds(
            freeBytes: 752_300_000_000, bitsPerSecond: 33_288_696))
        #expect(((seconds ?? 0) / 3600) > 49)
        #expect(((seconds ?? 0) / 3600) < 51)
    }

    @Test func nilMeansUnknownWhileZeroMeansNoRoom() {
        // Withhold only when the rate is unknowable — a *known* budget of zero is the answer this
        // row exists to give, so it must not be swallowed as "nothing to say".
        #expect(RecordingRoom.seconds(freeBytes: 100_000, bitsPerSecond: 0) == nil)
        #expect(RecordingRoom.seconds(freeBytes: 0, bitsPerSecond: 1_000) == 0)
        #expect(RecordingRoom.phrase(seconds: 0, presetName: "High")
            == "Not enough room to record at High")
    }

    @Test func theFailStopReserveIsNotCountedAsRoom() {
        // Capture stops itself at the 2 GiB floor, so quoting raw free space promised a take twice
        // the length the guard allows — the exact failure this row exists to preempt.
        let rate = 19_000_000                        // Balanced at 4112×2570, 60 fps
        let free: Int64 = 4 * 1024 * 1024 * 1024     // 4 GiB
        let seconds = try? #require(RecordingRoom.seconds(freeBytes: free, bitsPerSecond: rate))
        let raw = Double(free) / (Double(rate) / 8)
        #expect((seconds ?? 0) < raw / 1.9)          // ~half: the 2 GiB reserve is half of 4 GiB
        #expect(RecordingRoom.seconds(freeBytes: 1_000_000, bitsPerSecond: rate) == 0)
    }

    @Test func theRowStaysAwayUntilItIsNews() {
        // "About 50 hours" is noise on a healthy disk; the row exists for the case that matters.
        #expect(RecordingRoom.phrase(seconds: 50 * 3600, presetName: "High") == nil)
        #expect(RecordingRoom.phrase(seconds: nil, presetName: "High") == nil)
        #expect(RecordingRoom.phrase(seconds: 40 * 60, presetName: "High")
            == "Room for about 40 min at High")
    }

    @Test func theFigureIsFlooredNeverRoundedUp() {
        // Rounding up would promise room that isn't there.
        #expect(RecordingRoom.approximate(59) == "under a minute")
        #expect(RecordingRoom.approximate(119) == "1 min")
        #expect(RecordingRoom.approximate(40 * 60 + 59) == "40 min")
        #expect(RecordingRoom.approximate(3600) == "1 hour")
        #expect(RecordingRoom.approximate(3600 + 20 * 60) == "1 hour 20 min")
        #expect(RecordingRoom.approximate(2 * 3600) == "2 hours")
    }
}
