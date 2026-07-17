import Foundation
import RecorderCore

/// A notification the app posts (docs/06 "Notifications").
public struct RecordingNotification: Sendable, Equatable {
    public let title: String
    public let body: String
    /// The file to reveal on click; nil when there is nothing to reveal.
    public let fileURL: URL?
}

/// Turns engine events into notification copy.
///
/// Pure, so docs/06's copy rules are assertions rather than good intentions — and because
/// `UNUserNotificationCenter.current()` needs a real bundle, which `swift test` has none of.
public enum RecordingNotifications {

    /// Nil for events not worth interrupting the user over.
    ///
    /// `duration` is the finished file's length; the caller reads it before the session is torn
    /// down (`.finished` carries no duration of its own). `hadStarted` distinguishes the two
    /// things `.failed` means — see the `.failed` branch.
    public static func notification(
        for event: EngineEvent, duration: TimeInterval, hadStarted: Bool = false
    ) -> RecordingNotification? {
        switch event {
        case .finished(let url, .userStopped, _):
            return RecordingNotification(
                title: "Recording saved · \(MenuHeader.elapsed(duration))",
                body: url.lastPathComponent,
                fileURL: url)

        case .finished(let url, let reason, _):
            // ADR-007 in UI form: a fail-stop is a success with a cause, so the title is the
            // same "saved" as a manual stop and the cause rides in the body.
            return RecordingNotification(
                title: "Recording saved · \(MenuHeader.elapsed(duration))",
                body: "Ended: \(cause(reason)). File is playable.",
                fileURL: url)

        case .microphoneLost:
            // The one notification that isn't about an ending: recording continues (ADR-012).
            // Leads with that because the question it answers is "did my capture just die?".
            return RecordingNotification(
                title: "Still recording · microphone disconnected",
                body: "The rest of the recording has no microphone track.",
                fileURL: nil)

        case .recordingFileRestored:
            // Same not-an-ending family as microphoneLost: lead with "still recording".
            return RecordingNotification(
                title: "Still recording · file moved back",
                body: "The recording file was moved while recording, so it was moved back.",
                fileURL: nil)

        case .failed(let message):
            // `.failed` means two different things despite its doc comment saying only one:
            // a start that never got off the ground, and a finalize that threw after a full
            // recording (`RecordingSession` yields it from the `finish()` catch). Titling the
            // second "Couldn't start recording" would contradict its own body and tell someone
            // who just lost 90 minutes that nothing had started. Only the caller knows which.
            return RecordingNotification(
                title: hadStarted ? "Couldn't save the recording" : "Couldn't start recording",
                body: message, fileURL: nil)

        case .started, .paused, .resumed, .fileProgress, .stopped:
            return nil
        }
    }

    // MARK: - Replay (docs/06 notifications table, M5 rows)

    /// docs/06: `Replay saved` / `Replay … .mov — last 60 s. Click to reveal.` The count is the
    /// clip's real duration, so a save moments after arming says "last 10 s" honestly.
    public static func replaySaved(url: URL, duration: TimeInterval) -> RecordingNotification {
        RecordingNotification(
            title: "Replay saved",
            body: "\(url.lastPathComponent) — last \(Int(duration.rounded())) s. Click to reveal.",
            fileURL: url)
    }

    /// docs/06: the one place "Couldn't" is right — there is no playable file. The raw error
    /// goes to the log; the user gets the two realistic causes and their actions.
    public static func replaySaveFailed() -> RecordingNotification {
        RecordingNotification(
            title: "Couldn't save replay",
            body: "Check that the output folder is writable, or try again in a moment.",
            fileURL: nil)
    }

    /// The armed stream's mic died (docs/02 §4: it can never rebind to this stream). Amends
    /// docs/06's table, which predates armed replay. Mirrors the recording row's outcome-first
    /// shape: replay is still working, and the one remedy is named.
    /// Launch-at-login registration threw (M6-T5) — the toggle reverted, so point the user at
    /// where they can change it directly.
    public static func loginItemFailed() -> RecordingNotification {
        RecordingNotification(
            title: "Couldn't change launch at login",
            body: "Turn it on or off in System Settings › General › Login Items.",
            fileURL: nil)
    }

    /// register() landed in `.requiresApproval` — registered, but macOS won't launch it until the
    /// user re-enables it in System Settings (they turned it off there before).
    public static func loginItemNeedsApproval() -> RecordingNotification {
        RecordingNotification(
            title: "Approve launch at login",
            body: "Enable ScreenRec in System Settings › General › Login Items to finish turning it on.",
            fileURL: nil)
    }

    public static func recoveredRecording(url: URL) -> RecordingNotification {
        RecordingNotification(
            title: "Recovered an interrupted recording",
            body: "\(url.lastPathComponent) is ready to play.",
            fileURL: url)
    }

    public static func replayMicrophoneLost() -> RecordingNotification {
        RecordingNotification(
            title: "Replay still armed · microphone disconnected",
            body: "Replays saved from now on have no microphone. Re-arm to reconnect it.",
            fileURL: nil)
    }

    /// The armed pipeline itself died (encoder failure) — replay is off, not degraded, so this
    /// is a disarm notice, not a warning. Names the one recovery; the raw cause goes to the log.
    public static func replayStopped() -> RecordingNotification {
        RecordingNotification(
            title: "Instant replay turned off",
            body: "Screen encoding stopped. Re-arm from the menu to try again.",
            fileURL: nil)
    }

    /// The system refused the shortcut registration (another app owns the combo). Replay still
    /// works from the menu, so this is a heads-up, not a failure.
    public static func replayHotkeyUnavailable() -> RecordingNotification {
        RecordingNotification(
            title: "Replay shortcut unavailable",
            body: "Another app may be using that shortcut. Choose a different one in "
                + "ScreenRec Settings. Saving from the menu still works.",
            fileURL: nil)
    }

    /// One phrase per reachable `EndReason` (docs/06). Never the raw SCK string, never the word
    /// "error" — the user can't act on either.
    private static func cause(_ reason: EndReason) -> String {
        switch reason {
        case .displayDisconnected: "display disconnected"
        case .microphoneChanged: "microphone changed"
        case .diskAlmostFull: "disk almost full — free up space before recording again"
        case .streamError: "screen capture stopped unexpectedly"
        // Unreachable: SCK reports sleep, lock and unplug as one code (-3815 →
        // displayDisconnected). Mapped anyway so the switch stays total.
        case .systemSleep: "the Mac went to sleep"
        // Not a cause — `.userStopped` takes the manual-stop branch above.
        case .userStopped: "you stopped it"
        }
    }
}
