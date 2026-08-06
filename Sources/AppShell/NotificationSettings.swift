import AppCore
import AppKit

/// The notification-settings AppKit edges: the deep-link to the system pane, and the one-time
/// armed-replay banner-suppression alert (M12-T5). Both point at the same fix — turning on "Allow
/// notifications when mirroring or sharing the display".
enum NotificationSettings {

    /// Best effort: deep-links to the Notifications pane; degrades to opening System Settings if the
    /// extension identifier ever changes.
    static func open() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The first-arm alert (M12-T5), fired once ever via AppState's `onReplayBannerWarning` seam;
    /// the dimmed armed-menu row is the standing reminder after. The second button routes to the fix.
    ///
    /// The wording follows what M35-T1 could establish: a read that succeeded states the fact, a read
    /// that failed keeps the hedge the app used when it could read nothing at all.
    @MainActor static func showArmedBannerWarning(_ banners: BannerVisibility) {
        // AppState only fires this when a warning is warranted; belt-and-braces so a future caller
        // cannot warn someone whose banners work.
        guard banners.warrantsWarning else { return }
        let alert = NSAlert()
        switch banners {
        case .hidden:
            alert.messageText = "Notification banners will be hidden while replay is armed"
            alert.informativeText =
                "Arming Instant Replay captures your screen, and macOS then hides notification "
                + "banners from every app — Slack, Messages, and others — until you disarm. They "
                + "still arrive; they just don't pop up. Turning on “Allow notifications when "
                + "mirroring or sharing the display” fixes it."
        case .unknown, .shown:
            alert.messageText = "Notifications may be hidden while replay is armed"
            alert.informativeText =
                "Arming Instant Replay captures your screen. Unless you've turned on “Allow "
                + "notifications when mirroring or sharing the display,” macOS then hides "
                + "notification banners from every app — Slack, Messages, and others — until you "
                + "disarm. They still arrive; they just don't pop up."
        }
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Notification Settings…")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { open() }
    }
}
