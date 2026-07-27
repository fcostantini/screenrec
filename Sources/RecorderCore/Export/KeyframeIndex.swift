import AVFoundation
import CoreMedia
import Foundation

/// Where a lossless trim will actually cut.
///
/// A passthrough trim copies streams, so the in-point must land on a sync sample and snaps
/// *backwards*. The gap is NOT bounded by `AVVideoMaxKeyFrameIntervalDurationKey` (2 s, docs/02 §3):
/// that caps encoded frames, and capture is frame-on-change — a static stretch emits no frames, so
/// no keyframes either. Measured on a real recording: **3.37 s back from a 61 s in-point** on a
/// 23-minute file. The gap is effectively unbounded, and worst when the screen was quiet, which is
/// exactly where people trim.
public enum KeyframeIndex {

    /// The presentation time a lossless trim starting at `seconds` will really begin at, or nil if
    /// the asset has no readable video track.
    ///
    /// Walks back in decode order from the requested point to the nearest full sync sample. The walk
    /// is bounded by the keyframe spacing, not the file length: measured **0.0–0.9 ms** across a
    /// 23-minute recording, so this is safe to call live while the user drags.
    public static func cutPoint(for asset: AVAsset, startingAt seconds: Double) async -> Double? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let cursor = track.makeSampleCursor(
                presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600))
        else { return nil }
        // A malformed file could otherwise walk the whole track; the bound is generous next to the
        // ~116 steps the worst measured gap needed.
        var remaining = 10_000
        while !cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue, remaining > 0 {
            guard cursor.stepInDecodeOrder(byCount: -1) == -1 else { break }  // reached the first sample
            remaining -= 1
        }
        return cursor.presentationTimeStamp.seconds
    }

    /// How the trim window states the cut. Nil when the requested point already lands on a keyframe:
    /// a caveat with nothing to warn about is noise, and the old copy warned unconditionally while
    /// never giving the number.
    ///
    /// Pure, so the sentence the user acts on is unit-tested away from AVFoundation.
    public static func cutDescription(
        requested: Double, actual: Double, tolerance: Double = 0.05
    ) -> String? {
        guard requested - actual > tolerance else { return nil }
        return "In \(timecode(requested)) → cuts at \(timecode(actual))"
    }

    /// `M:SS`, matching the trim window's existing timecodes.
    static func timecode(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
