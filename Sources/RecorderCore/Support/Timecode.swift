import Foundation

/// Every time this app renders on screen. Three renderers, because there are three honest
/// roundings — and the rounding is in the name so a new surface can't inherit the wrong one by
/// leaving a parameter at its default.
public enum Timecode {

    /// `M:SS`, **floored** — a point you can cut at. Rounding up would name a frame the file
    /// doesn't keep, which is what the trim window's `In`/`Out` and its lead-in sentence must agree
    /// on (M18-T1).
    public static func cutPoint(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// `HH:MM:SS`, truncated — a clock that is still running.
    ///
    /// ⚠️ The non-finite guard is load-bearing: a recording's duration is `.invalid`/NaN until the
    /// first frame starts the session (02 §10), and `Int(nan)` traps.
    public static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// `M:SS`, growing to `H:MM:SS` past an hour, **rounded** — a finished thing's length, where
    /// the number is a label rather than a cut point. The menu's tighter form of docs/06's
    /// `HH:MM:SS`.
    public static func length(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        guard whole >= 3600 else { return cutPoint(Double(whole)) }
        return String(format: "%d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
    }
}
