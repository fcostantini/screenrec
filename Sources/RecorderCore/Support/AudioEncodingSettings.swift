import AVFoundation

/// The one place AAC output settings come from, so recording (`MovieRecorder`) and replay
/// (`ReplayMuxer`) encode audio identically — 192 kbps stereo system, 160 kbps mic, snapped
/// to what the encoder actually supports.
enum AudioEncodingSettings {
    static func aac(sampleRate: Double, channels: Int, bitRate: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: supportedAACBitRate(
                target: bitRate, sampleRate: sampleRate, channels: channels),
        ]
    }

    /// Snaps `target` to a rate in `AVAudioConverter.applicableEncodeBitRates` for this format:
    /// the AAC encoder accepts only a discrete set that shrinks with the format (24 kHz mono
    /// tops out at 64 kbps), and an out-of-set value fails the writer with -12651. Picks the
    /// highest supported rate ≤ target; falls back to target if the encoder can't be queried.
    private static func supportedAACBitRate(target: Int, sampleRate: Double, channels: Int) -> Int {
        let bytesPerFrame = UInt32(2 * channels)
        var sourceASBD = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
        guard let source = AVAudioFormat(streamDescription: &sourceASBD),
              let destination = AVAudioFormat(settings: [
                  AVFormatIDKey: kAudioFormatMPEG4AAC,
                  AVSampleRateKey: sampleRate,
                  AVNumberOfChannelsKey: channels,
              ]),
              let converter = AVAudioConverter(from: source, to: destination),
              let rates = converter.applicableEncodeBitRates?.compactMap({ $0.intValue }),
              !rates.isEmpty else {
            return target
        }
        return rates.filter { $0 <= target }.max() ?? rates.min() ?? target
    }
}
