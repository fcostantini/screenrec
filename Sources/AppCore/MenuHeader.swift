import Foundation
import RecorderCore

/// Text for the menu's header row (docs/06 "Menu — idle state" item 1, "Menu — recording
/// state" item 1). Pure string-making, kept out of the views so the copy rules in docs/06 are
/// testable rather than a matter of trust.
public enum MenuHeader {

    /// Elapsed time, always `HH:MM:SS` per docs/06's copy rules. (Tabular numerals are the
    /// view's job — this only decides the digits.)
    ///
    /// The non-finite guard is belt-and-braces, not the last line of defence: `refreshProgress`
    /// already sanitizes before anything reaches here. It stays because the trap it prevents is
    /// real and cheap to prevent — `recordedDuration` is `.invalid`/NaN until the first frame
    /// starts the session (docs/02 §10) and `Int(nan)` traps — and because this is a public
    /// formatter that will outlive its one current caller.
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
    /// Every non-ready verdict collapses to one short phrase because this is a menu row, not a
    /// place to explain. `RecordingReadiness.blocked` carries a full remedy sentence for the
    /// onboarding window (M4-T3) to show — putting it here would blow out the menu's width to
    /// say something the user can't act on from a disabled row.
    public static func idleStatus(_ readiness: RecordingReadiness) -> String {
        switch readiness {
        case .ready: "Ready"
        case .needsScreenRecording, .needsMicrophone, .blocked: "Permissions needed…"
        }
    }
}
