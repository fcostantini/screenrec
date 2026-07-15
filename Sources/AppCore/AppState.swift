import CoreGraphics
import Foundation
import Observation
import RecorderCore

/// The menu-bar app's view state.
///
/// It drives a `RecordingSession` — the same seam the CLI's `record` has used since M2 — and
/// consumes its `EngineEvent` stream, RecorderCore's single event surface (docs/01). The app
/// adds no capture behaviour of its own (docs/06): every state here is either something a
/// session told us, or something the user picked from the menu.
///
/// MainActor-isolated because every reader is a view. Nothing on the sample path touches this:
/// events arrive already hopped off the capture queues by `RecordingSession`.
@MainActor
@Observable
public final class AppState {

    // MARK: - What the status item shows

    public private(set) var statusIcon: StatusIcon = .idle

    // MARK: - Sources (docs/06 "Menu — idle state", items 5–7)

    public private(set) var displays: [DisplayOption] = []
    public private(set) var microphones: [AudioInputDevice] = []

    /// The user's picks, held as the plain identifiers the menu selects by rather than as
    /// RecorderCore's `DisplaySelection`/`MicrophoneSelection`. Those carry associated values and
    /// aren't `Hashable`, so they can't be SwiftUI picker tags — and bending a capture type to
    /// suit a menu would be the wrong direction. `captureConfiguration` does the translation at
    /// the one moment it matters.
    public var selectedDisplayID: CGDirectDisplayID?      // nil ⇒ whatever is the main display
    public var selectedMicrophoneID: String?              // nil ⇒ record no microphone
    public var quality: QualityPreset = .balanced

    // MARK: - Header row

    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var recordedBytes: Int64 = 0

    /// Whether a recording could start right now (docs/06 item 1's header status, and what
    /// enables Start).
    ///
    /// Computed, not stored-and-refreshed. A stored copy is always a rebuild behind: SwiftUI
    /// builds the menu's rows *before* any `.task` on them runs, so a refresh from there lands
    /// after the enabled state has already been decided, and the menu shows the answer from the
    /// previous time it was opened. That's not theoretical — it shipped for an afternoon and the
    /// live run caught it: pick a microphone, and the menu went on offering an enabled Start
    /// that silently did nothing, because the readiness behind it still said the mic wasn't
    /// required. Both TCC queries are cheap local checks, so asking at build time is affordable
    /// and always current.
    public var readiness: RecordingReadiness {
        // A grant we haven't restarted into is NOT readiness. `CGPreflightScreenCaptureAccess()`
        // flips to true the moment the System Settings switch lands, but this process keeps the
        // TCC decision it launched with until it fully restarts (02 §2) — so believing preflight
        // here enables Start on an app whose every capture will fail. Only the launch-time
        // snapshot can tell the difference; permissions alone cannot.
        if needsRelaunchForScreenGrant {
            return .blocked(reason: "ScreenRec needs to reopen to finish turning on screen "
                + "recording. It will do that on its own in a moment.")
        }
        return Permissions.recordingReadiness(
            screen: Permissions.screenRecordingState(),
            microphone: Permissions.microphoneState(),
            microphoneRequired: selectedMicrophoneID != nil)
    }

    /// Whether screen recording was already granted when this process started.
    ///
    /// The relaunch decision keys on the *transition* (ungranted at launch → granted now), not
    /// on whether the user pressed our button: they can just as well flip the switch in System
    /// Settings without touching it, and that grant needs the same restart. Keying on the
    /// snapshot also stops the relaunch loop an app that launched already-granted would
    /// otherwise enter.
    public let screenWasGrantedAtLaunch: Bool

    /// The grant has landed but this process can't use it yet.
    public var needsRelaunchForScreenGrant: Bool {
        !screenWasGrantedAtLaunch && Permissions.screenRecordingState() == .granted
    }
    /// The microphone actually bound for this recording — not necessarily the one picked, since
    /// a vanished device falls back to the system default (docs/02 §4: SCK binds the mic once at
    /// `startCapture` and never re-resolves, so this is fixed for the session).
    public private(set) var activeMicrophoneName: String?
    /// Set when an attempt to record didn't survive its own start, or degraded on the way.
    /// ADR-007 forbids the silent version of either. M4-T5 turns these into notifications; until
    /// then the header row is the only place they can be said.
    public private(set) var lastFailure: String?

