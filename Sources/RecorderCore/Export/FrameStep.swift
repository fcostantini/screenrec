import AVFoundation
import CoreMedia
import Foundation

/// Moving the playhead one *real* frame (M24-T4).
///
/// Not `AVPlayerItem.step(byCount:)`, which assumes a fixed cadence: capture is frame-on-change
/// (docs/02 §1a), so a screen recording's frames are irregularly spaced and a step lands wherever
/// the nominal rate says. Measured on a 48.1 fps-nominal take: one `step(byCount: 1)` moved
/// **0.25 s — three frames — and 25 ms off any source frame**. Walking the sample table instead
/// lands exactly, and round-trips to the same time (docs/07).
public enum FrameStep {

    /// The presentation time `count` frames away from `seconds` in presentation order, or nil when
    /// the asset has no readable video track or the walk runs off the end.
    ///
    /// Bounded by `count`, not by the file length — the same cursor `KeyframeIndex` walks, which
    /// measured 0.0–0.9 ms over a much longer traversal, so this is safe to call on a keypress.
    public static func time(in asset: AVAsset, from seconds: Double, by count: Int) async -> Double? {
        guard count != 0,
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let cursor = track.makeSampleCursor(
                presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600))
        else { return nil }

        let direction: Int64 = count > 0 ? 1 : -1
        for _ in 0..<abs(count) where cursor.stepInPresentationOrder(byCount: direction) != direction {
            return nil   // the first or last frame: staying put beats reporting a move that didn't happen
        }
        return cursor.presentationTimeStamp.seconds
    }
}
