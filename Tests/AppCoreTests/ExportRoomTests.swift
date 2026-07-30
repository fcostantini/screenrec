import Foundation
import Testing

@testable import AppCore

/// The export fit decision (M23-T2) — the safety-critical half is the *direction* of each edge:
/// refusing what fits is annoying, letting through what doesn't is the failure this exists to stop.
@Suite struct ExportRoomTests {

    @Test func aJobLargerThanTheVolumeDoesNotFit() {
        #expect(!ExportRoom.fits(needBytes: 1_800_000_000, freeBytes: 900_000_000))
    }

    @Test func aJobTheVolumeCanHoldFits() {
        #expect(ExportRoom.fits(needBytes: 900_000_000, freeBytes: 1_800_000_000))
    }

    @Test func exactlyFittingIsAllowed() {
        // The boundary belongs to the user: a job that exactly fits is not refused.
        #expect(ExportRoom.fits(needBytes: 1_000, freeBytes: 1_000))
        #expect(!ExportRoom.fits(needBytes: 1_001, freeBytes: 1_000))
    }

    @Test func anUnknownEstimateNeverRefuses() {
        // A GIF, or a file whose header wouldn't read. Guessing would refuse exports that work.
        #expect(ExportRoom.fits(needBytes: nil, freeBytes: 0))
    }

    @Test func anUnreadableVolumeNeverRefuses() {
        // Matches the recording guard's rule (02 §7): an unreadable capacity is not evidence of a
        // full disk, so it must not become one.
        #expect(ExportRoom.fits(needBytes: 1_800_000_000, freeBytes: nil))
    }

    @Test func theVolumeNameIsReadableForTheBootVolume() {
        // The notice names the disk to go and fix, so this must resolve on the ordinary case.
        #expect(!ExportRoom.volumeName(forPath: NSHomeDirectory()).isEmpty)
    }
}
