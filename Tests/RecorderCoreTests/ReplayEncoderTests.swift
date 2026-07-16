import CoreMedia
import Testing

@testable import RecorderCore

/// VideoToolbox needs no TCC grant, so the encoder is exercised headlessly with synthesized
/// frames — real HEVC encodes, not mocks.
struct ReplayEncoderTests {

    /// `onFailure` arrives on a capture/VT thread; a bare captured `var` would race the test's
    /// read (and fail the TSan verify) the day the callback actually fires.
    private final class FailureLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?

        var message: String? {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }

        func set(_ message: String) {
            lock.lock()
            stored = message
            lock.unlock()
        }
    }

    @Test func encodesScreenFramesIntoRingWithKeyframeCadence() {
        let encoder = ReplayEncoder(seconds: 60, frameRateCap: 30)
        encodeSyntheticFrames(into: encoder, count: 90)  // 3 s at 30 fps; frame 0 triggers bring-up
        let stats = encoder.stats()

        // RealTime sessions may shed frames under load, so exact counts would flake. The
        // contract is cadence: ~1 keyframe per second of whatever span survived (docs/03 M5-T2).
        #expect(stats.sampleCount > 45)
        #expect(stats.spanSeconds > 0 && stats.spanSeconds <= 3.0)
        #expect(abs(Double(stats.keyframeCount) - stats.spanSeconds) <= 1.5)
        #expect(stats.compressedBytes > 0)
    }

    @Test func firstEncodedFrameIsKeyframe() {
        let encoder = ReplayEncoder(seconds: 60, frameRateCap: 30)
        encodeSyntheticFrames(into: encoder, count: 5)
        let entries = encoder.ringEntriesForTesting()
        #expect(entries.first?.isKeyframe == true)
    }

    @Test func evictsBeyondCapacityPlusSlack() {
        let encoder = ReplayEncoder(seconds: 2, frameRateCap: 30)
        encodeSyntheticFrames(into: encoder, count: 240)  // 8 s at 30 fps into a 2 s ring
        let stats = encoder.stats()
        // Capacity 2 s + 2 s slack; one frame of overshoot tolerated at the boundary.
        #expect(stats.spanSeconds <= 4.1)
        #expect(stats.sampleCount < 240)
    }

    @Test func ignoresNonScreenAndImagelessBuffers() {
        let encoder = ReplayEncoder(seconds: 60, frameRateCap: 30)
        encoder.consume(makeMarkerBuffer(), type: .systemAudio)
        encoder.consume(makeMarkerBuffer(), type: .microphone)
        encoder.consume(makeMarkerBuffer(), type: .screen)  // no image buffer → skipped
        #expect(encoder.stats() == ReplayEncoder.Stats(
            spanSeconds: 0, sampleCount: 0, keyframeCount: 0, compressedBytes: 0))
    }

    @Test func invalidateStopsAcceptingFramesWithoutFailing() {
        let failure = FailureLatch()
        let encoder = ReplayEncoder(seconds: 60, frameRateCap: 30) { failure.set($0) }
        encodeSyntheticFrames(into: encoder, count: 5)
        encoder.invalidate()
        encoder.consume(
            makeVideoSampleBuffer(width: 640, height: 360, pts: CMTime(value: 6, timescale: 30)),
            type: .screen)
        encoder.completePendingFrames()
        // A stopped encoder is not a failed one — no callback, ring content intact.
        #expect(failure.message == nil)
        #expect(encoder.stats().sampleCount > 0)
    }

    @Test func keyframeFlagReadsNotSyncAttachment() {
        // No attachments at all ⇒ keyframe (02 §9: NotSync absent ⇒ keyframe).
        #expect(ReplayEncoder.isKeyframe(makeMarkerBuffer()))
    }
}
