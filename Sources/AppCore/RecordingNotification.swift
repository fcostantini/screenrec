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

    /// One phrase per reachable `EndReason` (docs/06). Never the raw SCK string, never the word
    /// "error" — the user can't act on either.
    private static func cause(_ reason: EndReason) -> String {
        switch reason {
        case .displayDisconnected: "display disconnected"
        case .microphoneChanged: "microphone changed"
        case .diskAlmostFull: "disk almost full"
        case .streamError: "screen capture stopped unexpectedly"
        // Unreachable: SCK reports sleep, lock and unplug as one code (-3815 →
        // displayDisconnected). Mapped anyway so the switch stays total.
        case .systemSleep: "the Mac went to sleep"
        // Not a cause — `.userStopped` takes the manual-stop branch above.
        case .userStopped: "you stopped it"
        }
    }
}
