import Foundation
import RecorderCore

/// The take that just finished, for the menu's top-level receipt (M24-T3) — the counterpart to
/// [[LastReplay]] and [[LastExport]]. Reveals the file on click.
///
/// Not persisted, unlike `LastExport`: an export's receipt is its only pointer (the `.mov`-only
/// recents list can't show one), while a recording already lives in `Recordings ▸`. So this row is
/// prominence rather than access — and prominence expires, on the export receipt's own clock.
public struct LastRecording: Equatable, Sendable {
    public let url: URL
    public let duration: TimeInterval
    /// When the take finished — the basis for staleness.
    public let date: Date

    public init(url: URL, duration: TimeInterval, date: Date) {
        self.url = url
        self.duration = duration
        self.date = date
    }

    /// Names the take by what it is, not when: the timestamped filename is exactly what makes
    /// `Recordings ▸` hard to scan, so repeating it here would move the problem rather than fix it.
    public var menuTitle: String { "Recording saved · \(Timecode.length(duration))" }

    public func isStale(now: Date, freshFor: TimeInterval) -> Bool {
        now.timeIntervalSince(date) > freshFor
    }
}
