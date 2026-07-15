import Foundation

/// Why a recording session ended. A non-`userStopped` reason on a `finished`/`stopped`
/// event is the fail-stop path (ADR-007): the session ended for a reason, not a crash.
public enum EndReason: Sendable, Equatable {
    case userStopped
    case displayDisconnected
    case microphoneChanged
    case diskAlmostFull
    case systemSleep
    case streamError(String)
}

/// The one event surface RecorderCore exposes to callers (CLI, app AppState). Extend
/// here — never fork — since M1/M3/M4 and the docs/06 notification copy all consume it.
public enum EngineEvent: Sendable, Equatable {
    case started                                    // first complete video frame
    case paused
    case resumed
    /// A selected mic stopped delivering — the device went away (docs/02 §4). The one
    /// mid-recording problem that does NOT end the session: recording continues and the mic
    /// track simply ends here (ADR-012). A notification, not a termination.
    case microphoneLost
    case fileProgress(seconds: Double, bytes: Int64)
    case stopped(EndReason)                         // engine ran with no writer (e.g. engine-smoke)
    case finished(url: URL, reason: EndReason, droppedFrames: Int)  // file finalized, playable
    case failed(message: String)                    // nothing playable exists (preflight/start failure)
}
