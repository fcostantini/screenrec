import CoreMedia
import Testing
@testable import RecorderCore

@Suite struct TimestampRebaserTests {

    // Whole-second timestamps keep the rebased seconds exact and readable.
    private func t(_ seconds: Int64) -> CMTime { CMTime(value: seconds, timescale: 1) }

    private func emitted(_ decision: TimestampRebaser.Decision) -> Double? {
        if case .emit(let pts) = decision { return pts.seconds }
        return nil
    }

    // MARK: epoch

    @Test func firstVideoFrameSetsEpochToZero() {
        var rebaser = TimestampRebaser()
        #expect(emitted(rebaser.rebase(rawPTS: t(1000), source: .screen)) == 0)
        #expect(emitted(rebaser.rebase(rawPTS: t(1010), source: .screen)) == 10)
    }

    @Test func audioBeforeFirstVideoFrameIsDropped() {
        var rebaser = TimestampRebaser()
        #expect(rebaser.rebase(rawPTS: t(500), source: .systemAudio) == .drop)
        #expect(rebaser.rebase(rawPTS: t(1000), source: .microphone) == .drop)
        #expect(emitted(rebaser.rebase(rawPTS: t(1000), source: .screen)) == 0)  // epoch
        #expect(emitted(rebaser.rebase(rawPTS: t(1001), source: .systemAudio)) == 1)
    }

    @Test func audioStampedBeforeEpochIsDropped() {
        var rebaser = TimestampRebaser()
        _ = rebaser.rebase(rawPTS: t(1000), source: .screen)  // epoch = 1000
        // Audio stamped earlier than the epoch would lead video — drop it.
        #expect(rebaser.rebase(rawPTS: t(990), source: .systemAudio) == .drop)
        #expect(emitted(rebaser.rebase(rawPTS: t(1005), source: .systemAudio)) == 5)
    }

    // MARK: monotonic enforcement

    @Test func outOfOrderAndDuplicateFramesRejected() {
        var rebaser = TimestampRebaser()
        _ = rebaser.rebase(rawPTS: t(0), source: .screen)
        #expect(emitted(rebaser.rebase(rawPTS: t(10), source: .screen)) == 10)
        #expect(rebaser.rebase(rawPTS: t(10), source: .screen) == .drop)  // duplicate PTS
        #expect(rebaser.rebase(rawPTS: t(5), source: .screen) == .drop)   // reordered earlier
        #expect(emitted(rebaser.rebase(rawPTS: t(11), source: .screen)) == 11)
    }

    @Test func tracksAreIndependentlyMonotonic() {
        var rebaser = TimestampRebaser()
        _ = rebaser.rebase(rawPTS: t(0), source: .screen)  // epoch
        #expect(emitted(rebaser.rebase(rawPTS: t(10), source: .screen)) == 10)
        // Audio at rebased 3 trails video's 10 but is the first on its own track — emit it.
        #expect(emitted(rebaser.rebase(rawPTS: t(3), source: .systemAudio)) == 3)
        #expect(emitted(rebaser.rebase(rawPTS: t(4), source: .microphone)) == 4)
    }

    // MARK: pause / resume

    @Test func cumulativePauseOffsetsSubtractPausedSpans() {
        var rebaser = TimestampRebaser()
        _ = rebaser.rebase(rawPTS: t(0), source: .screen)  // epoch 0
        #expect(emitted(rebaser.rebase(rawPTS: t(10), source: .screen)) == 10)

        rebaser.pause(atRawPTS: t(12))
        #expect(rebaser.rebase(rawPTS: t(15), source: .screen) == .drop)       // paused
        #expect(rebaser.rebase(rawPTS: t(16), source: .systemAudio) == .drop)
        rebaser.resume()
        // Resume frame at raw 20: offset += 20−12 = 8 ⇒ rebased 20−8 = 12.
        #expect(emitted(rebaser.rebase(rawPTS: t(20), source: .screen)) == 12)
        #expect(emitted(rebaser.rebase(rawPTS: t(30), source: .screen)) == 22)

        // A second pause of 8 more accumulates to offset 16.
        rebaser.pause(atRawPTS: t(32))
        rebaser.resume()
        #expect(emitted(rebaser.rebase(rawPTS: t(40), source: .screen)) == 24)  // 40 − 16
    }

    @Test func resumeCompletesOnlyOnAVideoFrame() {
        var rebaser = TimestampRebaser()
        _ = rebaser.rebase(rawPTS: t(0), source: .screen)
        _ = rebaser.rebase(rawPTS: t(10), source: .screen)
        rebaser.pause(atRawPTS: t(11))
        rebaser.resume()
        // Audio arriving while resume is armed is still dropped; only a video frame re-anchors.
        #expect(rebaser.rebase(rawPTS: t(20), source: .systemAudio) == .drop)
        #expect(emitted(rebaser.rebase(rawPTS: t(21), source: .screen)) == 11)  // offset 21−11=10 ⇒ 21−10
    }

    @Test func pauseAndResumeReportWhetherTheyTookEffect() {
        var rebaser = TimestampRebaser()
        // Before the epoch there is no timeline to pause, and nothing to resume.
        #expect(rebaser.pause(atRawPTS: t(5)) == false)
        #expect(rebaser.resume() == false)
        _ = rebaser.rebase(rawPTS: t(1000), source: .screen)  // epoch
        #expect(rebaser.pause(atRawPTS: t(1005)) == true)     // now takes effect
        #expect(rebaser.pause(atRawPTS: t(1006)) == false)    // already paused
        #expect(rebaser.resume() == true)                     // was paused
        #expect(rebaser.resume() == false)                    // no longer paused
    }

    @Test func pauseBeforeEpochIsIgnored() {
        var rebaser = TimestampRebaser()
        rebaser.pause(atRawPTS: t(5))  // nothing recording yet → no-op
        rebaser.resume()
        #expect(emitted(rebaser.rebase(rawPTS: t(100), source: .screen)) == 0)
        #expect(emitted(rebaser.rebase(rawPTS: t(110), source: .screen)) == 10)
    }

    // MARK: robustness

    @Test func nonNumericTimestampsDropped() {
        var rebaser = TimestampRebaser()
        #expect(rebaser.rebase(rawPTS: .invalid, source: .screen) == .drop)
        #expect(rebaser.rebase(rawPTS: .indefinite, source: .screen) == .drop)
        // A valid frame afterward still anchors the epoch normally.
        #expect(emitted(rebaser.rebase(rawPTS: t(100), source: .screen)) == 0)
    }
}
