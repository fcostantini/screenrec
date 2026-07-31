import AVFoundation
import CoreGraphics
import Foundation

/// The Trim window's filmstrip (M24-T4): a fixed number of thumbnails spread across a clip.
///
/// `AVAssetImageGenerator`, not `VideoFrameReader`: the reader is sequential from zero (it was
/// built for GIF), so a strip across a long take would decode the whole file. These are
/// random-access seeks, which is why cost tracks the **thumbnail count and the source's keyframe
/// spacing, not the take's length** — measured 785 ms for 16 against a recording whose keyframes
/// average 2.39 s apart, and 221 ms against one at 0.98 s (docs/07).
public enum FilmstripThumbnails {

    /// Where the thumbnails are sampled from: the centre of each of `count` equal slices, so the
    /// first isn't a black leading frame and the last isn't past the final sample.
    public static func times(count: Int, duration: Double) -> [Double] {
        guard count > 0, duration > 0, duration.isFinite else { return [] }
        return (0..<count).map { duration * (Double($0) + 0.5) / Double(count) }
    }

    /// Thumbnails for `times`, each fitted within `maxPixels`, yielded **as they arrive** so the
    /// strip fills in rather than blocking: the first lands in ~80 ms while all 16 take ~785 ms.
    ///
    /// The seek is deliberately tolerant. A ±0.5 s thumbnail is orientation, and exact seeking
    /// measured ~1.7× the cost for a 30 pt image nobody reads a timecode off (docs/07); the frame
    /// step, where exactness is the point, uses `AVPlayer.step(byCount:)` instead.
    public static func stream(
        for asset: AVAsset, times: [Double], maxPixels: Int
    ) -> AsyncStream<(index: Int, image: CGImage)> {
        AsyncStream { continuation in
            guard !times.isEmpty else { continuation.finish(); return }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance

            // Keyed on the quantised `CMTimeValue`, never on the `Double` that produced it: the
            // callback reports the time it was *asked* for, which has been through the timescale —
            // 12.10406 s comes back as 12.10333, so a seconds-based key silently drops that frame.
            // Later duplicates lose, which only happens when a clip is shorter than the strip's
            // resolution; the strip then has repeats rather than a trap.
            let stamps = times.map { CMTime(seconds: $0, preferredTimescale: Self.timescale) }
            let byTime = Dictionary(
                zip(stamps.map(\.value), stamps.indices), uniquingKeysWith: { first, _ in first })
            var outstanding = stamps.count

            generator.generateCGImagesAsynchronously(forTimes: stamps.map(NSValue.init(time:))) {
                requestedTime, image, _, _, _ in
                if let image, let index = byTime[requestedTime.value] {
                    continuation.yield((index: index, image: image))
                }
                outstanding -= 1
                if outstanding == 0 { continuation.finish() }
            }
            // Cancelling the consuming task must stop the decode: a superseded strip would
            // otherwise keep a multi-GB asset's pipeline alive behind the new one.
            continuation.onTermination = { _ in generator.cancelAllCGImageGeneration() }
        }
    }

    private static let tolerance = CMTime(seconds: 0.5, preferredTimescale: timescale)
    private static let timescale: CMTimeScale = 600
}
