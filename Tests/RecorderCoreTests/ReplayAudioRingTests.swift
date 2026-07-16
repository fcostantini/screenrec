import CoreMedia
import Testing

@testable import RecorderCore

/// Pure CoreMedia — no TCC, no VideoToolbox — so every path here runs headlessly.
struct ReplayAudioRingTests {

    /// 0.1 s of silence per buffer, delivered as system audio.
    private func feed(
        _ ring: ReplayAudioRing, buffers: Int,
        format: CMAudioFormatDescription, sampleRate: Int32
    ) {
        let framesPerBuffer = Int(sampleRate) / 10
        for index in 0..<buffers {
            ring.consume(
                makeAudioSampleBuffer(
                    format: format, frames: framesPerBuffer,
                    pts: CMTime(value: CMTimeValue(index * framesPerBuffer), timescale: sampleRate)),
                type: .systemAudio)
        }
    }

    @Test func byteCountMatchesDurationTimesFormatMath() {
        let ring = ReplayAudioRing(source: .systemAudio, seconds: 60)
        let format = makeAudioFormat(sampleRate: 48_000, channels: 2)
        feed(ring, buffers: 30, format: format, sampleRate: 48_000)  // 3 s
        let stats = ring.stats()

        // 30 buffers × 4800 frames × 4 B (16-bit stereo); span is start-to-start, so 2.9 s.
        #expect(stats.sampleCount == 30)
        #expect(stats.bytes == 30 * 4800 * 4)
        #expect(abs(stats.spanSeconds - 2.9) < 0.001)
        #expect(stats.format == ReplayAudioRing.Format(sampleRate: 48_000, channels: 2, bytesPerSample: 2))
        #expect(stats.format?.bytesPerSecond == 192_000)
    }

    /// SCK's system audio is non-interleaved Float32 (measured live 2026-07-16) — the format
    /// where per-plane `mBytesPerFrame` and sample-size bookkeeping both mislead. This is the
    /// test that reproduces the live 0-byte bug.
    @Test func handlesPlanarFloat32SystemAudio() {
        let ring = ReplayAudioRing(source: .systemAudio, seconds: 60)
        let format = makeAudioFormat(sampleRate: 48_000, channels: 2, planarFloat32: true)
        feed(ring, buffers: 10, format: format, sampleRate: 48_000)  // 1 s
        let stats = ring.stats()

        // 10 buffers × 4800 frames × 4 B × 2 planes; rate counts every channel.
        #expect(stats.bytes == 10 * 4800 * 4 * 2)
        #expect(stats.format == ReplayAudioRing.Format(sampleRate: 48_000, channels: 2, bytesPerSample: 4))
        #expect(stats.format?.bytesPerSecond == 384_000)
    }

    @Test func evictsBeyondCapacityPlusSlack() {
        let ring = ReplayAudioRing(source: .systemAudio, seconds: 2)
        let format = makeAudioFormat(sampleRate: 48_000, channels: 2)
        feed(ring, buffers: 80, format: format, sampleRate: 48_000)  // 8 s into a 2 s ring
        let stats = ring.stats()
        // Capacity 2 s + 2 s slack, measured start-to-start; one buffer of tolerance each way,
        // and the lower bound is what catches an over-eviction regression (a near-empty ring
        // passes any upper bound trivially).
        #expect(stats.spanSeconds <= 4.11)
        #expect(stats.spanSeconds >= 3.8)
        #expect(stats.sampleCount < 80)
        #expect(stats.sampleCount > 30)
        // Bytes must track eviction, not total intake.
        #expect(stats.bytes == stats.sampleCount * 4800 * 4)
    }

    @Test func storesDeepCopiesNotTheDeliveredBuffers() throws {
        let ring = ReplayAudioRing(source: .microphone, seconds: 60)
        let format = makeAudioFormat(sampleRate: 24_000, channels: 1)
        let delivered = makeAudioSampleBuffer(format: format, frames: 2400, pts: .zero)
        ring.consume(delivered, type: .microphone)

        let stored = try #require(ring.ringEntriesForTesting().first?.element)
        let sourceBlock = try #require(CMSampleBufferGetDataBuffer(delivered))
        let storedBlock = try #require(CMSampleBufferGetDataBuffer(stored))
        // Different backing storage is the whole point: SCK can recycle its buffer freely.
        #expect(sourceBlock !== storedBlock)
        #expect(CMBlockBufferGetDataLength(storedBlock) == 2400 * 2)
    }

    @Test func formatChangeClearsAndRelatches() {
        let ring = ReplayAudioRing(source: .microphone, seconds: 60)
        let airPods = makeAudioFormat(sampleRate: 24_000, channels: 1)
        let builtIn = makeAudioFormat(sampleRate: 48_000, channels: 1)

        ring.consume(makeAudioSampleBuffer(format: airPods, frames: 2400, pts: .zero), type: .microphone)
        ring.consume(
            makeAudioSampleBuffer(format: builtIn, frames: 4800, pts: CMTime(value: 2400, timescale: 24_000)),
            type: .microphone)

        let stats = ring.stats()
        // The pre-change audio is dead air for "the last N seconds" (and unmixable at mux):
        // the ring restarts at the new format rather than pinning stale content forever.
        #expect(stats.sampleCount == 1)
        #expect(stats.formatChanges == 1)
        #expect(stats.format?.sampleRate == 48_000)
        #expect(stats.bytes == 4800 * 2)
    }

    /// Same rate and channel count, different layout — the change the three-field identity
    /// (rate/channels/formatID) misses, and mixing the two layouts would corrupt a mux.
    @Test func layoutChangeAtSameRateCountsAsFormatChange() {
        let ring = ReplayAudioRing(source: .microphone, seconds: 60)
        let int16 = makeAudioFormat(sampleRate: 48_000, channels: 1)
        let float32 = makeAudioFormat(sampleRate: 48_000, channels: 1, planarFloat32: true)

        ring.consume(makeAudioSampleBuffer(format: int16, frames: 4800, pts: .zero), type: .microphone)
        ring.consume(
            makeAudioSampleBuffer(format: float32, frames: 4800, pts: CMTime(value: 4800, timescale: 48_000)),
            type: .microphone)

        let stats = ring.stats()
        #expect(stats.formatChanges == 1)
        #expect(stats.format == ReplayAudioRing.Format(sampleRate: 48_000, channels: 1, bytesPerSample: 4))
    }

    @Test func ignoresOtherSourcesAndFormatlessBuffers() {
        let ring = ReplayAudioRing(source: .systemAudio, seconds: 60)
        let format = makeAudioFormat(sampleRate: 48_000, channels: 2)
        ring.consume(makeAudioSampleBuffer(format: format, frames: 4800, pts: .zero), type: .microphone)
        ring.consume(makeMarkerBuffer(), type: .systemAudio)  // no format description → skipped
        #expect(ring.stats() == ReplayAudioRing.Stats(
            spanSeconds: 0, sampleCount: 0, bytes: 0, format: nil, formatChanges: 0, copyFailures: 0))
    }
}
