import AVFoundation
import Foundation

/// Reads what a surface needs to *describe* a recording without playing it (M18-T3).
public enum MediaFile {

    /// The playable length of a file, or nil when it can't be read (mid-write, gone, not media).
    ///
    /// A header read, not a scan — a few ms whatever the file's size. Async anyway, so a caller on
    /// a slow or absent volume never blocks.
    public static func duration(of url: URL) async -> Double? {
        guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds,
              seconds.isFinite, seconds > 0
        else { return nil }
        return seconds
    }

    /// The pixel size of a file's first video track, or nil when it can't be read (no video track,
    /// gone, not media). Same header read as `duration(of:)`.
    ///
    /// `naturalSize` is pre-transform, so a rotated source would report its stored size; nothing in
    /// this app writes a transform, and the size feeds a byte estimate where the pixel count — which
    /// a rotation doesn't change — is all that matters.
    public static func dimensions(of url: URL) async -> (width: Int, height: Int)? {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              size.width > 0, size.height > 0
        else { return nil }
        return (Int(size.width), Int(size.height))
    }
}
