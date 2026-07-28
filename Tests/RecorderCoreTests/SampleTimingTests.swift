import CoreMedia
import Foundation
import Testing
@testable import RecorderCore

/// Retiming sits on the sample path: `MovieRecorder`'s tail patch and `ReplayMuxer`'s rebase both
/// hand a copy to a writer, and a wrong timestamp there is a desynced or inflated track in a file
/// that still looks healthy.
@Suite struct SampleTimingTests {

    private static let format = makeAudioFormat(sampleRate: 48_000, channels: 1)

    private func buffer(pts: CMTime, frames: Int = 480) -> CMSampleBuffer {
        makeAudioSampleBuffer(format: Self.format, frames: frames, pts: pts)
    }

    @Test func shiftsPresentationTimeToTheRequestedStamp() throws {
        let original = buffer(pts: CMTime(value: 1, timescale: 10))
        let moved = try #require(SampleTiming.retimed(original, to: CMTime(value: 9, timescale: 10)))

        #expect(CMSampleBufferGetPresentationTimeStamp(moved) == CMTime(value: 9, timescale: 10))
        // The source is untouched — callers keep using it (the ring holds its own copy).
        #expect(CMSampleBufferGetPresentationTimeStamp(original) == CMTime(value: 1, timescale: 10))
        #expect(CMSampleBufferGetNumSamples(moved) == CMSampleBufferGetNumSamples(original))
    }

    @Test func keepsTheDurationUnlessOneIsGiven() throws {
        // A video frame — one sample, which is the shape the `duration` parameter exists for.
        // ⚠️ On a multi-sample audio buffer the same value is *per sample*, so `GetDuration`
        // reports it multiplied by the sample count.
        let original = makeVideoSampleBuffer(
            width: 32, height: 32, pts: .zero, duration: CMTime(value: 1, timescale: 60), shade: 0)

        let inherited = try #require(SampleTiming.retimed(original, to: CMTime(value: 5, timescale: 1)))
        #expect(CMSampleBufferGetDuration(inherited) == CMSampleBufferGetDuration(original))

        // 🔴 The bug this parameter exists for (docs/07, M5-T3): AVAssetWriter infers a track's LAST
        // sample duration from the previous pts delta when the duration is invalid, so a tail patch
        // seconds after the last real frame inflated a 10 s track to 19 s. An explicit duration is
        // the fix, and it has to survive the copy.
        let stamped = try #require(SampleTiming.retimed(
            original, to: CMTime(value: 5, timescale: 1), duration: CMTime(value: 1, timescale: 30)))
        #expect(CMSampleBufferGetDuration(stamped) == CMTime(value: 1, timescale: 30))
    }

    @Test func refusesABufferWithNoNumericTiming() {
        // An invalid PTS has no delta to apply; retiming it would produce a sample the writer
        // places at an arbitrary point instead of failing loudly. (A marker buffer is the only
        // way to hold one — CoreMedia refuses to *create* an audio buffer with an invalid PTS.)
        #expect(SampleTiming.retimed(makeMarkerBuffer(), to: .zero) == nil)
    }
}
