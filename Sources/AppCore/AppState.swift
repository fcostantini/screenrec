import CoreGraphics
import Foundation
import Observation
import RecorderCore

/// The menu-bar app's view state.
///
/// Drives a `RecordingSession` and consumes its `EngineEvent` stream, RecorderCore's single
/// event surface (docs/01). Adds no capture behaviour of its own (docs/06).
///
/// MainActor-isolated: every reader is a view, and events arrive already hopped off the capture
/// queues by `RecordingSession`.
@MainActor
@Observable
public final class AppState {

    // MARK: - What the status item shows

    public private(set) var statusIcon: StatusIcon = .idle

    // MARK: - Sources (docs/06 "Menu — idle state", items 5–7)

    public private(set) var displays: [DisplayOption] = []
    public private(set) var microphones: [AudioInputDevice] = []

    /// The user's picks, as the plain identifiers the menu selects by: RecorderCore's
    /// `DisplaySelection`/`MicrophoneSelection` carry associated values and aren't `Hashable`,
    /// so they can't be SwiftUI picker tags. `captureConfiguration` translates.
    public var selectedDisplayID: CGDirectDisplayID?      // nil ⇒ whatever is the main display
    public var selectedMicrophoneID: String?              // nil ⇒ record no microphone

    // Persisted (docs/06). The display and microphone picks deliberately are not: they name
    // hardware that may not be there next launch, and `refreshSources` already re-homes it.
    public var quality: QualityPreset { didSet { persist() } }
    /// docs/06 offers 30 or 60; `Settings.allowedFrameRateCaps` is the source of truth.
    public var frameRateCap: Int { didSet { persist() } }

    // MARK: - Header row

    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var recordedBytes: Int64 = 0

