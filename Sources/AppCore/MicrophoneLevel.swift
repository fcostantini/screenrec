import Foundation
import RecorderCore

/// The menu-bar input meter's scale (M16-T5): a peak amplitude in, a number of lit bars out.
///
/// The thresholds are set by measurement, not taste. A quiet room reads **−79 … −42.7 dBFS**
/// depending on the microphone (docs/07), so the first bar has to sit above the loudest of those —
/// otherwise the meter shows a bar in silence and "no bars" stops meaning anything. That makes an
/// unlit meter the real signal: nothing is reaching this microphone.
public enum MicrophoneLevel {
    /// Lower edge of each bar, loudest first. Above the last one the meter reads "loud".
    public static let barThresholdsDBFS: [Float] = [-12, -24, -35]
    public static let barCount = barThresholdsDBFS.count

    /// Lit bars for a peak amplitude, 0 … `barCount`.
    public static func bars(forPeak peak: Float) -> Int {
        guard peak > 0 else { return 0 }
        let dBFS = 20 * log10(peak)
        // Loudest-first, so the first threshold the level clears gives the count.
        for (index, threshold) in barThresholdsDBFS.enumerated() where dBFS >= threshold {
            return barCount - index
        }
        return 0
    }
}
