import Foundation

/// The most recent MP4 export, for the menu's in-app receipt (M10-T2) — the counterpart to
/// [[LastReplay]]. Reveals the `.mp4` on click. In-memory: the last export until the next one,
/// or app relaunch.
public struct LastExport: Equatable, Sendable {
    public let url: URL

    public var menuTitle: String { "Exported to MP4 · \(url.lastPathComponent)" }
}