    /// Whether a recording could start right now (docs/06 item 1's header status, and what
    /// enables Start).
    ///
    /// Computed, not stored: SwiftUI builds menu rows before any `.task` on them runs, so a
    /// refreshed copy would always be one open behind. Both TCC queries are cheap.
    public var readiness: RecordingReadiness {
        // A grant this process hasn't restarted into is not readiness:
        // `CGPreflightScreenCaptureAccess()` flips true the moment the System Settings switch
        // lands, but the process keeps its launch-time TCC decision until a full restart
        // (02 §2). Only the launch snapshot can tell the difference.
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
    /// The relaunch decision keys on the transition (ungranted at launch → granted now), not on
    /// whether our button was pressed: a grant flipped directly in System Settings needs the
    /// same restart. Keying on the snapshot also avoids a relaunch loop when the app launched
    /// already-granted.
    public let screenWasGrantedAtLaunch: Bool

    /// The grant has landed but this process can't use it yet.
    public var needsRelaunchForScreenGrant: Bool {
        !screenWasGrantedAtLaunch && Permissions.screenRecordingState() == .granted
    }
    /// The microphone actually bound for this recording — not necessarily the one picked, since
    /// a vanished device falls back to the system default. SCK binds the mic once at
    /// `startCapture` and never re-resolves (02 §4), so this is fixed for the session.
    public private(set) var activeMicrophoneName: String?
    /// Set when a recording didn't survive its own start, or degraded on the way. ADR-007
    /// forbids the silent version of either.
    public private(set) var lastFailure: String?

    public private(set) var recentRecordings: [URL] = []

    // MARK: - Onboarding (docs/06 "Onboarding window")

    /// Whether the setup window has anything to say: first launch or any missing permission,
    /// never once satisfied (docs/06).
    public var needsOnboarding: Bool { readiness != .ready }

    /// Whether the screen-recording prompt has been fired this launch.
    ///
    /// This — not "were we denied" — flips the row to the System Settings route: preflight reads
    /// false for "never asked" and "declined" alike (02 §2), and after asking the remedy is the
    /// same either way. Latched for the launch; reverting to `Grant…` would restore a button
    /// that can no longer prompt.
    public private(set) var hasAskedForScreenRecording = false

    /// Notification authorization. Held rather than queried because, unlike TCC, reading it is
    /// async — and the live call needs a real bundle, so the app supplies it (see
    /// `setNotificationState`) and tests inject it.
    public private(set) var notificationState: PermissionState = .notDetermined

    /// The checklist. Stored and refreshed, unlike the computed `readiness`, because the window
    /// stays open while the user crosses to System Settings: TCC changes outside the process, so
    /// `@Observable` has nothing to observe and a computed value would never redraw. The window
    /// polls, and the poll writes here.
    public private(set) var onboardingRows: [OnboardingRow] = []

    /// Re-reads the permission states. Assigns only on a real change: `@Observable` publishes on
    /// every set, not every change, so an unconditional write would redraw the window once a
    /// second.
    public func refreshOnboarding() {
        let fresh = OnboardingModel.rows(
            screen: Permissions.screenRecordingState(),
            hasAskedForScreen: hasAskedForScreenRecording,
            microphone: Permissions.microphoneState(),
            microphoneRequired: selectedMicrophoneID != nil,
            notifications: notificationState)
        if fresh != onboardingRows { onboardingRows = fresh }
    }

    /// Fires the screen-recording prompt and latches that it has been asked. Returns whether the
    /// grant landed — it essentially never does on the spot: macOS makes the user cross to
    /// System Settings and restart the app (02 §2). The window polls for it instead.
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

    /// Where recordings go. Changing it re-reads the recent-files rows, which belong to the
    /// folder, not to the app.
    public var outputDirectory: URL {
        didSet {
            guard outputDirectory != oldValue else { return }
            outputLocation = OutputLocation(directory: outputDirectory)
            persist()
            refreshRecentRecordings()
        }
    }
    private var outputLocation: OutputLocation
    private var session: RecordingSession?
    private var currentOutputURL: URL?
    /// Captures `self` weakly and is awaited by `stopAndWaitForFinalize()`. Nothing cancels it in
    /// `deinit` (nonisolated, can't touch this) and nothing needs to: the loop exits when the
    /// session's stream finishes, which `RecordingSession` guarantees after `finished`/`failed`.
    private var consumeTask: Task<Void, Never>?

    /// Whether a session is in flight — the menu shows recording controls, the source pickers
    /// are hidden, and quitting has to confirm.
    ///
    /// Not derived from `statusIcon`: between `start()` and the first complete video frame the
    /// icon still reads `.idle` while a session exists. Keying off it would offer Start a second
    /// time in that window, and would let ⌘Q skip its confirmation.
    public var isSessionActive: Bool { session != nil }

    /// Drives the menu's Pause/Resume swap.
    public var isPaused: Bool { statusIcon == .paused }

    /// Posts a notification. Injected because AppCore may not import UserNotifications (docs/01)
    /// — and because `UNUserNotificationCenter.current()` needs a real bundle, which tests lack.
    public var notifier: (@MainActor (RecordingNotification) -> Void)?

    /// `defaults` is injected so the persistence round-trip is testable without touching the
    /// real user's preferences.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let settings = SettingsStore.load(from: defaults)
        outputDirectory = settings.outputDirectory
        outputLocation = OutputLocation(directory: settings.outputDirectory)
        quality = settings.quality
        frameRateCap = settings.frameRateCap
        screenWasGrantedAtLaunch = Permissions.screenRecordingState() == .granted
        refreshOnboarding()          // populated before the first render, or the window flickers
    }

    private let defaults: UserDefaults

    /// Writes the current settings. Called from the `didSet`s rather than by the views, so a
    /// preference cannot be changed without being saved.
    private func persist() {
        SettingsStore.save(
            Settings(
                outputDirectory: outputDirectory, quality: quality, frameRateCap: frameRateCap),
            to: defaults)
    }

    // MARK: - Menu refresh
    //
    // Pull, not push: docs/06 wants the menu current when it opens and silent when it's closed,
    // so the view calls these from its `.task` rather than the state keeping timers alive.

