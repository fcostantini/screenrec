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

    /// The estimate as a surface should show it: two significant figures, in the user's locale.
    /// `183,1 MB` would read as a measurement — this is a model, so it rounds to `180 MB`.
    public static func formatted(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: roundedToTwoSignificantFigures(bytes))
    }

    static func roundedToTwoSignificantFigures(_ bytes: Int64) -> Int64 {
        guard bytes > 0 else { return 0 }
        let magnitude = pow(10, (log10(Double(bytes)).rounded(.down) - 1))
        guard magnitude >= 1 else { return bytes }
        return Int64(((Double(bytes) / magnitude).rounded() * magnitude).rounded())
    }

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        // `.file` is decimal, which is what Finder shows the same file as.
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter
    }()
}
