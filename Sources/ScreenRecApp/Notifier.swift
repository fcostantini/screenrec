import AppCore
import AppKit
import UserNotifications

/// Posts recording notifications and handles their clicks (docs/06 "Notifications").
///
/// The delegate must be set before launch completes: a click can *launch* the app, and a
/// notification delivered before there is a delegate is dropped — losing the one interaction
/// docs/06 specifies. Hence `NSApplicationDelegateAdaptor`, not a view's `.task`.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    /// Where the click handler finds the file to reveal.
    private static let fileURLKey = "fileURL"

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for authorization once, at launch, if it has never been asked.
    ///
    /// Onboarding's row can't be the only asker: it opens when a permission *blocks* recording,
    /// notifications never block, and it stops auto-opening the moment the blocking rows go
    /// green — so a normal install never sees it and every notification is dropped in silence.
    /// Declining is free (docs/06: optional, never gates anything), and the onboarding row still
    /// shows the state and routes to System Settings afterwards.
    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Delivers, or silently does nothing if the user declined notifications — they're optional
    /// and never gate anything (docs/06).
    @MainActor
    func post(_ notification: RecordingNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        // Time-sensitive, or banners never render for the app's own headline feature: macOS
        // suppresses ordinary banners whenever the display is captured, and replay saves fire
        // exactly then. Needs the matching entitlement (Scripts/entitlements.plist).
        content.interruptionLevel = .timeSensitive
        if let url = notification.fileURL {
            content.userInfo = [Self.fileURLKey: url.path]
        }
        // nil trigger = deliver now.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// docs/06: click always reveals the file in Finder.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let path = response.notification.request.content
            .userInfo[Self.fileURLKey] as? String else { return }
        Finder.reveal(URL(fileURLWithPath: path))
    }

    /// Show the banner even when ScreenRec is frontmost — otherwise the notification is silently
    /// swallowed whenever Settings or Onboarding happens to be open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    /// Prints the delivered list and exits — docs/03's verify hook, and the only way to assert
    /// real notification copy without a human watching the screen.
    ///
    /// Prints each notification's date because this is Notification Center's *persisted* list,
    /// not this run's: without a timestamp the gate passes just as happily on a week-old entry
    /// when nothing was delivered at all. Assert on the date, not merely on the copy.
    static func printDeliveredAndExit() -> Never {
        let done = DispatchSemaphore(value: 0)
        let stamp = ISO8601DateFormatter()
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            for note in delivered.sorted(by: { $0.date < $1.date }) {
                print("[\(stamp.string(from: note.date))] \(note.request.content.title)")
                print("  \(note.request.content.body)")
            }
            print("(\(delivered.count) delivered)")
            done.signal()
        }
        done.wait()
        exit(0)
    }
}
