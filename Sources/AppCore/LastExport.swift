import Foundation

/// The most recent export, for the menu's in-app receipt (M10-T2/T3) — the counterpart to
/// [[LastReplay]]. Reveals the file on click. Persisted so it survives relaunch (M12-T2), and
/// stamped with `date` so a receipt from an earlier session expires rather than squatting (M12-T3).
public struct LastExport: Equatable, Sendable {
    public let url: URL
    /// When the export finished — the basis for staleness (M12-T3).
    public let date: Date

    public init(url: URL, date: Date) {
        self.url = url
        self.date = date
    }

    /// The verb follows the output format — the three derive actions write distinct extensions
    /// (`.mp4` export, `.gif`, `.mov` trim), so the extension names the action.
    public var menuTitle: String {
        let verb: String
        switch url.pathExtension.lowercased() {
        case "gif": verb = "Saved as GIF"
        case "mov": verb = "Trimmed"
        default: verb = "Exported to MP4"
        }
        return "\(verb) · \(url.lastPathComponent)"
    }

    /// Whether the receipt has aged past the "just did it" window (M12-T3): a persisted receipt from
    /// an earlier session shouldn't reappear as fresh — the file still lives in Recent Exports.
    public func isStale(now: Date, freshFor: TimeInterval) -> Bool {
        now.timeIntervalSince(date) > freshFor
    }
}
