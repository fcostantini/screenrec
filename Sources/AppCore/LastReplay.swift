import Foundation

/// The most recent saved replay, for the menu's in-app confirmation (M9-T2). While replay is
/// armed the screen is captured, so macOS suppresses the "Replay saved" banner (docs/06
/// §Notifications) — this row is the save's receipt instead, and reveals the clip on click.
public struct LastReplay: Equatable, Sendable {
    public let url: URL
    public let seconds: Int

    /// Mirrors the notification's language; the count is the clip's real rounded length.
    public var menuTitle: String { "Replay saved · \(seconds) s" }
}