    public private(set) var recentRecordings: [URL] = []

    // MARK: - Onboarding (docs/06 "Onboarding window")

    /// Whether the setup window has anything to say. docs/06: it appears on first launch or any
    /// missing permission, and never once satisfied.
    public var needsOnboarding: Bool { readiness != .ready }

    /// Whether the screen-recording prompt has been fired this launch.
    ///
    /// This — not "were we denied" — is what flips the row to the System Settings route, because
    /// macOS won't tell us we were denied: preflight reads false for "never asked" and
    /// "declined" alike (02 §2). Having asked is the one thing we know for certain, and after it
    /// the remedy is the same either way. Latched for the launch: going back to `Grant…` would
    /// restore the dead button for the very users it exists to rescue.
    public private(set) var hasAskedForScreenRecording = false

    /// Notification authorization. Held rather than queried because, unlike TCC, reading it is
    /// async — and the live call needs a real bundle, so the app supplies it (see
    /// `setNotificationState`) and tests inject it.
    public private(set) var notificationState: PermissionState = .notDetermined

    /// The checklist. **Stored and refreshed, unlike `readiness` which is computed** — and the
    /// difference is not an inconsistency, it's the two surfaces needing opposite things:
    ///
    /// - The *menu* is rebuilt every time it opens, so computing live is what keeps it current;
    ///   a stored copy was a rebuild behind (that bug shipped, see `readiness`).
    /// - This *window stays open* while the user crosses to System Settings and back. Computing
    ///   live would keep the values right and still never redraw: TCC changes outside the
    ///   process, so `@Observable` has nothing to observe and SwiftUI never re-reads. That bug
    ///   shipped too — granting the microphone left the row sitting on `○ Grant…` forever.
    ///
    /// So the window polls, and the poll writes here.
    public private(set) var onboardingRows: [OnboardingRow] = []

    /// Re-reads the permission states. Assigns only on a real change: `@Observable` publishes on
    /// every set, not every change, so an unconditional write would redraw the window once a
    /// second for as long as it's open.
    public func refreshOnboarding() {
        let fresh = OnboardingModel.rows(
            screen: Permissions.screenRecordingState(),
            hasAskedForScreen: hasAskedForScreenRecording,
            microphone: Permissions.microphoneState(),
            microphoneRequired: selectedMicrophoneID != nil,
            notifications: notificationState)
        if fresh != onboardingRows { onboardingRows = fresh }
    }

    /// Fires the screen-recording prompt and latches that we've now asked. Returns whether the
    /// grant landed — it essentially never does on the spot, because macOS makes the user cross
    /// to System Settings and then restart the app (02 §2); the window polls for it instead.
    @discardableResult
    public func requestScreenRecording() -> Bool {
        hasAskedForScreenRecording = true
        let granted = Permissions.requestScreenRecording()
        refreshOnboarding()          // the row must switch to the System Settings route now
        return granted
    }

    public func requestMicrophoneAccess() async {
        _ = await Permissions.requestMicrophoneAccess()
        refreshOnboarding()
    }

    public func setNotificationState(_ state: PermissionState) {
        notificationState = state
        refreshOnboarding()
    }

    // MARK: - Session

    public let outputDirectory: URL
    private let outputLocation: OutputLocation
    private var session: RecordingSession?
    private var currentOutputURL: URL?
    /// Captures `self` weakly and is awaited by `stopAndWaitForFinalize()`. There is no `deinit`
    /// cancelling it — `deinit` is nonisolated and can't touch this — but nothing leaks: an
    /// AppState only dies with the app, and the loop exits on its own when the session's stream
    /// finishes (which `RecordingSession` guarantees after `finished`/`failed`).
    private var consumeTask: Task<Void, Never>?

