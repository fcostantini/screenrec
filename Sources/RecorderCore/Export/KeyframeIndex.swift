import AVFoundation
import CoreMedia
import Foundation

/// What a lossless trim keeps that the user didn't ask for.
///
/// A passthrough trim copies streams, so the file must start at a sync sample — but the export
/// writes an edit list, so playback still begins exactly at the in-point (measured: the first
/// presented frame is byte-identical to the source there, in AVFoundation and ffmpeg alike). The
/// frames between the sync sample and the in-point stay *in the file*, hidden: `ffprobe
/// -ignore_editlist 1` decodes them (docs/02 §6a). The gap is NOT bounded by
/// `AVVideoMaxKeyFrameIntervalDurationKey` (2 s, docs/02 §3): that caps encoded frames, and capture
/// is frame-on-change, so a static stretch emits none. Measured 3.43 s on a 23-minute recording.
public enum KeyframeIndex {

    /// The presentation time of the earliest frame a lossless trim from `seconds` keeps in the
    /// file — the sync sample at or before the in-point — or nil if the asset has no readable
    /// video track.
    ///
    /// Walks back in decode order from the requested point. The walk is bounded by the keyframe
    /// spacing, not the file length: measured **0.0–0.9 ms** across a 23-minute recording, so this
    /// is safe to call live while the user drags.
    public static func leadInStart(for asset: AVAsset, trimmingFrom seconds: Double) async -> Double? {
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

    /// Sync samples don't land on whole seconds, so a lead-in this short is a rounding artefact,
    /// not something to tell the user about.
    private static let subFrameTolerance = 0.05

    /// How the trim window states it. Nil when the in-point already sits on a sync sample: nothing
    /// is hidden, and a caveat with nothing to warn about is noise.
    public static func leadInDescription(requested: Double, start: Double) -> String? {
        let leadIn = requested - start
        guard leadIn > subFrameTolerance else { return nil }
        return String(
            format: "Starts exactly at %@ · keeps %.1f s before it inside the file",
            timecode(requested), leadIn)
    }

    /// `M:SS`, floored — the one timecode the trim window and the CLI both render, so a lead-in
    /// sentence can't disagree with the `In`/`Out` readouts beside it.
    public static func timecode(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
