import AVFAudio
import CoreMedia

/// Normalizes every microphone buffer to ONE fixed format — 48 kHz mono Float32 (docs/03
/// M8-T1) — so a device/codec switch, or a rebuilt mic-only stream (M8-T2), can keep feeding
/// the same writer input and replay ring. Sits in the engine's mic path before `SampleRouter`
/// fan-out: consumers never see a device format.
///
/// PTS discipline (docs/03): each output buffer carries its input buffer's PTS and the
/// converter runs primeless, so no leading samples are invented and the host-clock timeline
/// is preserved; the SRC keeps its filter state across buffers for a continuous waveform.
///
/// Confined to the microphone sample queue — single-threaded by construction, no locking.
/// Allocation-light per docs/01: the input wraps the buffer's own payload no-copy, the ABL
/// scratch is stack-allocated, and the only per-buffer heap allocation is the emitted block.
/// Public: docs/03 names this the shared seam (engine path, and the M8 spike/T2 rebuild feed it).
public final class ResampledMicInput {

    /// The fixed target. `standardFormat` = Float32 deinterleaved; mono, so one plane.
    ///
    /// `AVAudioFormat` is immutable after init — every property is get-only — so the shared mutable
    /// state the compiler warns about does not exist. Kept a static because this is the mic sample
    /// path, where docs/01 cares about per-buffer allocation.
    public nonisolated(unsafe) static let targetFormat =
        AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    public init() {}

    private var converter: AVAudioConverter?
    private var output: AVAudioPCMBuffer?

    /// The converted buffer, the buffer itself when it already matches the target, or nil when
    /// conversion isn't possible (dropping one mic buffer beats corrupting the track).
    public func convert(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        else { return nil }
        if asbd.hasSameIdentity(as: Self.targetFormat.streamDescription.pointee) { return buffer }

        // (Re)build on any input-format change — a converter's state is format-specific.
        if converter.map({ !asbd.hasSameIdentity(as: $0.inputFormat.streamDescription.pointee) }) ?? true {
            let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
            guard let fresh = AVAudioConverter(from: format, to: Self.targetFormat) else { return nil }
            fresh.primeMethod = .none
            converter = fresh
        }
        guard let converter, CMSampleBufferGetNumSamples(buffer) > 0 else { return nil }

        // Slack over the exact ratio: an SRC's per-call output can wobble by a filter length.
        let frames = CMSampleBufferGetNumSamples(buffer)
        let ratio = Self.targetFormat.sampleRate / asbd.mSampleRate
        let needed = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
        if output == nil || output!.frameCapacity < needed {
            output = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: needed)
        }
        guard let output else { return nil }
        output.frameLength = 0

        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        return Self.withInputPCM(of: buffer, format: converter.inputFormat) { pcm in
            var fed = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
                if fed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                fed = true
                outStatus.pointee = .haveData
                return pcm
            }
            guard status != .error, output.frameLength > 0,
                  let channel = output.floatChannelData?[0] else { return nil }

            // Copied out, because `output` is reused for the next conversion while the emitted
            // buffer escapes downstream for arbitrarily long.
            let length = Int(output.frameLength) * MemoryLayout<Float>.size
            return PCMSampleBuffer.make(
                format: Self.targetFormat.formatDescription,
                sampleCount: Int(output.frameLength), pts: pts, byteLength: length
            ) { destination in
                memcpy(destination, channel, length)
                return true
            }
        }
    }

    /// Runs `body` with `buffer`'s PCM wrapped as an `AVAudioPCMBuffer` — no copy; the wrap is
    /// valid only inside `body` (the retained block anchors the payload, the ABL lives on the
    /// stack).
    private static func withInputPCM(
        of buffer: CMSampleBuffer, format: AVAudioFormat,
        _ body: (AVAudioPCMBuffer) -> CMSampleBuffer?
    ) -> CMSampleBuffer? {
        var neededSize = 0
        let probe = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: &neededSize, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            blockBufferOut: nil)
        guard neededSize > 0, probe == noErr || probe == kCMSampleBufferError_ArrayTooSmall
        else { return nil }

        return withUnsafeTemporaryAllocation(
            byteCount: neededSize, alignment: MemoryLayout<AudioBufferList>.alignment
        ) { scratch in
            guard let base = scratch.baseAddress else { return nil }
            let listPointer = base.assumingMemoryBound(to: AudioBufferList.self)
            var block: CMBlockBuffer?
            guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                buffer, bufferListSizeNeededOut: nil, bufferListOut: listPointer,
                bufferListSize: neededSize, blockBufferAllocator: nil,
                blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr,
                let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: listPointer)
            else { return nil }
            return withExtendedLifetime(block) { body(pcm) }
        }
    }
}
