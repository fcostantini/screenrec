import CoreGraphics
import Foundation
import Observation
import RecorderCore

/// The recording in flight: what it is, how far it has got, and what its events mean (M22-T2).
/// Extracted from `AppState` along the `PermissionsModel`/`ExportModel` seam.
///
/// ⚠️ **The actions are deliberately not here.** `AppState.start()` reaches into the count-in,
/// permissions, the output location, the replay controller and the whole capture configuration;
/// moving that would relocate the tangle rather than cut it. This owns the *state* and the *fold* —
/// which is exactly what docs/03 asked for — and `AppState` hands it a started capture.
///
/// `lastFailure` stays on `AppState` (M22-T2 ruling A): a pre-flight failure has no session at all
/// (M17-T2), so a session-scoped home would be wrong in both directions. The fold reports through
/// `reportFailure`, and `AppState` keeps the policy of what outlives what.
@Observable
@MainActor
public final class SessionModel {

    // MARK: - What the surfaces read

    public private(set) var statusIcon: StatusIcon = .idle
    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var recordedBytes: Int64 = 0

    /// The live menu-bar clock's basis (M9-T3): nil when idle, set on `.started`, frozen on
    /// `.paused`, cleared on any ending. The label computes the ticking value from it locally.
    public private(set) var recordingClock: RecordingClock?

    /// The microphone actually bound for this recording — not necessarily the one picked, since
    /// a vanished device falls back to the system default. SCK binds the mic once at
    /// `startCapture` and never re-resolves (02 §4), so this is fixed for the session.
    public private(set) var activeMicrophoneName: String?
    /// The app being recorded, for the recording menu's "Recording <app> only" line (docs/06,
    /// M7-T2); nil for whole-screen. Named at start — the pick is locked for the session.
    public private(set) var activeAppName: String?
    /// The region being recorded, for the "Recording region <w>×<h>" line (docs/06, M11-T2); nil
    /// unless a region is the pick. Sized at start — the pick is locked for the session.
    public private(set) var activeRegion: CGSize?

    /// Whether a session is in flight — the menu shows recording controls, the source pickers
    /// are hidden, and quitting has to confirm.
    ///
    /// Not derived from `statusIcon`: between `start()` and the first complete video frame the
    /// icon still reads `.idle` while a session exists. Keying off it would offer Start a second
    /// time in that window, and would let ⌘Q skip its confirmation.
    public var isActive: Bool { capture != nil }

    /// Drives the menu's Pause/Resume swap.
    public var isPaused: Bool { statusIcon == .paused }

    // MARK: - The capture it is driving

    /// The live `RecordingSession`. Internal: `AppState`'s actions pause, stop and finalize it.
    private(set) var capture: RecordingSession?
    private(set) var currentOutputURL: URL?
    /// The file the last `.finished` carried, with its duration — read once the session has torn
    /// down, then cleared with the rest of it (M21-T3).
    private(set) var finishedRecording: (url: URL, duration: TimeInterval)?
    /// Captures `self` weakly and is awaited by `AppState.stopAndWaitForFinalize()`. Nothing
    /// cancels it in `deinit` (nonisolated, can't touch this) and nothing needs to: the loop exits
    /// when the session's stream finishes, which `RecordingSession` guarantees after
    /// `finished`/`failed`.
    var consumeTask: Task<Void, Never>?

    /// Posts a notification; wired to `AppState.notifier`, which the app injects (docs/01 keeps
    /// UserNotifications out of AppCore).
    var notifier: (@MainActor (RecordingNotification) -> Void)?

    /// Reports a failure message the menu should show, and whether it must survive the teardown
    /// that follows (a start failure must; a lost mic must not). `AppState` owns both the text and
    /// that policy — see the type doc.
    var reportFailure: (@MainActor (String?, _ outlivesSession: Bool) -> Void)?

    public init() {}

    // MARK: - Lifecycle

    /// Takes ownership of a started capture and the facts that are fixed for its lifetime.
    func attach(
        _ capture: RecordingSession, outputURL: URL,
        microphoneName: String?, appName: String?, region: CGSize?
    ) {
        self.capture = capture
        currentOutputURL = outputURL
        activeMicrophoneName = microphoneName
        activeAppName = appName
        activeRegion = region
    }

    /// Drops the finished capture and everything scoped to it. The rest of teardown — restarting
    /// an armed replay, cancelling the automatic stop, refreshing the recents — is `AppState`'s,
    /// because none of it is about this session's state.
    func clear() {
        capture = nil
        currentOutputURL = nil
        finishedRecording = nil
        consumeTask = nil
        activeMicrophoneName = nil
        activeAppName = nil
        activeRegion = nil
        elapsedSeconds = 0
        recordedBytes = 0
    }

    // MARK: - Event folding

    /// Drives the state off a `RecordingSession.events` stream until the session finishes.
    /// The stream terminates after `finished`/`failed`, which returns the icon to `.idle`.
    public func consume(_ events: AsyncStream<EngineEvent>) async {
        for await event in events { apply(event) }
    }

