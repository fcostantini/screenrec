/// Maps a `QualityPreset` to an average HEVC bitrate for the video track.
///
/// Model (docs/02 §3): `bitrate = width × height × fps × baseBitsPerPixel × hevcDiscount
/// × preset multiplier`. `baseBitsPerPixel` is the H.264-class bits-per-pixel-per-frame
/// figure; `hevcDiscount` reflects HEVC's efficiency over H.264 at matched quality. The
/// per-preset multipliers scale that baseline — efficient ½, balanced ×1, high ×1¾ — so
/// at fixed geometry the three presets are strictly ordered. The result feeds
/// `AVVideoAverageBitRateKey` in `MovieRecorder` (M2-T2).
///
/// Constants are the docs/02 §3 starting point; M2-T6 recalibrates them against Tier-1
/// output. Pure math with no stored state — no dependency on a live stream or display.
public enum BitrateModel {
    /// H.264-class bits per pixel per frame, before the HEVC discount.
    public static let baseBitsPerPixel = 0.05
    /// HEVC's bitrate advantage over H.264 at matched quality (0.6 ⇒ ~40% smaller).
    public static let hevcDiscount = 0.6

    /// Average video bitrate in whole bits/second for the given frame geometry and preset.
    ///
    /// `width`/`height` are pixels (from `CaptureConfiguration.pixelDimensions`), `frameRate`
    /// the fps cap. Degenerate geometry (a zero dimension) yields 0 — callers pass resolved
    /// display pixels, so this only guards arithmetic, not a real recording path.
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

    /// Per-preset scale over the baseline bits/pixel. Kept here (not on `QualityPreset`)
    /// so all bitrate math lives in one place, per the note in `CaptureConfiguration`.
    private static func multiplier(for preset: QualityPreset) -> Double {
        switch preset {
        case .efficient: return 0.5
        case .balanced: return 1.0
        case .high: return 1.75
        }
    }
}
