import CoreMedia

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
