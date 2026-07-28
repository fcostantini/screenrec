import Foundation
import RecorderCore

/// Text for the menu's rows (docs/06 "Menu"). Pure string-making, kept out of the views so
/// docs/06's copy rules are testable.
public enum MenuHeader {

    /// Elapsed time, always `HH:MM:SS` per docs/06's copy rules.
    ///
    /// The non-finite guard is load-bearing: `recordedDuration` is `.invalid`/NaN until the
    /// first frame starts the session (02 §10), and `Int(nan)` traps.
    public static func elapsed(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// The recording header's right-hand detail: `41.2 MB · HEVC`. docs/06 mandates
    /// `ByteCountFormatter` for sizes.
    public static func recordingDetail(bytes: Int64) -> String {
        let size = ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
        return "\(size) · HEVC"
    }

    /// The idle header's right-hand status: `Ready`, or the blocking condition.
    ///
    /// Every non-ready verdict collapses to one short phrase; `RecordingReadiness.blocked`'s
    /// full remedy sentence is the onboarding window's to show, not a menu row's.
    public static func idleStatus(_ readiness: RecordingReadiness) -> String {
        switch readiness {
        case .ready: "Ready"
        case .needsScreenRecording, .needsMicrophone, .blocked: "Permissions needed…"
        }
    }

    /// The output folder shown on `Open Recordings Folder` (docs/06 item 9): the destination as a
    /// home-relative path (`~/Movies`), so the menu says where recordings go without opening it.
    ///
    /// Long paths keep only their tail: a menu sizes itself to its widest row and can't
    /// truncate visually, so a deep folder would stretch the whole menu across the screen. The
    /// tail is the part the user chose; elided ancestry is one click away in Finder.
    public static func recordingsFolder(_ directory: URL) -> String {
        let abbreviated = (directory.path as NSString).abbreviatingWithTildeInPath
        guard abbreviated.count > maxFolderDisplayLength else { return abbreviated }

        var tail = ""
        for component in abbreviated.split(separator: "/").reversed() {
            let candidate = "/\(component)\(tail)"
            if !tail.isEmpty, candidate.count + 1 > maxFolderDisplayLength { break }
            tail = candidate
        }
        // A single component longer than the budget keeps its end — the most specific part.
        return "…" + tail.suffix(maxFolderDisplayLength)
    }

    private static let maxFolderDisplayLength = 40

    /// The `Stop After` pick as a row title (M18-T4): `Off`, `5 min`, `1 hour` — through the same
    /// phrasing the disk row uses, so the two can't drift.
    public static func stopAfter(_ minutes: Int) -> String {
        minutes == 0 ? "Off" : RecordingRoom.approximate(Double(minutes) * 60)
    }

    /// What the recording menu says about a bound already running: an absolute clock time, never a
    /// countdown — the menu is stamped at open and must not tick (M6-T10). Locale-formatted, so a
    /// 12-hour Mac reads `Stops at 2:35 PM` rather than a 24-hour figure that could be misread as
    /// a duration.
    public static func stopsAt(
        _ date: Date, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "Stops at \(formatter.string(from: date))"
    }
}
