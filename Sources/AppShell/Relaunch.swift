import AppKit
import Foundation

/// Quits and reopens the app: macOS won't honour a Screen Recording grant until a full restart
/// (02 §2).
///
/// `open -n` is spawned detached so it outlives this process; `waitUntilExit` would deadlock.
@MainActor
enum Relaunch {

    /// Callers must be certain nothing is recording — terminating mid-session would abandon a
    /// live writer (ADR-007).
    static func now() {
        let bundleURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // The flag marks the copy as ours, so the single-instance guard lets it through — this and
        // the process that spawned it overlap until `terminate` below unwinds (LaunchPolicy).
        process.arguments = ["-n", bundleURL.path, "--args", LaunchPolicy.relaunchArgument]

        do {
            try process.run()
        } catch {
            // Quitting without a launcher would strand the user with no app; the window still
            // tells them to reopen ScreenRec themselves.
            NSLog("ScreenRec: relaunch failed (\(error.localizedDescription)) — staying open")
            return
        }
        NSApplication.shared.terminate(nil)
    }
}
