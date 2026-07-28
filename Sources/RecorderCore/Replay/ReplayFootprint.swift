import Foundation

/// Estimates what an armed replay holds in memory, so a surface can quote it before the user
/// arms (docs/04 §6.1: bitrate × (window + 2 s slack), plus the two PCM rings).
///
/// Quality is deliberately not an input: `ReplayEncoder` always encodes `.balanced`, so the ring
/// costs the same whatever the recording preset says.
public enum ReplayFootprint {
    /// System audio arrives 48 kHz stereo Float32 (docs/02 §1); every mic buffer is normalized to
    /// 48 kHz mono Float32 (`ResampledMicInput`). Both rings hold PCM, not compressed audio.
    static let systemAudioBytesPerSecond = 48_000 * 2 * 4
    static let microphoneBytesPerSecond = 48_000 * 1 * 4

    /// Bytes the rings retain for a `seconds` window of `width`×`height` capture. Returns 0 for a
    /// geometry or window that can't be estimated rather than a misleading number.
    public static func estimatedBytes(
        width: Int, height: Int, frameRateCap: Int, seconds: Double, includesMicrophone: Bool
    ) -> Int64 {
        guard width > 0, height > 0, frameRateCap > 0, seconds > 0, seconds.isFinite else { return 0 }
        let videoBytesPerSecond = Double(BitrateModel.averageBitrate(
            width: width, height: height, frameRate: frameRateCap, preset: .balanced)) / 8
        let audioBytesPerSecond = Double(
            systemAudioBytesPerSecond + (includesMicrophone ? microphoneBytesPerSecond : 0))
        let retained = seconds + ReplayWindow.slackSeconds
        return Int64(((videoBytesPerSecond + audioBytesPerSecond) * retained).rounded())
    }
}
