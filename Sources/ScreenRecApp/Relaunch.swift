import AppKit
import Foundation

/// Quits and reopens the app.
///
/// macOS won't honour a Screen Recording grant until the app fully restarts (02 §2), and
/// docs/06 promises the user we'll do that for them rather than making them find the app again
/// — the exact step a new user is most likely to abandon.
///
/// `open -n` is spawned *detached*, so it outlives this process: the child is what reopens us
/// after we're gone. `waitUntilExit` would deadlock (it would wait for a launcher that's
/// waiting for us to quit), so we deliberately don't.
enum Relaunch {

    /// The only irreversible thing in M4-T3. Callers must be certain nothing is recording:
    /// terminating mid-session would abandon a live writer, which ADR-007 forbids outright.
    static func now() {
        let bundleURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path]

        do {
            try process.run()
        } catch {
            // If the relaunch can't even start, quitting would strand the user with no app at
            // all. Staying put is the lesser failure: the permission is granted, and the window
            // still tells them to reopen ScreenRec themselves.
            NSLog("ScreenRec: relaunch failed (\(error.localizedDescription)) — staying open")
            return
        }
        NSApplication.shared.terminate(nil)
    }
}
