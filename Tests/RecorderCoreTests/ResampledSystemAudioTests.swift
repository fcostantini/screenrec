import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import RecorderCore

/// Normalising a process tap's audio (M27-T5). A tap's rate **follows the output device** — 24 kHz
/// and 48 kHz were both measured on one Mac in a day — where SCK's system audio is always 48 kHz.
/// These pin the conversion, which the hardware only exercises when it happens to be at 24 kHz.
@Suite struct ResampledSystemAudioTests {

    private static func asbd(of buffer: CMSampleBuffer) -> AudioStreamBasicDescription? {
        CMSampleBufferGetFormatDescription(buffer)
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
    }

    @Test func aTwentyFourKilohertzTapBecomesFortyEight() throws {
        let input = makeAudioFormat(sampleRate: 24_000, channels: 2, planarFloat32: true)
        let resampler = ResampledMicInput(target: ResampledMicInput.systemAudioTarget)
        let converted = try #require(
            resampler.convert(
                makeAudioSampleBuffer(format: input, frames: 2400, pts: .zero, amplitude: 0.5)))

        let out = try #require(Self.asbd(of: converted))
        #expect(out.mSampleRate == 48_000)
        #expect(out.mChannelsPerFrame == 2)
        // Twice the rate, so about twice the frames — an SRC's output wobbles by a filter length.
        #expect(abs(CMSampleBufferGetNumSamples(converted) - 4800) < 100)
    }

    @Test func audioAlreadyAtTheTargetIsHandedOnUntouched() throws {
        // The common case: no converter, no copy, the same buffer object straight through.
        // The target's own format description, so "already at the target" is exact — the shared
        // helper builds 16-bit or planar audio, neither of which is what a tap delivers.
        let buffer = makeAudioSampleBuffer(
            format: ResampledMicInput.systemAudioTarget.formatDescription, frames: 960, pts: .zero)
        let resampler = ResampledMicInput(target: ResampledMicInput.systemAudioTarget)
        #expect(resampler.convert(buffer) === buffer)
    }

    @Test func theSystemAudioTargetIsOneContiguousStereoBlock() {
        // Interleaved on purpose: `PCMSampleBuffer.make` writes a single block, and a planar stereo
        // target would emit one channel and mislabel its length.
        let target = ResampledMicInput.systemAudioTarget.streamDescription.pointee
        #expect(target.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0)
        #expect(target.mChannelsPerFrame == 2)
        #expect(target.mBytesPerFrame == 8)  // 2 ch × Float32
    }

    @Test func theMicrophonesOwnTargetIsUnchanged() {
        // This task edited the mic path's converter. Its default must not have moved.
        let mic = ResampledMicInput.targetFormat.streamDescription.pointee
        #expect(mic.mSampleRate == 48_000)
        #expect(mic.mChannelsPerFrame == 1)
    }
}