    /// Whether an ending leaves a file worth offering for naming (M21-T3) or Stop & Copy (M21-T2).
    /// Exhaustive on purpose: a new `EndReason` has to state its answer here rather than defaulting
    /// to "offer it", which is the shape of silence M23-T1 exists to close.
    private static func leavesAnActionableFile(_ reason: EndReason) -> Bool {
        switch reason {
        case .userStopped, .displayDisconnected, .appQuit, .windowClosed, .diskAlmostFull,
             .streamError:
            return true
        // Renaming or exporting onto the volume that just refused a write is the wrong next move,
        // and asking someone to name a take that died is the wrong moment (docs/06).
        case .writeFailed:
            return false
        }
    }

    /// Folds one engine event into the state. Internal: production always arrives via
    /// `consume(_:)`; only tests hand-feed events.
    func apply(_ event: EngineEvent) {
        notify(about: event)
        switch event {
        case .started:
            recordingClock = RecordingClock(accumulated: 0, runningSince: Date())
            statusIcon = .recording
        case .resumed:
            recordingClock?.runningSince = Date()   // resume the span; keep what was banked
            statusIcon = .recording
        case .paused:
            recordingClock?.bankAndFreeze(now: Date())
            statusIcon = .paused
        case .finished(let url, let reason, _):
            // What the take left behind, for the steps that run after teardown (M21-T3). A discard
            // never lands here, and neither does a start that produced no file. The length is the
            // last polled elapsed — it labels the take in the prompt, it isn't a measurement.
            if Self.leavesAnActionableFile(reason) { finishedRecording = (url, elapsedSeconds) }
            fallthrough
        case .stopped, .discarded:
            // Every ending is the same to the icon, including fail-stops (ADR-007 successes with
            // a cause) and discards. The cause, if any, reaches the user as a notification.
            recordingClock = nil
            statusIcon = .idle
        case .failed(let message):
            recordingClock = nil
            statusIcon = .idle
            reportFailure?(message, true)
        case .microphoneLost:
            // The one mid-recording problem that does not end the session (ADR-012): the
            // recording continues, and the icon must keep saying so. The rescue may clear it.
            reportFailure?("Microphone disconnected — still recording.", false)
        case .microphoneRecovered:
            // The rescue spliced the mic back (M8-T2); the loss notice would now be a lie.
            reportFailure?(nil, false)
        case .microphoneSilent:
            // Connected but carrying nothing (M16-T4). Same shape as a loss: the menu says so and
            // the recording continues.
            reportFailure?("Microphone is silent — still recording.", false)
        case .microphoneAudible:
            reportFailure?(nil, false)
        case .excludedAppUnavailable:
            // Degraded, not failed: the take runs, and the menu says what didn't happen. The
            // notification above carries the name; this row outlives nothing (M21-T4).
            reportFailure?("The app to leave out wasn't on screen — nothing was excluded.", false)
        case .microphoneDroppedAtStart:
            // The wanted mic never started (M13-T4); the recording continues without it. Say so in
            // the menu, or the active-mic-name row would name a mic that isn't in the take.
            reportFailure?("No microphone — it didn't start in time.", false)
        case .recordingFileRestored:
            break   // recording unaffected; the notification carries the news
        }
    }

    /// Posts the notification an event warrants, if any (docs/06).
    ///
    /// Runs before the fold, while `capture` is still alive: `.finished` carries no duration, and
    /// the writer's own `recordedDuration` is the only accurate source for the title's clock —
    /// `elapsedSeconds` only advances while the menu is open, so it is usually stale or zero.
    private func notify(about event: EngineEvent) {
        let duration = capture?.recordedDuration.seconds ?? 0
        guard let notification = RecordingNotifications.notification(
            for: event,
            duration: duration.isFinite ? duration : 0,
            // `hasStartedSession`, not the icon: the icon flips to `.recording` on the first
            // frame, before an unwritable-folder write failure surfaces (02 §2).
            hadStarted: capture?.hasStartedSession ?? false) else { return }
        notifier?(notification)
    }

    /// Re-reads the writer's duration and the file's size on disk.
    ///
    /// Polled, not pushed — no per-sample progress event (there was a dead `fileProgress` arm,
    /// retired M14-T3). Suits docs/06 here anyway ("≤ 1 Hz, menu open only").
    func refreshProgress() {
        let duration = capture?.recordedDuration.seconds ?? 0
        // NaN until the first frame starts the session (docs/02 §10).
        let seconds = duration.isFinite ? duration : 0
        let bytes = currentOutputURL.map(OutputLocation.currentFileSize(for:)) ?? 0
        // Assign only on real change: @Observable publishes on every set, and a publish
        // rebuilds the OPEN menu's AppKit rows — which garbles hover/highlight state.
        // Idle both values sit at zero, so the idle menu never rebuilds at all.
        if elapsedSeconds != seconds { elapsedSeconds = seconds }
        if recordedBytes != bytes { recordedBytes = bytes }
    }
}
