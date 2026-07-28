import Foundation
import RecorderCore

/// How much recording the free disk still holds (M18-T4).
///
/// The disk guard only speaks at the fail-stop floor, which is the last possible moment — it stops
/// a take in progress. This is the same arithmetic said *before* you start (accuracy in docs/07).
public enum RecordingRoom {

    /// Below this the figure is worth a row; above it, it is noise on a healthy disk.
    public static let worthSaying: TimeInterval = 2 * 3600

    /// Seconds of recording the disk holds at `bitsPerSecond`, or nil when the rate is unknown.
    /// Pure.
    ///
    /// Counts only the space above the recording path's fail-stop floor: capture stops itself at
    /// `reserveBytes` (02 §7), so quoting raw free space would promise a take twice the length the
    /// guard allows. Zero is a real answer — "no room" is the case this figure exists for.
    public static func seconds(
        freeBytes: Int64, bitsPerSecond: Int,
        reserveBytes: Int64 = DiskSpaceMonitor.defaultFloorBytes
    ) -> TimeInterval? {
        guard bitsPerSecond > 0 else { return nil }
        return Double(max(0, freeBytes - reserveBytes)) / (Double(bitsPerSecond) / 8)
    }

    /// The menu row, or nil when there is plenty — `Room for about 40 min at High`. Floors the
    /// figure, so it is never larger than the truth. `presetName` is passed in because the preset's
    /// display names live with the views that show them.
    public static func phrase(seconds: TimeInterval?, presetName: String) -> String? {
        guard let seconds, seconds < worthSaying else { return nil }
        guard seconds >= 60 else { return "Not enough room to record at \(presetName)" }
        return "Room for about \(approximate(seconds)) at \(presetName)"
    }

    /// `40 min` / `1 hour 20 min` / `under a minute`, floored.
    static func approximate(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let (hours, rest) = (minutes / 60, minutes % 60)
        let hourPhrase = hours == 1 ? "1 hour" : "\(hours) hours"
        return rest == 0 ? hourPhrase : "\(hourPhrase) \(rest) min"
    }
}
