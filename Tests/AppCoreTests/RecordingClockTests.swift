import Foundation
import Testing
@testable import AppCore

/// The menu-bar clock's basis (M9-T3): pause-correct elapsed time, computed against an injected
/// `now` so there's no wall-clock in the test.
@Suite struct RecordingClockTests {

    private static let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func aRunningClockCountsFromItsStart() {
        let clock = RecordingClock(accumulated: 0, runningSince: Self.t0)
        #expect(clock.elapsed(now: Self.t0) == 0)
        #expect(clock.elapsed(now: Self.t0.addingTimeInterval(42)) == 42)
    }

    @Test func afterAResumeTheBankedTimeIsIncluded() {
        // 30 s banked before this span, running for another 12 s ⇒ 42 s.
        let clock = RecordingClock(accumulated: 30, runningSince: Self.t0)
        #expect(clock.elapsed(now: Self.t0.addingTimeInterval(12)) == 42)
    }

    @Test func aPausedClockIsFrozenAtWhereItWasBanked() {
        var clock = RecordingClock(accumulated: 0, runningSince: Self.t0)
        clock.bankAndFreeze(now: Self.t0.addingTimeInterval(25))
        #expect(clock.runningSince == nil)
        #expect(clock.accumulated == 25)
        // Time marching on does not advance a frozen clock.
        #expect(clock.elapsed(now: Self.t0.addingTimeInterval(999)) == 25)
    }

    @Test func pauseResumePauseAccumulatesOnlyTheRunningSpans() {
        var clock = RecordingClock(accumulated: 0, runningSince: Self.t0)
        clock.bankAndFreeze(now: Self.t0.addingTimeInterval(10))   // ran 10 s → banked 10
        clock.runningSince = Self.t0.addingTimeInterval(100)       // resume much later
        clock.bankAndFreeze(now: Self.t0.addingTimeInterval(105))  // ran 5 s → banked 15
        #expect(clock.accumulated == 15)                            // the paused 90 s is excluded
    }
}
