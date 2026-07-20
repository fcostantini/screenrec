import CoreMedia

/// The one home of the block-create → fill → ready-sample-buffer dance for PCM audio
/// (`ResampledMicInput`'s emit and `ReplayAudioRing`'s deep copy). `fill` writes exactly
/// `byteLength` bytes into the freshly-allocated block; returning false aborts to nil.
enum PCMSampleBuffer {
    static func make(
        format: CMAudioFormatDescription, sampleCount: Int, pts: CMTime, byteLength: Int,
        fill: (UnsafeMutableRawPointer) -> Bool
    ) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteLength,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: byteLength, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block) == noErr,
            let block
        else { return nil }

        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(
            block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil,
            dataPointerOut: &pointer) == noErr,
            let raw = pointer,
            fill(UnsafeMutableRawPointer(raw))
        else { return nil }

        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: sampleCount, presentationTimeStamp: pts,
            packetDescriptions: nil, sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }
}
