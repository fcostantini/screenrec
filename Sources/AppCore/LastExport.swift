import Foundation

/// The most recent export, for the menu's in-app receipt (M10-T2/T3) — the counterpart to
/// [[LastReplay]]. Reveals the file on click. In-memory: the last export until the next one, or
/// app relaunch.
public struct LastExport: Equatable, Sendable {
    public let url: URL

    /// The verb follows the format, so a GIF's receipt doesn't read "Exported to MP4".
    public var menuTitle: String {
        let verb = url.pathExtension.lowercased() == "gif" ? "Saved as GIF" : "Exported to MP4"
        return "\(verb) · \(url.lastPathComponent)"
    }
}