    /// Re-reads what the user can pick. Devices come and go; the pickers are locked during a
    /// recording because the answer must not change mid-session.
    ///
    /// Also re-homes the display selection: docs/06 wants one row per screen with a checkmark on
    /// the current one, so the selection must name a row that exists — covering first launch and
    /// the picked display going away.
    public func refreshSources(displays: [DisplayOption]) {
        self.displays = displays
        microphones = AudioInputs.available()

        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = (displays.first(where: \.isMain) ?? displays.first)?.id
        }
        // A microphone that has gone away drops to None: `start()` resolves a stale ID to the
        // system default, so the menu would otherwise show one device while another is recorded.
        if let picked = selectedMicrophoneID, !microphones.contains(where: { $0.uniqueID == picked }) {
            selectedMicrophoneID = nil
        }
    }

    public func refreshRecentRecordings() {
        recentRecordings = RecentRecordings.inDirectory(outputDirectory)
    }

    /// Re-reads the writer's duration and the file's size on disk.
    ///
    /// Polled, not pushed: `EngineEvent.fileProgress` is declared but nothing emits it. Suits
    /// docs/06 here anyway ("≤ 1 Hz, menu open only").
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
            frameRateCap: frameRateCap,
            quality: quality)
    }

    // MARK: - Actions (docs/06 "Menu — idle/recording state", items 2–3)

    public func start() async {
        // See `isSessionActive`: the menu is clickable again before the first frame lands.
        guard session == nil else { return }

        lastFailure = nil
        // The menu disables Start unless this holds; unreachable from the UI.
        guard readiness == .ready else { return }

        var configuration = captureConfiguration
        configuration.microphone = resolvedMicrophone()

        let outputURL: URL
        do {
            outputURL = try outputLocation.reserveRecordingURL(date: Date())
        } catch {
            // Through `apply`, not a bare assignment: these failures produce no session and so
            // no event stream, and `lastFailure` alone reaches no surface — Start looks
            // unchanged and the user walks away believing they are recording (ADR-007).
            apply(.failed(message: "Couldn't create a recording in "
                + "\"\(outputDirectory.lastPathComponent)\". Choose another folder."))
            return
        }

        let session: RecordingSession
        do {
            session = try RecordingSession(configuration: configuration, outputURL: outputURL)
        } catch {
            // The reservation is an O_EXCL placeholder the recorder would have consumed; with no
            // recorder, drop it rather than leave a 0-byte file and the name taken.
            try? FileManager.default.removeItem(at: outputURL)
            apply(.failed(message: "Couldn't set up the recorder: \(error.localizedDescription)"))
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
    /// awaiting the consume task is what keeps a live writer from being abandoned.
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
        notify(about: event)
        switch event {
        case .started, .resumed:
            statusIcon = .recording
        case .paused:
            statusIcon = .paused
        case .stopped, .finished:
            // Every ending is the same to the icon, including fail-stops (ADR-007 successes with
            // a cause). The cause reaches the user as a notification instead.
            statusIcon = .idle
        case .failed(let message):
            statusIcon = .idle
            lastFailure = message
        case .microphoneLost:
            // The one mid-recording problem that does not end the session (ADR-012): the mic
            // track ends, the recording continues, and the icon must keep saying so.
            lastFailure = "Microphone disconnected — still recording."
        case .fileProgress:
            break   // nothing emits this; `refreshProgress()` polls instead
        }
    }

    /// Posts the notification an event warrants, if any (docs/06).
    ///
    /// Runs before the fold, while `session` is still alive: `.finished` carries no duration, and
    /// the writer's own `recordedDuration` is the only accurate source for the title's clock —
    /// `elapsedSeconds` only advances while the menu is open, so it is usually stale or zero.
    private func notify(about event: EngineEvent) {
        let duration = session?.recordedDuration.seconds ?? 0
        guard let notification = RecordingNotifications.notification(
            for: event,
            duration: duration.isFinite ? duration : 0,
            // `.failed` covers both a start that never happened and a finalize that threw after
            // a full recording; the icon is the only thing that knows which.
            hadStarted: statusIcon != .idle) else { return }
        notifier?(notification)
    }

    private func endSession() {
        session = nil
        currentOutputURL = nil
        consumeTask = nil
        activeMicrophoneName = nil
        elapsedSeconds = 0
        recordedBytes = 0
        // `lastFailure` belongs to the session that raised it: left set, a transient notice would
        // outlive the recording it described and squat in the idle header, where docs/06 item 1
        // wants the readiness status. Start failures survive because they set this after the
        // session is already over.
        lastFailure = nil
        refreshRecentRecordings()      // the file that just finalized belongs at the top
    }

    // MARK: - Helpers

    /// SCK needs an explicit device ID or capture fails with an opaque "invalid parameter"
    /// (02 §1), so a picked microphone goes through the CLI's resolver: it rejects a stale ID and
    /// falls back to the system default.
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
            // worse outcome (ADR-012) — but never silently (ADR-007).
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
