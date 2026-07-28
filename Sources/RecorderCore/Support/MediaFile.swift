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
}
