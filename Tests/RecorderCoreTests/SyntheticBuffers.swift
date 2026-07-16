import CoreMedia
import CoreVideo

/// A filled BGRA frame wrapped as a ready `CMSampleBuffer` — the shared video fixture
/// (MovieRecorder writes it, ReplayEncoder encodes it). IOSurface-backed because that's what SCK
/// delivers and what the hardware encoder wants; vary `shade` per frame so encoders see real
/// deltas instead of identical stills.
func makeVideoSampleBuffer(
    width: Int, height: Int, pts: CMTime,
    duration: CMTime = CMTime(value: 1, timescale: 30), shade: UInt8 = 0x40
) -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
    let createStatus = CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)
    precondition(createStatus == kCVReturnSuccess, "CVPixelBufferCreate failed: \(createStatus)")
    let pixels = pixelBuffer!

    CVPixelBufferLockBaseAddress(pixels, [])
    memset(
        CVPixelBufferGetBaseAddress(pixels), Int32(shade),
        CVPixelBufferGetBytesPerRow(pixels) * height)
    CVPixelBufferUnlockBaseAddress(pixels, [])

    var format: CMVideoFormatDescription?
    precondition(
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format)
            == noErr)
    var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    precondition(
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescription: format!,
            sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
    return sample!
}

/// Linear-PCM format — the shared audio fixture (MovieRecorder writes it, ReplayAudioRing
/// buffers it). Default is 16-bit interleaved; `planarFloat32: true` mirrors what SCK's system
/// audio actually delivers (non-interleaved Float32, where `mBytesPerFrame` is per-plane).
func makeAudioFormat(
    sampleRate: Double, channels: UInt32, planarFloat32: Bool = false
) -> CMAudioFormatDescription {
    let bytesPerFrame = planarFloat32 ? 4 : 2 * channels
    var asbd = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: planarFloat32
            ? kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
            : kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: bytesPerFrame,
        mFramesPerPacket: 1,
        mBytesPerFrame: bytesPerFrame,
        mChannelsPerFrame: channels,
        mBitsPerChannel: planarFloat32 ? 32 : 16,
        mReserved: 0)
    var format: CMAudioFormatDescription?
    precondition(
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
            == noErr)
    return format!
}

/// `frames` of silence in `format`, as a ready `CMSampleBuffer`. Byte size derives from the
/// format's own bytes-per-frame, so a test's byte math can't disagree with the ASBD.
func makeAudioSampleBuffer(
    format: CMAudioFormatDescription, frames: Int, pts: CMTime
) -> CMSampleBuffer {
    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)!.pointee
    // Planar layouts carry one plane per channel; `mBytesPerFrame` covers a single plane.
    let planes = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        ? Int(asbd.mChannelsPerFrame) : 1
    let dataSize = frames * Int(asbd.mBytesPerFrame) * planes
    var blockBuffer: CMBlockBuffer?
    precondition(
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: dataSize, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer) == noErr)
    CMBlockBufferFillDataBytes(
        with: 0, blockBuffer: blockBuffer!, offsetIntoDestination: 0, dataLength: dataSize)

    var sampleBuffer: CMSampleBuffer?
    precondition(
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer!, formatDescription: format,
            sampleCount: frames, presentationTimeStamp: pts, packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer) == noErr)
    return sampleBuffer!
}

/// A minimal empty `CMSampleBuffer`: a valid object with no data or format. Enough for anything
/// that only inspects the `SourceType` it was routed as (fan-out, watchdog heartbeats).
///
/// Shared because three suites had grown verbatim copies of it — the same rule-of-three trigger
/// that produced `pollingTask`, which M3-T5 applied to the source loop and initially missed here.
func makeMarkerBuffer() -> CMSampleBuffer {
    var buffer: CMSampleBuffer?
    let status = CMSampleBufferCreate(
        allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true,
        makeDataReadyCallback: nil, refcon: nil, formatDescription: nil,
        sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil,
        sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer)
    precondition(status == noErr, "CMSampleBufferCreate failed: \(status)")
    return buffer!
}
