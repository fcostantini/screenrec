import Foundation

/// Why a recording session ended. A non-`userStopped` reason on a `finished`/`stopped`
/// event is the fail-stop path (ADR-007): the session ended for a reason, not a crash.
public enum EndReason: Sendable, Equatable {
    case userStopped
    case displayDisconnected
    /// App-scoped capture only: the recorded app quit. SCK fires no stream error for this
    /// (measured, docs/02 §1a) — `AppTerminationWatch` detects it.
    case appQuit
    /// Unreachable: mic buffers arrive format-normalized (`ResampledMicInput`); kept declared
    /// to avoid a public-API ripple.
    case microphoneChanged
    case diskAlmostFull
    case systemSleep
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
    /// The in-progress file was moved (Trash included) and the sentinel renamed it back;
    /// recording continues. Deletion is not an event — it fails the session.
    case recordingFileRestored
    case fileProgress(seconds: Double, bytes: Int64)
    case stopped(EndReason)                         // engine ran with no writer (e.g. engine-smoke)
    case finished(url: URL, reason: EndReason, droppedFrames: Int)  // file finalized, playable
    /// The user threw the take away mid-recording: the file is removed, nothing saved.
    /// Session-emitted (the engine never sends it), like `.finished`.
    case discarded
    case failed(message: String)                    // nothing playable exists (preflight/start failure)
}
