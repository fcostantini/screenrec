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
