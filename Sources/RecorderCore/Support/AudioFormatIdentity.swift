import CoreAudioTypes

extension AudioStreamBasicDescription {
    /// Whether two PCM streams are the same for docs/02 §4 purposes — a change in any of these
    /// means the device (or its codec) switched and the streams' payloads are not miscible.
    /// Layout fields included: same rate/channels in a different layout (interleaved Int16 vs
    /// planar Float32) is just as incompatible as a rate change. Shared by
    /// `ResampledMicInput`'s rebuild check and `ReplayAudioRing`'s re-latch so the two can't
    /// disagree on "switched".
    func hasSameIdentity(as other: AudioStreamBasicDescription) -> Bool {
        mSampleRate == other.mSampleRate
            && mChannelsPerFrame == other.mChannelsPerFrame
            && mFormatID == other.mFormatID
            && mFormatFlags == other.mFormatFlags
            && mBitsPerChannel == other.mBitsPerChannel
    }
}