    /// Whether a session is in flight — the menu shows recording controls, the source pickers
    /// are hidden, and quitting has to confirm.
    ///
    /// Deliberately *not* derived from `statusIcon`: between `start()` and the first complete
    /// video frame the icon still reads `.idle` (the engine hasn't emitted `.started` yet) while
    /// a session very much exists. Keying off the icon would offer "Start Recording" a second
    /// time in that window — building a second session over the first — and would let ⌘Q skip
    /// its confirmation and abandon a live writer.
    public var isSessionActive: Bool { session != nil }

    /// Drives the menu's Pause/Resume swap.
    public var isPaused: Bool { statusIcon == .paused }

    public init(outputLocation: OutputLocation = OutputLocation()) {
        self.outputLocation = outputLocation
        outputDirectory = outputLocation.directory
        screenWasGrantedAtLaunch = Permissions.screenRecordingState() == .granted
        refreshOnboarding()          // populated before the first render, or the window flickers
    }

    // MARK: - Menu refresh
    //
    // Pull, not push: docs/06 wants the menu current when it opens and silent when it's closed,
    // so the view calls these from its `.task` rather than the state keeping timers alive behind
    // a menu nobody is looking at.

    /// Re-reads what the user can pick. Devices come and go; the pickers are locked during a
    /// recording precisely because the answer must not change mid-session.
    ///
    /// Also re-homes the display selection. docs/06 wants a checkmark on the *current* display
    /// and one row per screen — no "main display" abstraction — so the selection has to name a
    /// row that exists. That covers first launch (nothing picked yet) and the display that was
    /// picked going away, which would otherwise leave the submenu with nothing checked and the
    /// engine resolving an ID that no longer exists.
    public func refreshSources(displays: [DisplayOption]) {
        self.displays = displays
        microphones = AudioInputs.available()

        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = (displays.first(where: \.isMain) ?? displays.first)?.id
        }
        // A microphone that has gone away drops to None rather than lingering as a checkmark on
        // a row that no longer exists. Silence would be worse than it looks: `start()` resolves
        // a stale ID to the *system default*, so the menu would show one device selected while a
        // different one was recorded.
        if let picked = selectedMicrophoneID, !microphones.contains(where: { $0.uniqueID == picked }) {
            selectedMicrophoneID = nil
        }
    }

    public func refreshRecentRecordings() {
        recentRecordings = RecentRecordings.inDirectory(outputDirectory)
    }

    /// Re-reads the writer's duration and the file's size on disk.
    ///
    /// Polled rather than pushed because `EngineEvent.fileProgress` is declared but nothing
    /// emits it — the CLI's own ticker polls `recordedDuration` the same way. That suits
    /// docs/06 here anyway ("≤ 1 Hz, menu open only"): a pull happens exactly when someone is
    /// looking, which no push could arrange.
    public func refreshProgress() {
        let duration = session?.recordedDuration.seconds ?? 0
        // NaN until the first frame starts the session (docs/02 §10).
        elapsedSeconds = duration.isFinite ? duration : 0
        recordedBytes = currentOutputURL.map(Self.fileSize) ?? 0
    }

    // MARK: - Configuration

    /// What the pickers currently describe. Pure, so the menu→capture translation is testable
    /// without starting anything.
    public var captureConfiguration: CaptureConfiguration {
        CaptureConfiguration(
            display: selectedDisplayID.map(DisplaySelection.id) ?? .main,
            microphone: selectedMicrophoneID.map { MicrophoneSelection.device(id: $0) } ?? .none,
            quality: quality)
    }

    // MARK: - Actions (docs/06 "Menu — idle/recording state", items 2–3)

    public func start() async {
        // See `isSessionActive`: the menu is clickable again before the first frame lands.
        guard session == nil else { return }

        lastFailure = nil
        // Belt and braces: the menu disables Start unless this holds, and `readiness` is live
        // rather than a stored copy, so this shouldn't be reachable from the UI.
        guard readiness == .ready else { return }

        var configuration = captureConfiguration
        configuration.microphone = resolvedMicrophone()

        let outputURL: URL
        do {
            outputURL = try outputLocation.reserveRecordingURL(date: Date())
        } catch {
            lastFailure = "Couldn't create a recording in "
                + "\"\(outputDirectory.lastPathComponent)\". Choose another folder."
            return
        }

        let session: RecordingSession
        do {
            session = try RecordingSession(configuration: configuration, outputURL: outputURL)
        } catch {
            // The reservation is an O_EXCL placeholder the recorder would have consumed; with no
            // recorder to consume it, drop it rather than leave a 0-byte file in the user's
            // folder and the name taken (M2-T5's field note; the CLI does the same).
            try? FileManager.default.removeItem(at: outputURL)
            lastFailure = "Couldn't set up the recorder: \(error.localizedDescription)"
            return
        }

        self.session = session
        currentOutputURL = outputURL
        elapsedSeconds = 0
        recordedBytes = 0

        let events = session.events
        consumeTask = Task { [weak self] in
            guard let self else { return }
            await consume(events)
            endSession()
        }
        await session.start()
    }

    /// Clean, user-initiated stop. The file finalizes and `finished` follows, which is what
    /// actually ends the session — see `endSession`.
    public func stop() async {
        await session?.stop()
    }

    public func pause() async {
        await session?.pause()
    }

    public func resume() async {
        await session?.resume()
    }

    /// Stops a recording and waits for the file to finalize. The app calls this before
    /// terminating: `RecordingSession` finishes its stream only once the writer is done, so
    /// awaiting the consume task is what makes "never abandon a writer" true rather than hoped.
    public func stopAndWaitForFinalize() async {
        guard let consumeTask else { return }
        await stop()
        await consumeTask.value
    }

    // MARK: - Event folding

    /// Drives the state off a `RecordingSession.events` stream until the session finishes.
    /// The stream terminates after `finished`/`failed`, which returns the icon to `.idle`.
    public func consume(_ events: AsyncStream<EngineEvent>) async {
        for await event in events { apply(event) }
    }

    /// Folds one engine event into the state. Internal: production always arrives via
    /// `consume(_:)`; only tests hand-feed events.
    func apply(_ event: EngineEvent) {
        switch event {
        case .started, .resumed:
            statusIcon = .recording
        case .paused:
            statusIcon = .paused
        case .stopped, .finished:
            // Every ending is the same to the icon — including the fail-stops, which are
            // ADR-007 successes with a cause. The cause reaches the user as a notification
            // (M4-T5); a distinct icon for it would be alarm with nothing to act on.
            statusIcon = .idle
        case .failed(let message):
            statusIcon = .idle
            lastFailure = message
        case .microphoneLost:
            // The one mid-recording problem that does not end the session (ADR-012): the mic
            // track ends, the recording continues, and so the icon must keep saying so.
            lastFailure = "Microphone disconnected — still recording."
        case .fileProgress:
            break   // nothing emits this; `refreshProgress()` polls instead
        }
    }

    private func endSession() {
        session = nil
        currentOutputURL = nil
        consumeTask = nil
        activeMicrophoneName = nil
        elapsedSeconds = 0
        recordedBytes = 0
        // `lastFailure` belongs to the session that raised it. Left set, a transient notice
        // ("Microphone disconnected — still recording") outlives the recording it described and
        // then squats in the idle header, where it is no longer true — and where docs/06 item 1
        // wants the readiness status instead. Start failures survive because nothing follows
        // them: they set this *after* the session is over.
        lastFailure = nil
        refreshRecentRecordings()      // the file that just finalized belongs at the top
    }

    // MARK: - Helpers

    /// SCK needs an explicit device ID or capture fails with an opaque "invalid parameter"
    /// (docs/02 §1), so a picked microphone goes through the same resolver the CLI uses — it
    /// rejects a stale ID (the device was unplugged since the menu was opened) and falls back to
    /// the system default.
    private func resolvedMicrophone() -> MicrophoneSelection {
        guard let picked = selectedMicrophoneID else {
            activeMicrophoneName = nil
            return .none
        }
        switch Permissions.resolvedMicrophoneID(preferred: picked) {
        case .explicit(let resolved):
            activeMicrophoneName = microphones.first { $0.uniqueID == resolved }?.name
            return .device(id: resolved)
        case .noDevice(let reason):
            // Record the screen anyway — losing a long capture over a missing microphone is the
            // worse outcome (ADR-012's reasoning) — but never silently (ADR-007).
            activeMicrophoneName = nil
            lastFailure = reason
            return .none
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }
}
