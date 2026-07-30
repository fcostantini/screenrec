import Foundation

/// Why a recording session ended. A non-`userStopped` reason on a `finished`/`stopped`
/// event is the fail-stop path (ADR-007): the session ended for a reason, not a crash.
public enum EndReason: Sendable, Equatable {
    case userStopped
    case displayDisconnected
    /// App-scoped capture only: the recorded app quit. SCK fires no stream error for this
    /// (measured, docs/02 §1a) — `AppTerminationWatch` detects it.
    case appQuit
    /// Window-scoped capture only: the recorded window went away — closed, or taken with its app
    /// when it quit. Unlike `.app`, SCK ends a window stream itself, so both routes arrive as the
    /// same stream error and report this one reason (measured, docs/02 §1c).
    case windowClosed
    case diskAlmostFull
    /// The `AVAssetWriter` refused a write mid-session and went `.failed` — the volume filled,
    /// went read-only, or went away. Everything flushed before that is on disk (fragmented, 02 §5),
    /// so this is a fail-stop with a playable file, not a loss.
    case writeFailed
    case streamError(String)
}

/// The one event surface RecorderCore exposes to callers (CLI, app AppState).
public enum EngineEvent: Sendable, Equatable {
    case started                                    // first complete video frame
    case paused
    case resumed
    /// A selected mic stopped delivering — the device went away (docs/02 §4). The one
    /// mid-recording problem that does not end the session: recording continues (ADR-012);
    /// the rescue stream may resume the track (M8-T2, `.microphoneRecovered`).
    case microphoneLost
    /// The rescue stream spliced the mic back in (M8-T2): the track/ring resumes after a
    /// silent gap over the loss window.
    case microphoneRecovered
    /// A selected mic is delivering buffers that contain nothing — muted, gain at zero, or an
    /// input with nothing on it (M16-T4). A notice, not an ending: recording continues.
    case microphoneSilent
    /// Sound reached a mic that had been reported silent.
    case microphoneAudible
    /// A selected mic resolved to a device but never delivered its first buffer within the
    /// recorder's start grace, so the recording has no mic track (M13-T4). Session-emitted (the
    /// recorder detects it), like `.discarded`; distinct from `.microphoneLost` (which had a track).
    case microphoneDroppedAtStart
    /// The app to leave out (M21-T4) had nothing on screen at start, so it could not be excluded:
    /// the recording runs, and everything it plays is in the file. Degraded, not failed (ADR-007).
    case excludedAppUnavailable(bundleID: String)
    /// The in-progress file was moved (Trash included) and the sentinel renamed it back;
    /// recording continues. Deletion is not an event — it fails the session.
    case recordingFileRestored
    case stopped(EndReason)                         // engine ran with no writer (e.g. engine-smoke)
    case finished(url: URL, reason: EndReason, droppedFrames: Int)  // file finalized, playable
    /// The user threw the take away mid-recording: the file is removed, nothing saved.
    /// Session-emitted (the engine never sends it), like `.finished`.
    case discarded
    case failed(message: String)                    // nothing playable exists (preflight/start failure)
}
