import Foundation
import RecorderCore

/// Text for the menu's rows (docs/06 "Menu"). Pure string-making, kept out of the views so
/// docs/06's copy rules are testable.
public enum MenuHeader {

    /// The recording header's right-hand detail: `41.2 MB · HEVC`. docs/06 mandates
    /// `ByteCountFormatter` for sizes.
    public static func recordingDetail(bytes: Int64) -> String {
        let size = ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
        return "\(size) · HEVC"
    }

    /// The `Stop & Copy MP4` row (M21-T2): the cost is stated before the click, not discovered
    /// after it. **`up to`, not `≈`** — the figure is the encoder's rate budget, and VideoToolbox
    /// spends far less on a quiet screen (measured 2.2 MB against this row's 11, docs/07). Without
    /// the geometry to compute one the row is the action alone (M16-T2).
    public static func stopAndCopy(maximumBytes: Int64?) -> String {
        guard let maximumBytes, maximumBytes > 0 else { return "Stop & Copy MP4" }
        return "Stop & Copy MP4 · up to \(ApproximateBytes.formatted(maximumBytes))"
    }

    /// The export row (M28-T4). The percentage rides in the title, not only in the drawn bar,
    /// because the title is what VoiceOver reads — a bar alone leaves that reader the frozen row
    /// this row exists to fix. Nil progress keeps the filename, since there is nothing else to say.
    public static func exporting(_ name: String, fraction: Double?) -> String {
        guard let fraction else { return "Exporting \(name)…" }
        return "Exporting… \(exportPercent(fraction))%"
    }

    /// One rounding rule, so the drawn bar and the number it sits beside can never disagree.
    public static func exportPercent(_ fraction: Double) -> Int {
        Int((min(1, max(0, fraction)) * 100).rounded())
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
