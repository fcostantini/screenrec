import CoreMedia

enum SampleTiming {
    /// A copy of `buffer` shifted so its presentation time is `newPTS` (decode times shift by
    /// the same delta). Durations are untouched unless `duration` is given — needed when the
    /// copy becomes a track's LAST sample: the writer infers an invalid last duration from the
    /// previous pts delta, which inflates a tail-patched track by the whole frozen gap.
    /// Nil when the buffer has no numeric timing or the copy fails.
    static func retimed(
        _ buffer: CMSampleBuffer, to newPTS: CMTime, duration: CMTime? = nil
    ) -> CMSampleBuffer? {
        let originalPTS = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard originalPTS.isNumeric else { return nil }
        let delta = CMTimeSubtract(newPTS, originalPTS)

        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr, count > 0
        else { return nil }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(
            buffer, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count) == noErr
        else { return nil }
        for index in timings.indices {
            if timings[index].presentationTimeStamp.isNumeric {
                timings[index].presentationTimeStamp = CMTimeAdd(timings[index].presentationTimeStamp, delta)
            }
            if timings[index].decodeTimeStamp.isNumeric {
                timings[index].decodeTimeStamp = CMTimeAdd(timings[index].decodeTimeStamp, delta)
            }
            if let duration {
                timings[index].duration = duration
            }
        }
        var out: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: buffer,
            sampleTimingEntryCount: count, sampleTimingArray: &timings, sampleBufferOut: &out) == noErr
        else { return nil }
        return out
    }
}
