import AppCore

/// The Instant Replay pane's banner caption, by what the app can actually tell (ADR-022).
///
/// Extracted from the view so the copy is assertable without rendering SwiftUI. ⚠️ Unlike the menu
/// row, which vanishes when there is nothing to warn about, this one **states the good news**: a
/// Settings pane is where you go to find out how something is configured, and "this is fine" is an
/// answer there.
enum ArmedBannerCaption {

    static func text(for banners: BannerVisibility) -> String {
        switch banners {
        case .hidden:
            return "While replay is armed, macOS hides notification banners — ScreenRec's and other "
                + "apps'. To keep seeing them, turn on \"Allow notifications when mirroring or "
                + "sharing the display\" in System Settings › Notifications."
        case .shown:
            return "Notification banners keep working while replay is armed, because you've allowed "
                + "them when sharing the display."
        // A failed read degrades to the hedge, never to a claim (ADR-022) — which is the wording this
        // caption used unconditionally before it could read anything.
        case .unknown:
            return "While replay is armed, macOS may hide notification banners — ScreenRec's and "
                + "other apps'. To keep seeing them, turn on \"Allow notifications when mirroring or "
                + "sharing the display\" in System Settings › Notifications."
        }
    }
}
