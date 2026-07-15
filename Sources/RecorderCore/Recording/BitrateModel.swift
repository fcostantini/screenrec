/// Maps a `QualityPreset` to an average HEVC bitrate for the video track.
///
/// Model (docs/02 §3): `bitrate = width × height × fps × baseBitsPerPixel × hevcDiscount
/// × preset multiplier`. Feeds `AVVideoAverageBitRateKey` in `MovieRecorder`.
///
/// Pure math with no stored state — no dependency on a live stream or display.
public enum BitrateModel {
    /// H.264-class bits per pixel per frame, before the HEVC discount.
    public static let baseBitsPerPixel = 0.05
    /// HEVC's bitrate advantage over H.264 at matched quality (0.6 ⇒ ~40% smaller).
    public static let hevcDiscount = 0.6

    /// Average video bitrate in whole bits/second for the given frame geometry and preset.
    ///
    /// `width`/`height` are pixels (from `CaptureConfiguration.pixelDimensions`), `frameRate`
    /// the fps cap. A zero dimension yields 0.
    public static func averageBitrate(
        width: Int,
        height: Int,
        frameRate: Int,
        preset: QualityPreset
    ) -> Int {
        let pixelsPerSecond = Double(width) * Double(height) * Double(frameRate)
        let bits = pixelsPerSecond * baseBitsPerPixel * hevcDiscount * multiplier(for: preset)
        return Int(bits.rounded())
    }

    /// Per-preset scale over the baseline bits/pixel. Kept here, not on `QualityPreset`, so all
    /// bitrate math lives in one place.
    private static func multiplier(for preset: QualityPreset) -> Double {
        switch preset {
        case .efficient: return 0.5
        case .balanced: return 1.0
        case .high: return 1.75
        }
    }
}
