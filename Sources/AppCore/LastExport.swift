import Foundation

/// The most recent export, for the menu's in-app receipt (M10-T2/T3) — the counterpart to
/// [[LastReplay]]. Reveals the file on click. In-memory: the last export until the next one, or
/// app relaunch.
public struct LastExport: Equatable, Sendable {
    public let url: URL

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
}
