import Foundation
import RecorderCore

/// Text for the menu's header row (docs/06 "Menu — idle state" item 1, "Menu — recording
/// state" item 1). Pure string-making, kept out of the views so docs/06's copy rules are
/// testable.
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
}
