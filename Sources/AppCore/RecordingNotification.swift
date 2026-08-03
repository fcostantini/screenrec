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
                title: "Recording saved · \(Timecode.clock(duration))",
                body: url.lastPathComponent,
                fileURL: url)

        case .finished(let url, let reason, _):
            // ADR-007 in UI form: a fail-stop is a success with a cause, so the title is the
            // same "saved" as a manual stop and the cause rides in the body.
            return RecordingNotification(
                title: "Recording saved · \(Timecode.clock(duration))",
                body: "Ended: \(cause(reason)). File is playable.",
                fileURL: url)

        case .microphoneLost:
            // Not an ending: recording continues (ADR-012). Leads with that because the
            // question it answers is "did my capture just die?".
            return RecordingNotification(
                title: "Still recording · microphone disconnected",
                body: "The recording has no microphone until it reconnects.",
                fileURL: nil)

        case .microphoneRecovered:
            // The rescue spliced the mic back in (M8-T2) — silence here would leave the user
            // believing the loss notice above still holds.
            return RecordingNotification(
                title: "Still recording · microphone reconnected",
                body: "The microphone track resumed.",
                fileURL: nil)

        case .microphoneSilent:
            // Connected, delivering, and carrying nothing (M16-T4). Same not-an-ending family as
            // the loss above; the body names the fix, since "muted" is the usual cause.
            return RecordingNotification(
                title: "Still recording · microphone is silent",
                body: "No sound has reached it for \(Int(MicrophoneSilence.duration)) "
                    + "seconds. Check that it isn't muted.",
                fileURL: nil)

        case .microphoneAudible:
            // Sound came back; without this the silence notice above stays the last word and the
            // user can't tell whether their fix worked.
            return RecordingNotification(
                title: "Still recording · microphone is picking up sound",
                body: "The microphone is working again.",
                fileURL: nil)

        case .microphoneDroppedAtStart:
            // A selected mic resolved but never delivered its first buffer in time (M13-T4), so the
            // take has no mic track. M9-T1's start notice only covers a mic that didn't resolve at
            // all; this closes the resolved-but-slow gap — a silent mic-less take (ADR-007).
            return RecordingNotification(
                title: "Recording started · no microphone",
                body: "The microphone didn't start in time, so this recording has no microphone track.",
                fileURL: nil)

        case .excludedAppUnavailable(let bundleID):
            // The app to leave out had nothing on screen, so SCK couldn't name it and the take
            // records everything — including whatever that app plays (M21-T4, measured). Saying so
            // is the whole point: the user asked for it to be absent.
            return RecordingNotification(
                title: "Recording started · nothing left out",
                body: "\(bundleID) has no window on screen, so it couldn't be excluded. "
                    + "Anything it plays will be in this recording.",
                fileURL: nil)

        case .silencedAppUnavailable(let bundleID):
            // The audio twin of the case above (M27-T2): no process object means the tap cannot
            // exclude it, and the exclusion is otherwise silently a no-op (docs/07).
            return RecordingNotification(
                title: "Recording started · nothing silenced",
                body: "\(bundleID) isn't playing any audio, so it couldn't be left out. "
                    + "Anything it plays will be in the recording.",
                fileURL: nil)

        case .audioTapSilent:
            return RecordingNotification(
                title: "Recording · no system audio",
                body: "Something is playing, but none of it is reaching the recording. "
                    + "The screen is still being recorded.",
                fileURL: nil)

        case .audioTapUnavailable:
            return RecordingNotification(
                title: "Recording started · nothing silenced",
                body: "Couldn't silence that app's audio, so the recording has the whole mix.",
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

        case .started, .paused, .resumed, .stopped, .discarded:
            // `.discarded` is silent: the confirmation alert was the acknowledgement.
            return nil
        }
    }

    /// A recording that wanted a microphone but resolved to none records screen-only (ADR-012);
    /// this says so at start, in the outcome-first voice, so a take set up and walked away from
    /// isn't silently mic-less — the mid-recording loss (`microphoneLost`) already notifies. Nil
    /// when the user chose None (an intentional no-mic) or a device did resolve.
    public static func recordingStart(
        microphonePreference: MicrophonePreference, resolvedMicName: String?
    ) -> RecordingNotification? {
        guard microphonePreference != .none, resolvedMicName == nil else { return nil }
        let body = microphonePreference == .automatic
            ? "No microphone is connected — recording screen only."
            : "The selected microphone isn't connected — recording screen only."
        return RecordingNotification(
            title: "Recording started · no microphone", body: body, fileURL: nil)
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

    // MARK: - Export (M10-T2, docs/06 notifications table)

    /// The share export finished — reveal it to send it on. Export runs from an idle menu (no
    /// active screen-share), so unlike the replay banner this isn't suppressed: it's the primary
    /// completion signal.
    public static func exported(url: URL) -> RecordingNotification {
        RecordingNotification(
            title: "Exported to MP4",
            body: "\(url.lastPathComponent) — ready to share. Click to reveal.",
            fileURL: url)
    }

    /// The transcode failed. The original recording is only read, so it's untouched; the raw
    /// error goes to the log and the user gets the one thing to check.
    public static func exportFailed() -> RecordingNotification {
        RecordingNotification(
            title: "Couldn't export to MP4",
            body: "The original recording is untouched. Try again, or check the output folder is writable.",
            fileURL: nil)
    }

    /// The export was refused before it started because it can't fit (M23-T2). Names the volume and
    /// both figures — the need and the have are what decide the next move; "check the output folder
    /// is writable" (the generic failure) would name the wrong thing entirely.
    public static func exportNoRoom(_ shortfall: ExportRoom.Shortfall) -> RecordingNotification {
        RecordingNotification(
            title: "Not enough room to export",
            body: "This needs about \(ApproximateBytes.formatted(shortfall.needBytes)) and "
                + "\(shortfall.volumeName) has \(ApproximateBytes.formatted(shortfall.freeBytes)) "
                + "free. The recording is untouched.",
            fileURL: nil)
    }

    /// Stop & Copy MP4 finished (M21-T2). The file is already on the pasteboard, so the next
    /// keystroke is the point; the click-to-reveal is the fallback for a clipboard since overwritten.
    public static func copiedToPasteboard(url: URL) -> RecordingNotification {
        RecordingNotification(
            title: "Copied — ⌘V to paste",
            body: "\(url.lastPathComponent) is on the clipboard. Click to reveal it.",
            fileURL: url)
    }

    /// The GIF (M10-T3) finished — reveal it to drop into a thread.
    public static func savedAsGIF(url: URL) -> RecordingNotification {
        RecordingNotification(
            title: "Saved as GIF",
            body: "\(url.lastPathComponent) — ready to share. Click to reveal.",
            fileURL: url)
    }

    public static func gifExportFailed() -> RecordingNotification {
        RecordingNotification(
            title: "Couldn't save GIF",
            body: "The original recording is untouched. Try again, or check the output folder is writable.",
            fileURL: nil)
    }

    /// A menu row outlived its file (M18-T4). The rows are stamped at menu open, so a file can be
    /// moved or trashed under them; without this the click is a silent no-op.
    public static func fileMissing(url: URL) -> RecordingNotification {
        RecordingNotification(
            title: "That file isn't there any more",
            body: "“\(url.lastPathComponent)” was moved or deleted. The list is up to date now.",
            fileURL: nil)
    }

    /// The lossless trim (M10-T4) finished — reveal the clipped copy.
    public static func trimmed(url: URL) -> RecordingNotification {
        RecordingNotification(
            title: "Trimmed",
            body: "\(url.lastPathComponent) — ready to share. Click to reveal.",
            fileURL: url)
    }

    public static func trimFailed() -> RecordingNotification {
        RecordingNotification(
            title: "Couldn't trim",
            body: "The original recording is untouched. Try again, or check the output folder is writable.",
            fileURL: nil)
    }

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

    /// The armed stream's mic died (docs/02 §4: it can never rebind to this stream). Amends
    /// docs/06's table, which predates armed replay. Mirrors the recording row's outcome-first
    /// shape: replay is still working, and the one remedy is named.
    public static func replayMicrophoneLost() -> RecordingNotification {
        RecordingNotification(
            title: "Replay still armed · microphone disconnected",
            body: "Replays saved while it's away have no microphone.",
            fileURL: nil)
    }

    /// The armed pipeline's mic came back via the rescue stream (M8-T2) — counterpart to the
    /// loss notice above.
    public static func replayMicrophoneReconnected() -> RecordingNotification {
        RecordingNotification(
            title: "Replay still armed · microphone reconnected",
            body: "Replays saved from now on include the microphone again.",
            fileURL: nil)
    }

    /// The armed pipeline's mic is connected but carrying nothing (M16-T4). Armed replay gets the
    /// pair too: a clip saved now would have a silent mic track, which is the failure this milestone
    /// exists to stop being discovered afterwards.
    public static func replayMicrophoneSilent() -> RecordingNotification {
        RecordingNotification(
            title: "Replay still armed · microphone is silent",
            body: "Replays saved now have no sound from it. Check that it isn't muted.",
            fileURL: nil)
    }

    public static func replayMicrophoneAudible() -> RecordingNotification {
        RecordingNotification(
            title: "Replay still armed · microphone is picking up sound",
            body: "Replays saved from now on include it again.",
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

    /// The system refused the start/stop shortcut (M9-T4). Starting from the menu still works.
    public static func recordHotkeyUnavailable() -> RecordingNotification {
        RecordingNotification(
            title: "Start/stop shortcut unavailable",
            body: "Another app may be using that shortcut. Choose a different one in "
                + "ScreenRec Settings. Starting from the menu still works.",
            fileURL: nil)
    }

    /// The system refused the pause/resume shortcut (M12-T6). Pausing from the menu still works.
    public static func pauseHotkeyUnavailable() -> RecordingNotification {
        RecordingNotification(
            title: "Pause/resume shortcut unavailable",
            body: "Another app may be using that shortcut. Choose a different one in "
                + "ScreenRec Settings. Pausing from the menu still works.",
            fileURL: nil)
    }

    /// The start/stop shortcut fired while the app can't record yet (M9-T4) — say so, never a
    /// silent no-op; the setup window names the missing permission.
    public static func recordingHotkeyBlocked() -> RecordingNotification {
        RecordingNotification(
            title: "Can't start recording",
            body: "ScreenRec needs permission first — open it to finish setup.",
            fileURL: nil)
    }

    /// The start/stop shortcut stopped a take it was set to copy, while another export held the
    /// one-at-a-time slot (M24-T2). The take is saved; only the copy was dropped, and the menu is
    /// where the second one is asked for.
    public static func stopCopySkipped() -> RecordingNotification {
        RecordingNotification(
            title: "Saved — the copy had to wait",
            body: "Another export was still running, so this take was saved without one. "
                + "Export it from the menu when that finishes.",
            fileURL: nil)
    }

    /// One phrase per reachable `EndReason` (docs/06). Never the raw SCK string, never the word
    /// "error" — the user can't act on either.
    private static func cause(_ reason: EndReason) -> String {
        switch reason {
        case .displayDisconnected: "display disconnected"
        case .appQuit: "the recorded app quit"
        case .windowClosed: "the recorded window closed"
        case .diskAlmostFull: "disk almost full — free up space before recording again"
        // No remedy named: the refusal could be a full, read-only or disconnected volume, and we
        // can't tell which. Inventing one would be worse than saying only what we know.
        case .writeFailed: "couldn't keep writing to disk"
        case .streamError: "screen capture stopped unexpectedly"
        // Not a cause — `.userStopped` takes the manual-stop branch above.
        case .userStopped: "you stopped it"
        }
    }
}
