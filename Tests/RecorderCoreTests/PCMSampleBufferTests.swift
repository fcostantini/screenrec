import CoreMedia
import Foundation
import Testing
@testable import RecorderCore

/// The block-create → fill → ready-buffer dance, which `ResampledMicInput`'s emit and
/// `ReplayAudioRing`'s deep copy both go through: if it hands back a buffer whose bytes are not
/// the ones `fill` wrote, every mic sample downstream is wrong and nothing else would say so.
@Suite struct PCMSampleBufferTests {

    private static let format = makeAudioFormat(sampleRate: 48_000, channels: 1, planarFloat32: true)

    @Test func carriesTheBytesFillWroteAndTheTimingAsked() throws {
        let frames = 64
        let byteLength = frames * MemoryLayout<Float>.size
        let pts = CMTime(value: 3, timescale: 4)

        let buffer = try #require(PCMSampleBuffer.make(
            format: Self.format, sampleCount: frames, pts: pts, byteLength: byteLength
        ) { raw in
            raw.assumingMemoryBound(to: Float.self)
                .update(repeating: 0.25, count: frames)
            return true
        })

        #expect(CMSampleBufferGetNumSamples(buffer) == frames)
        #expect(CMSampleBufferGetPresentationTimeStamp(buffer) == pts)

        // Read the payload back out: a buffer of the right shape holding the wrong bytes is the
        // failure this exists to catch.
        let block = try #require(CMSampleBufferGetDataBuffer(buffer))
        var totalLength = 0
        var pointer: UnsafeMutablePointer<CChar>?
        #expect(CMBlockBufferGetDataPointer(
            block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength,
            dataPointerOut: &pointer) == noErr)
        #expect(totalLength == byteLength)
        let samples = try #require(pointer).withMemoryRebound(to: Float.self, capacity: frames) {
            Array(UnsafeBufferPointer(start: $0, count: frames))
        }
        #expect(samples.allSatisfy { $0 == 0.25 })
    }

    @Test func abortsToNilWhenFillFails() {
        // `fill` returning false means the producer couldn't supply the samples; handing back a
        // buffer of uninitialized memory would publish noise as audio.
        #expect(PCMSampleBuffer.make(
            format: Self.format, sampleCount: 64, pts: .zero, byteLength: 256, fill: { _ in false })
            == nil)
    }
}
