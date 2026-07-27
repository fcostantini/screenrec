import CoreGraphics
import Foundation
import Observation
import RecorderCore
import os

/// One Hashable tag for the Source picker's two kinds of row (docs/06 item 5, M7-T2).
/// RecorderCore's `ContentSelection` carries non-Hashable siblings; `captureConfiguration`
/// translates.
public enum SourceChoice: Hashable, Sendable {
    case display(CGDirectDisplayID?)
    case app(bundleID: String)
    /// A rectangle of a display (M11-T2). `rect` is SCK `sourceRect` points (top-left, docs/02 §1b);
    /// `display` nil ⇒ main. Chosen via the overlay, not typed — the picker only shows/re-picks it.
    case region(display: CGDirectDisplayID?, rect: CGRect)
}

/// Which global shortcut a registration is for (M9-T4). The app maps each to a Carbon hotkey id and
/// the action it fires; AppState only names the intent.
public enum GlobalShortcut: Sendable, Equatable {
    case saveReplay
    case toggleRecording
    case togglePause
}

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

    private static let log = Logger(subsystem: "dev.fcostantini.screenrec", category: "app")

    // MARK: - What the status item shows

    public private(set) var statusIcon: StatusIcon = .idle

    // MARK: - Sources (docs/06 "Menu — idle state", items 5–7)

    public private(set) var displays: [DisplayOption] = []
    public private(set) var microphones: [AudioInputDevice] = []
    /// Running apps for the Source picker (docs/06 item 5, M7-T2). Fetched async by the view at
    /// menu open — `SCShareableContent` takes ~a second — through `refreshApps`.
    public private(set) var capturableApps: [CapturableApp] = []

    /// The user's picks, as the plain identifiers the menu selects by: RecorderCore's
    /// `DisplaySelection`/`MicrophoneSelection` carry associated values and aren't `Hashable`,
    /// so they can't be SwiftUI picker tags. `captureConfiguration` translates.
    public var selectedDisplayID: CGDirectDisplayID? {    // nil ⇒ whatever is the main display
        didSet {
            if selectedDisplayID != oldValue, !isRehomingSources { replayConfigurationChanged() }
        }
    }
    /// The Source pick when it's an app (docs/06 item 5, M7-T2); nil ⇒ entire screen. Persisted,
    /// and — like the mic pick — it survives the app not running: never re-homed by absence, and
    /// a start while the app is away fails loud (never a silent whole-screen fallback).
    public var selectedAppBundleID: String? {
        didSet {
            guard selectedAppBundleID != oldValue, !isRehomingSources else { return }
            persist()
            replayConfigurationChanged()
        }
    }
    /// The Source pick when it's a region (docs/06 item 5, M11-T2); nil ⇒ not a region. Set via the
    /// drag overlay through `setRegion`; persisted, and — like the app pick — it survives its display
    /// vanishing (a start then fails loud, never a silent whole-screen fallback).
    public var selectedRegion: RegionSelection? {
        didSet {
            guard selectedRegion != oldValue, !isRehomingSources else { return }
            persist()
            replayConfigurationChanged()
        }
    }
    /// The user's microphone pick: a specific device, `.automatic` (follow the system default at
    /// capture start, M6-T13), or `.none`. Persisted, and survives its device's absence — resolution
    /// happens at every stream start (device-if-present, else no mic; the default for `.automatic`).
    public var microphonePreference: MicrophonePreference {   // set once in init, then by the picker
        didSet {
            guard microphonePreference != oldValue, !isRehomingSources else { return }
            persist()
            replayConfigurationChanged()
        }
    }

    /// The specific device UID when one is picked; nil for `.none`/`.automatic` (both resolve at
    /// start). Lets `captureConfiguration` stay a plain translation.
    private var pickedMicrophoneID: String? {
        if case .device(let id) = microphonePreference { return id }
        return nil
    }

    /// True while `refreshSources` re-homes stale picks (housekeeping, not user intent) and
    /// while `sourceChoice` batches its two backing writes — either way, the suppressed didSets
    /// must not restart the armed stream: a rebuild wipes the replay buffer, and the batched
    /// case would otherwise rebuild twice, once against a config that exists for a microsecond.
    private var isRehomingSources = false

    // Persisted (docs/06). The display and microphone picks deliberately are not: they name
    // hardware that may not be there next launch, and `refreshSources` already re-homes it.
    public var quality: QualityPreset {
        didSet {
            persist()
            if quality != oldValue { replayConfigurationChanged() }
        }
    }
    /// docs/06 offers 30 or 60; `Settings.allowedFrameRateCaps` is the source of truth.
    public var frameRateCap: Int {
        didSet {
            persist()
            if frameRateCap != oldValue { replayConfigurationChanged() }
        }
    }

    /// Whether the menu-bar label shows the live elapsed clock while recording (M9-T3). A pure
    /// display pref — it touches nothing but the label — persisted, opt-out.
    public var showsMenuBarTimer: Bool {
        didSet { if showsMenuBarTimer != oldValue { persist() } }
    }

    /// The GIF export caps (M10-T3 follow-up), each a `Settings.allowedGif…` choice. Steer
    /// `Save as GIF`; a pure export pref, persisted.
    public var gifFPS: Int {
        didSet { if gifFPS != oldValue { persist() } }
    }
    public var gifWidth: Int {
        didSet { if gifWidth != oldValue { persist() } }
    }
    public var gifMaxSeconds: Int {
        didSet { if gifMaxSeconds != oldValue { persist() } }
    }

    // MARK: - Instant replay (docs/06 idle item 3, Settings "Instant Replay")

    /// Arming starts the rolling buffer (its own capture stream while idle; a recording's
    /// stream while one runs) and registers the hotkey. Persisted; restored at launch via
    /// `activateReplayIfArmed()` — never from `init`, which tests construct freely.
    public var isReplayArmed: Bool {
        didSet {
            guard isReplayArmed != oldValue else { return }
            // First arm ever (M12-T5): flag it seen now so persist() below stores it, but fire the
            // alert only AFTER arming — a modal here would defer capture until it was dismissed.
            let isFirstArm = isReplayArmed && !hasSeenReplayBannerWarning
            if isFirstArm { hasSeenReplayBannerWarning = true }
            persist()
            syncReplayArming()
            if isFirstArm { onReplayBannerWarning?() }
        }
    }

    /// Whether the one-time banner-suppression alert has been shown (M12-T5); persisted so it fires
    /// only on the very first arm ever. Seeded in `init`; `persist()` writes it.
    public private(set) var hasSeenReplayBannerWarning: Bool = false

    /// Shows the first-arm alert (M12-T5): the AppKit `NSAlert` is injected (banned in AppCore), nil
    /// in tests. Fired once ever, after which the dimmed menu row is the standing reminder.
    public var onReplayBannerWarning: (@MainActor () -> Void)?

    /// The rolling window, `Settings.replaySecondsRange` (5 s – 15 min, M9-T8). Changing it resizes
    /// the rings in place — the buffer survives: grow fills over time, shrink evicts the excess now.
    public var replaySeconds: Int {
        didSet {
            persist()
            if replaySeconds != oldValue, isReplayArmed {
                replay.windowChanged(seconds: Double(replaySeconds))
            }
        }
    }

    public var replayHotkey: Hotkey {
        didSet {
            persist()
            if isReplayArmed { registerReplayHotkey() }
        }
    }

    /// The optional global start/stop recording shortcut (M9-T4). Nil ⇒ off. Registered whenever
    /// set — not gated on arming, unlike the replay shortcut — and the handler checks readiness when
    /// it fires.
    public var recordHotkey: Hotkey? {
        didSet {
            guard recordHotkey != oldValue else { return }
            persist()
            registerRecordHotkey()
        }
    }

    /// The optional global pause/resume shortcut (M12-T6). Nil ⇒ off — opt-in like `recordHotkey`,
    /// since an always-live combo the user didn't choose could clash.
    public var pauseHotkey: Hotkey? {
        didSet {
            guard pauseHotkey != oldValue else { return }
            persist()
            registerPauseHotkey()
        }
    }

    /// Whether Start runs a 3-2-1 count-in first (M12-T6). Off by default. Persisted.
    public var countInEnabled: Bool = false {
        didSet {
            guard countInEnabled != oldValue else { return }
            persist()
        }
    }

    /// Runs the count-in overlay, calling the completion when it reaches zero (M12-T6). Injected by
    /// the app (AppKit is banned in AppCore); nil in tests. Guarded by `isCountingIn` against re-entry.
    public var runCountIn: (@MainActor (@escaping () -> Void) -> Void)?
    private var isCountingIn = false

    /// Registers/unregisters a global shortcut, reporting whether the system accepted it. Injected by
    /// the app (Carbon lives there, not in AppCore); a nil hotkey unregisters that shortcut.
    public var hotkeyRegistrar: (@MainActor (Hotkey?, GlobalShortcut) -> Bool)?

    /// Launch-at-login backing (docs/06). Injected by the app; nil in tests that don't exercise it.
    /// Set before `syncLaunchAtLogin()`.
    public var loginItem: (any LoginItemManaging)?

    /// The Settings toggle's state. The OS is the truth (`SMAppService` self-persists), so this is
    /// seeded from `loginItem` at launch and written back on a real user change. A failed write
    /// reverts to actual status rather than lying.
    public var launchAtLogin = false {
        didSet {
            guard !isSyncingLoginItem, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }
    private var isSyncingLoginItem = false

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem?.setEnabled(enabled)
            // register() can succeed into `.requiresApproval` (the user disabled it in System
            // Settings before); the toggle stays on, but they must re-enable it there.
            if enabled, loginItem?.needsApproval == true {
                notifier?(RecordingNotifications.loginItemNeedsApproval())
            }
        } catch {
            Self.log.error("login-item toggle failed: \(error.localizedDescription, privacy: .public)")
            notifier?(RecordingNotifications.loginItemFailed())
            // Revert on the next runloop, not synchronously: SwiftUI has already committed the
            // tapped state to the Toggle, and a same-tick revert can leave the switch visually
            // stuck on while the model reads off.
            Task { @MainActor [weak self] in
                guard let self else { return }
                isSyncingLoginItem = true
                launchAtLogin = loginItem?.isEnabled ?? false
                isSyncingLoginItem = false
            }
        }
    }

    private let replay: any ReplayControlling

    // MARK: - Header row

    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var recordedBytes: Int64 = 0

    /// The live menu-bar clock's basis (M9-T3): nil when idle, set on `.started`, frozen on
    /// `.paused`, cleared on any ending. The label computes the ticking value from it locally.
    public private(set) var recordingClock: RecordingClock?

    /// Permissions/onboarding, split out (M9-T7): AppState owns this sub-model and forwards to it.
    /// It needs one input, `microphoneRequired`, supplied from the mic pick; observation propagates
    /// through the nested `@Observable`, so views read `state.readiness`/`state.onboardingRows`/…
    /// unchanged.
    private let permissions = PermissionsModel()

    /// The one input the model needs: whether a mic is required (i.e. one is picked).
    private var microphoneRequired: Bool { microphonePreference != .none }

    /// Whether a recording could start right now (docs/06 item 1's header status, and what enables
    /// Start). Computed, not stored: SwiftUI builds menu rows before any `.task` runs, so a stored
    /// copy would lag one open (both TCC queries are cheap).
    public var readiness: RecordingReadiness {
        permissions.readiness(microphoneRequired: microphoneRequired)
    }

    public var screenWasGrantedAtLaunch: Bool { permissions.screenWasGrantedAtLaunch }
    public var needsRelaunchForScreenGrant: Bool { permissions.needsRelaunchForScreenGrant }

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
    /// Set when a recording didn't survive its own start, or degraded on the way. ADR-007
    /// forbids the silent version of either.
    public private(set) var lastFailure: String?

    public private(set) var recentRecordings: [URL] = []

    /// The Recent Exports group (M12-T2): the most-recent `.mp4`/`.gif` in the output directory, so
    /// derived share files have an in-menu home and inherit the file submenu. Refreshed with recents.
    public private(set) var recentExports: [URL] = []

    /// The last replay saved this armed session, for the menu's banner-independent confirmation
    /// (M9-T2): the "Replay saved" notification is suppressed while armed (docs/06). Cleared on
    /// disarm; updated on each save.
    public private(set) var lastReplay: LastReplay?

    /// A brief menu-bar confirmation the label shows on a save (M9-T3): visible without opening
    /// the menu, unlike `lastReplay`'s row. Set on save success, auto-cleared after `flashDuration`.
    public private(set) var replaySavedFlash = false
    private var flashTask: Task<Void, Never>?
    private static let flashDuration: Duration = .seconds(2)

    /// The export/trim cluster (M14-T1), the `PermissionsModel` pattern: AppState owns it and
    /// forwards the public surface below, so the view/CLI/test surface is unchanged. Its receipt
    /// persistence uses `defaults`; its notifications forward to `notifier` (both wired in `init`).
    /// `internal` (not `private`) so `ExportModelTests` can inject the export-function spies.
    let exports: ExportModel

    public var exportInProgress: String? { exports.exportInProgress }
    public var lastExport: LastExport? { exports.lastExport }
    public var trimTarget: URL? {
        get { exports.trimTarget }
        set { exports.trimTarget = newValue }
    }

    // MARK: - Onboarding (docs/06 "Onboarding window") — delegated to PermissionsModel (M9-T7)

    /// Whether the setup window has anything to say: first launch or any missing permission,
    /// never once satisfied (docs/06).
    public var needsOnboarding: Bool { readiness != .ready }
    public var hasAskedForScreenRecording: Bool { permissions.hasAskedForScreenRecording }
    public var notificationState: PermissionState { permissions.notificationState }
    public var onboardingRows: [OnboardingRow] { permissions.onboardingRows }

    public func refreshOnboarding() {
        permissions.refreshOnboarding(microphoneRequired: microphoneRequired)
    }

    @discardableResult
    public func requestScreenRecording() -> Bool {
        permissions.requestScreenRecording(microphoneRequired: microphoneRequired)
    }

    public func requestMicrophoneAccess() async {
        await permissions.requestMicrophoneAccess(microphoneRequired: microphoneRequired)
    }

    public func setNotificationState(_ state: PermissionState) {
        permissions.setNotificationState(state, microphoneRequired: microphoneRequired)
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
            // Replays follow recordings; only the muxer changes, the buffer survives.
            if isReplayArmed { replay.setOutputDirectory(outputDirectory) }
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
    /// real user's preferences; `replayController` so transition wiring is testable without
    /// live capture engines.
    public init(
        defaults: UserDefaults = .standard,
        replayController: (any ReplayControlling)? = nil
    ) {
        self.defaults = defaults
        let settings = SettingsStore.load(from: defaults)
        outputDirectory = settings.outputDirectory
        outputLocation = OutputLocation(directory: settings.outputDirectory)
        quality = settings.quality
        frameRateCap = settings.frameRateCap
        microphonePreference = settings.microphonePreference
        selectedAppBundleID = settings.captureAppBundleID
        selectedRegion = settings.captureRegion
        isReplayArmed = settings.replayArmed
        replaySeconds = settings.replaySeconds
        replayHotkey = settings.replayHotkey
        recordHotkey = settings.recordHotkey
        pauseHotkey = settings.pauseHotkey
        countInEnabled = settings.countInEnabled
        showsMenuBarTimer = settings.showsMenuBarTimer
        gifFPS = settings.gifFPS
        gifWidth = settings.gifWidth
        gifMaxSeconds = settings.gifMaxSeconds
        hasSeenReplayBannerWarning = settings.seenReplayBannerWarning
        // The export cluster (M14-T1): it seeds its own persisted receipt from `defaults`.
        exports = ExportModel(defaults: defaults)
        replay = replayController ?? ReplayController()
        // `screenWasGrantedAtLaunch` is captured by PermissionsModel's own init. Populate the rows
        // before the first render, or the window flickers.
        refreshOnboarding()

        // Export notifications forward to whatever `notifier` the app wires (M14-T1) — read at call
        // time, so it tracks the notifier set after init.
        exports.notify = { [weak self] in self?.notifier?($0) }

        replay.onMicrophoneLost = { [weak self] in
            self?.notifier?(RecordingNotifications.replayMicrophoneLost())
        }
        replay.onMicrophoneRecovered = { [weak self] in
            self?.notifier?(RecordingNotifications.replayMicrophoneReconnected())
        }
        replay.onPipelineFailure = { [weak self] message in
            guard let self else { return }
            // Mirror the controller's self-disarm in the persisted state. The didSet runs
            // (persist, unregister hotkey, call disarm) — disarm is a no-op on the already-dead
            // pipeline.
            isReplayArmed = false
            Self.log.error("replay pipeline failed: \(message, privacy: .public)")
            notifier?(RecordingNotifications.replayStopped())
        }
    }

    private let defaults: UserDefaults

    /// Writes the current settings. Called from the `didSet`s rather than by the views, so a
    /// preference cannot be changed without being saved.
    private func persist() {
        SettingsStore.save(
            Settings(
                outputDirectory: outputDirectory, quality: quality, frameRateCap: frameRateCap,
                microphonePreference: microphonePreference,
                captureAppBundleID: selectedAppBundleID,
                captureRegion: selectedRegion,
                replayArmed: isReplayArmed, replaySeconds: replaySeconds,
                replayHotkey: replayHotkey, recordHotkey: recordHotkey,
                pauseHotkey: pauseHotkey, countInEnabled: countInEnabled,
                showsMenuBarTimer: showsMenuBarTimer,
                gifFPS: gifFPS, gifWidth: gifWidth, gifMaxSeconds: gifMaxSeconds,
                seenReplayBannerWarning: hasSeenReplayBannerWarning),
            to: defaults)
    }

    // MARK: - Replay actions

    /// Starts the armed pipeline for a state restored from defaults. The app calls this once at
    /// launch; `init` never arms so tests can construct freely without spinning capture.
    ///
    /// A launch that can't capture stays armed-but-dormant: an ungranted stream would spin the
    /// controller's retry loop forever behind a lying badge. The grant → auto-relaunch flow
    /// lands here again with the permission usable.
    public func activateReplayIfArmed() {
        guard isReplayArmed,
              Permissions.screenRecordingState() == .granted,
              !needsRelaunchForScreenGrant else { return }
        syncReplayArming()
    }

    /// Seeds the toggle from the OS's actual login-item state (the truth), without the didSet
    /// re-registering. The app calls this once at launch after injecting `loginItem`.
    public func syncLaunchAtLogin() {
        isSyncingLoginItem = true
        launchAtLogin = loginItem?.isEnabled ?? false
        isSyncingLoginItem = false
    }

    /// Renames any orphaned `.partial` a crash left behind — already a playable fragmented
    /// movie (docs/04 §3.2), so recovery is a rename — and tells the user. The app calls this
    /// once at launch, before any recording can start; a live session's partial is no orphan.
    public func recoverInterruptedRecordings() {
        for url in outputLocation.recoverOrphanedPartials() {
            notifier?(RecordingNotifications.recoveredRecording(url: url))
        }
    }

    /// Saves the last `replaySeconds`. Fire-and-forget from the hotkey and the menu row; the
    /// outcome arrives as a notification (docs/06). A trigger while a save runs coalesces.
    public func saveReplay() {
        guard isReplayArmed else { return }
        replay.requestSave { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let saved):
                    // The in-app receipt (M9-T2): the notification below is banner-suppressed while
                    // armed, so the menu row is what actually reaches the user.
                    lastReplay = LastReplay(url: saved.url, seconds: Int(saved.duration.rounded()))
                    flashReplaySaved()             // and a signal without opening the menu (M9-T3)
                    notifier?(RecordingNotifications.replaySaved(url: saved.url, duration: saved.duration))
                    refreshRecentRecordings()      // the new clip belongs at the top
                case .failure(let error):
                    Self.log.error("replay save failed: \(error.localizedDescription, privacy: .public)")
                    notifier?(RecordingNotifications.replaySaveFailed())
                }
            }
        }
    }

    /// Shows the menu-bar save confirmation, then clears it after `flashDuration` (M9-T3). A new
    /// save restarts the window rather than stacking.
    private func flashReplaySaved() {
        replaySavedFlash = true
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.flashDuration)
            guard !Task.isCancelled else { return }
            self?.replaySavedFlash = false
        }
    }

    // Export/trim actions forward to `exports` (M14-T1). GIF is the one that carries state: AppState
    // owns the gif caps (persisted config), so it builds the `GifConfiguration` and passes it in.
    public func exportToMP4(_ source: URL) { exports.exportToMP4(source) }
    public func exportToGIF(_ source: URL) { exports.exportToGIF(source, configuration: gifConfiguration) }
    public func trim(_ source: URL, from start: Double, to end: Double) {
        exports.trim(source, from: start, to: end)
    }

    /// The `Save as GIF` caps as a `GifConfiguration` (M10-T3 follow-up), built from the persisted
    /// settings AppState owns. Pure, so the settings→config mapping is testable on its own.
    var gifConfiguration: GifConfiguration {
        GifConfiguration(maxWidth: gifWidth, maxHeight: gifWidth, fps: gifFPS, maxSeconds: Double(gifMaxSeconds))
    }

    private func syncReplayArming() {
        if isReplayArmed {
            if let session {
                // Resolved, not raw: an absent picked mic must not attach a ring the
                // recording's router will never feed (picked-device-or-nothing, 02 §1).
                replay.recordingStarted(
                    router: session.router, configuration: replayCaptureConfiguration(),
                    seconds: Double(replaySeconds), outputDirectory: outputDirectory)
            } else {
                replay.arm(
                    configuration: replayCaptureConfiguration(), seconds: Double(replaySeconds),
                    outputDirectory: outputDirectory)
            }
            registerReplayHotkey()
        } else {
            replay.disarm()
            lastReplay = nil          // the receipt belongs to the armed session that made it
            _ = hotkeyRegistrar?(nil, .saveReplay)
        }
    }

    private func replayConfigurationChanged() {
        guard isReplayArmed else { return }
        if let session {
            // Mid-recording only quality/fps can reach here (sources are locked, and the buffer
            // length takes `windowChanged` instead); rebuild on the recording's stream, with
            // the mic pick resolved the same way every replay path resolves it.
            replay.recordingStarted(
                router: session.router, configuration: replayCaptureConfiguration(),
                seconds: Double(replaySeconds), outputDirectory: outputDirectory)
        } else {
            replay.configurationChanged(
                configuration: replayCaptureConfiguration(), seconds: Double(replaySeconds),
                outputDirectory: outputDirectory)
        }
    }

    /// The configuration for replay's own stream: the current picks with the mic ID resolved
    /// the way `start()` resolves it (picked-device-or-nothing) — a stale ID fed raw to SCK
    /// fails with the opaque "invalid parameter" (02 §1), which would spin the armed retry
    /// loop forever.
    private func replayCaptureConfiguration() -> CaptureConfiguration {
        var configuration = captureConfiguration
        if microphonePreference != .none {          // else captureConfiguration already carries `.none`
            configuration.microphone = micSelection(microphoneResolution())
        }
        return configuration
    }

    /// A resolution as a capture selection — a resolved device, or nothing.
    private func micSelection(_ resolution: MicrophoneResolution) -> MicrophoneSelection {
        if case .explicit(let id) = resolution { return .device(id: id) }
        return .none
    }

    /// The concrete device for the current pick, shared by the recording and replay paths so they
    /// can never bind different mics: `.automatic` follows the system default, a specific pick is
    /// device-or-nothing. Callers special-case `.none` first (a chosen-no-mic isn't a miss). At
    /// capture start only — SCK binds the mic once (02 §4).
    private func microphoneResolution() -> MicrophoneResolution {
        switch microphonePreference {
        case .none: return .noDevice(reason: "no microphone chosen")
        case .automatic: return Permissions.resolvedMicrophoneID(preferred: nil, fallingBackToDefault: true)
        case .device(let id): return Permissions.resolvedMicrophoneID(preferred: id, fallingBackToDefault: false)
        }
    }

    /// Registers a shortcut and tells the user if the system refused it (combo taken by another
    /// app) — every UI surface advertises the combo, so a silent failure means a keypress that does
    /// nothing.
    private func registerReplayHotkey() {
        guard let hotkeyRegistrar else { return }
        if !hotkeyRegistrar(replayHotkey, .saveReplay) {
            notifier?(RecordingNotifications.replayHotkeyUnavailable())
        }
    }

    /// The app calls this once at launch — the start/stop shortcut isn't tied to arming, so it must
    /// register even before anything is armed; the didSet calls it on change.
    public func activateRecordHotkey() {
        registerRecordHotkey()
    }

    private func registerRecordHotkey() {
        guard let hotkeyRegistrar else { return }
        let accepted = hotkeyRegistrar(recordHotkey, .toggleRecording)   // nil ⇒ unregister ⇒ true
        if recordHotkey != nil, !accepted {
            notifier?(RecordingNotifications.recordHotkeyUnavailable())
        }
    }

    /// The app calls this once at launch (M12-T6): the pause shortcut isn't tied to a live recording —
    /// it registers up front and just does nothing until there's something to pause.
    public func activatePauseHotkey() {
        registerPauseHotkey()
    }

    private func registerPauseHotkey() {
        guard let hotkeyRegistrar else { return }
        let accepted = hotkeyRegistrar(pauseHotkey, .togglePause)   // nil ⇒ unregister ⇒ true
        if pauseHotkey != nil, !accepted {
            notifier?(RecordingNotifications.pauseHotkeyUnavailable())
        }
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
        isRehomingSources = true
        defer { isRehomingSources = false }
        // Assign only on real change: @Observable publishes on every set, and a publish rebuilds
        // the open menu's AppKit rows (garbling hover/highlight, M6-T10). Menu opens re-read
        // these, usually to the same values.
        if self.displays != displays { self.displays = displays }
        let microphones = AudioInputs.available()
        if self.microphones != microphones { self.microphones = microphones }

        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = (displays.first(where: \.isMain) ?? displays.first)?.id
        }
        // The microphone pick deliberately survives its device's absence: clearing it here
        // would forget the user's choice every time the AirPods sat in their case at menu-open.
        // The menu's picker binding shows None while the device is away
        // (`presentMicrophonePreference`), and stream starts resolve to the picked device or
        // nothing (Automatic follows the system default), so nothing lies.
    }

    /// Fetches and publishes the Source picker's app list; the view calls this at menu open.
    /// In-flight-guarded (a quick reopen must not stack ~1 s shareable-content fetches); a
    /// fetch failure keeps the last-known list rather than blanking an open picker.
    public func refreshCapturableApps() async {
        guard !isRefreshingApps else { return }
        isRefreshingApps = true
        defer { isRefreshingApps = false }
        guard let apps = try? await CapturableApps.available() else { return }
        refreshApps(apps)
    }
    private var isRefreshingApps = false

    /// Membership + publish, assign-on-change only (M6-T10). ScreenRec never lists itself —
    /// recording the recorder is noise; `recordableAppsFilter` applies the app layer's policy.
    /// `excluding` is injected so tests don't depend on the test runner's bundle identity.
    func refreshApps(
        _ apps: [CapturableApp], excluding ownBundleID: String? = Bundle.main.bundleIdentifier
    ) {
        var apps = apps.filter { $0.bundleID != ownBundleID }
        apps = recordableAppsFilter?(apps) ?? apps
        if capturableApps != apps { capturableApps = apps }
    }

    /// Which running apps belong in the Source picker, beyond self-exclusion. Injected by the
    /// app (the activation-policy read needs NSRunningApplication — AppKit); takes the whole
    /// list so the implementation can snapshot the process table once. Nil ⇒ no extra filter.
    public var recordableAppsFilter: (([CapturableApp]) -> [CapturableApp])?

    /// The picked app while it isn't in the live list: the menu shows it as a checkmarked
    /// "(not running)" row, so the pick stays visible without lying (the mic pattern's truth
    /// discipline, M7-T2).
    public var missingPickedApp: CapturableApp? {
        guard let bundleID = selectedAppBundleID,
              !capturableApps.contains(where: { $0.bundleID == bundleID }) else { return nil }
        return CapturableApp(bundleID: bundleID, name: appName(for: bundleID))
    }

    /// Resolves an installed app's display name from its bundle ID (works while it isn't
    /// running). Injected by the app — NSWorkspace is AppKit, banned here. Nil in tests.
    public var appDisplayName: ((String) -> String?)?

    /// Bundle ID → display name: the live list, then the installed-app resolver, then the ID
    /// itself — the one fallback chain, and it never returns an empty string.
    private func appName(for bundleID: String) -> String {
        capturableApps.first { $0.bundleID == bundleID }?.name
            ?? appDisplayName?(bundleID)
            ?? bundleID
    }

    /// What the menu's Microphone picker highlights: the pick, except a specific device that's
    /// currently away shows as `.none` (checkmark on None) — the truthful display of a pick whose
    /// device is in its case, without forgetting the pick. `.automatic` isn't a device, so it
    /// always shows itself.
    public var presentMicrophonePreference: MicrophonePreference {
        if case .device(let id) = microphonePreference,
           !microphones.contains(where: { $0.uniqueID == id }) {
            return .none
        }
        return microphonePreference
    }

    /// The current Source pick as menu text (M12-T3), so the submenu title tells the truth without
    /// being opened: `Region 1645×721`, an app's name, or the whole screen (named when there's a
    /// choice of display). Mirrors the checkmarked picker row.
    public var sourceMenuLabel: String {
        if let region = selectedRegion { return "Region \(Self.regionLabel(region.rect.size))" }
        if let bundleID = selectedAppBundleID { return appName(for: bundleID) }
        if displays.count > 1,
           let screen = displays.first(where: { $0.id == selectedDisplayID }) {
            return "Entire Screen (\(screen.name))"
        }
        return "Entire Screen"
    }

    /// The current Microphone pick as menu text (M12-T3): `None`, `Automatic`, or the device name —
    /// through `presentMicrophonePreference`, so an away device reads `None` (checkmark truth).
    public var microphoneMenuLabel: String {
        switch presentMicrophonePreference {
        case .none: return "None"
        case .automatic: return "Automatic"
        case .device(let id): return microphones.first(where: { $0.uniqueID == id })?.name ?? "None"
        }
    }

    /// What the armed rings would hold for a `seconds` window at the current sources and settings,
    /// or nil before the screen list arrives — a surface withholds the figure rather than guess.
    /// Takes the window as an argument so the Settings slider can quote its in-progress value.
    public func replayBufferBytes(seconds: Int) -> Int64? {
        guard let pixels = replayCapturePixelSize else { return nil }
        // `present…`, not the raw pick: an away device attaches no mic ring, so billing for one
        // would quote a buffer the armed stream isn't going to hold.
        return ReplayFootprint.estimatedBytes(
            width: pixels.width, height: pixels.height, frameRateCap: frameRateCap,
            seconds: Double(seconds), includesMicrophone: presentMicrophonePreference != .none)
    }

    /// docs/06: the Settings caption under the buffer slider. Both costs of arming, memory first —
    /// that's the one the slider changes.
    public func replayBufferCaption(seconds: Int) -> String {
        let awake = "While armed, ScreenRec keeps your Mac awake."
        guard let bytes = replayBufferBytes(seconds: seconds) else { return awake }
        return "A \(Self.bufferPhrase(seconds)) buffer holds about "
            + "\(ReplayFootprint.formatted(bytes)) in memory. \(awake)"
    }

    /// docs/06: the armed menu's dimmed cost row. Stamped at open, never ticking (M6-T10).
    public var replayBufferMenuLabel: String {
        guard let bytes = replayBufferBytes(seconds: replaySeconds) else {
            return "Mac stays awake while armed"
        }
        return "\(Self.shortBufferPhrase(replaySeconds)) buffer · "
            + "≈\(ReplayFootprint.formatted(bytes)) · Mac stays awake"
    }

    /// Pixels the armed stream encodes, mirroring `CaptureEngine`'s own resolution: a region's rect
    /// on its display; an app filter composites **on the main display** whatever display the pickers
    /// remember, and its frames stay display-sized (02 §1a); a whole-screen pick follows the
    /// selection. Nil when that display's geometry is unknown.
    private var replayCapturePixelSize: (width: Int, height: Int)? {
        let region = selectedRegion
        let displayID = region?.displayID ?? (selectedAppBundleID == nil ? selectedDisplayID : nil)
        guard let screen = displayOption(for: displayID),
              screen.pointPixelScale > 0, screen.pointSize != .zero else { return nil }
        return CaptureConfiguration.pixelDimensions(
            pointSize: region?.rect.size ?? screen.pointSize,
            pointPixelScale: screen.pointPixelScale)
    }

    /// A display id as its option; a nil id means the main display, matching the engine's `.main`.
    private func displayOption(for id: CGDirectDisplayID?) -> DisplayOption? {
        guard let id else { return displays.first(where: \.isMain) ?? displays.first }
        return displays.first { $0.id == id }
    }

    /// `45-second` / `1-minute` / `1:45` — whole minutes read better than `1:00`, and the slider's
    /// 15 s step makes the mixed case common enough to spell.
    static func bufferPhrase(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)-second" }
        if seconds % 60 == 0 { return "\(seconds / 60)-minute" }
        return clockPhrase(seconds)
    }

    /// The menu's tighter column: `45 s` / `1 min` / `1:45`.
    static func shortBufferPhrase(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return clockPhrase(seconds)
    }

    private static func clockPhrase(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    public func refreshRecentRecordings() {
        let recents = RecentRecordings.inDirectory(outputDirectory)
        if recentRecordings != recents { recentRecordings = recents }
        let exportFiles = RecentRecordings.inDirectory(
            outputDirectory, extensions: RecentRecordings.exportExtensions,
            limit: RecentRecordings.exportLimit)
        if recentExports != exportFiles { recentExports = exportFiles }
    }

    /// Drops a stale export receipt at menu open (M12-T3) — forwards to `exports` (M14-T1).
    public func expireStaleExportReceipt() { exports.expireStaleReceipt() }

    /// Renames a recording or export in place, extension intact (M12-T2). A blank/unchanged name is
    /// a no-op; a collision resolves like the exporters (` 2`). Re-points the receipt if it named
    /// this file. The source of a derived export is untouched — each acts on its own URL, no cascade.
    public func rename(_ url: URL, to newBaseName: String) {
        guard let preferred = RenameTarget.compute(for: url, newBaseName: newBaseName) else { return }
        // Try the requested name first: a case-only rename (`Clip` → `clip`) must land exactly, not
        // read as colliding with itself on a case-insensitive volume. Only a genuine collision — a
        // different file already at that name, which `moveItem` refuses to overwrite — falls to ` 2`.
        let target: URL
        if (try? FileManager.default.moveItem(at: url, to: preferred)) != nil {
            target = preferred
        } else {
            target = Exporter.availableURL(basedOn: preferred)
            do {
                try FileManager.default.moveItem(at: url, to: target)
            } catch {
                Self.log.error("rename failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        exports.renameReceipt(from: url, to: target)   // re-points the export receipt if it named this
        if let replay = lastReplay, replay.url.isSameFile(as: url) {
            lastReplay = LastReplay(url: target, seconds: replay.seconds)
        }
        refreshRecentRecordings()
    }

    /// Moves a recording or export to the Trash (M12-T2) — reversible, so no confirmation. Clears a
    /// receipt that named this file. A derived export's source is untouched (its own URL only).
    public func moveToTrash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            Self.log.error("move to trash failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        exports.clearReceipt(for: url)   // clears the export receipt if it named this
        if lastReplay?.url.isSameFile(as: url) == true { lastReplay = nil }
        refreshRecentRecordings()
    }

    /// Re-reads the writer's duration and the file's size on disk.
    ///
    /// Polled, not pushed — no per-sample progress event (there was a dead `fileProgress` arm, retired
    /// M14-T3). Suits docs/06 here anyway ("≤ 1 Hz, menu open only").
    public func refreshProgress() {
        let duration = session?.recordedDuration.seconds ?? 0
        // NaN until the first frame starts the session (docs/02 §10).
        let seconds = duration.isFinite ? duration : 0
        let bytes = currentOutputURL.map(OutputLocation.currentFileSize(for:)) ?? 0
        // Assign only on real change: @Observable publishes on every set, and a publish
        // rebuilds the OPEN menu's AppKit rows — which garbles hover/highlight state.
        // Idle both values sit at zero, so the idle menu never rebuilds at all.
        if elapsedSeconds != seconds { elapsedSeconds = seconds }
        if recordedBytes != bytes { recordedBytes = bytes }
    }

    // MARK: - Configuration

    /// What the pickers currently describe. Pure, so the menu→capture translation is testable
    /// without starting anything.
    public var captureConfiguration: CaptureConfiguration {
        let content: ContentSelection
        if let region = selectedRegion {
            content = .region(display: region.displayID.map(DisplaySelection.id) ?? .main, rect: region.rect)
        } else if let bundleID = selectedAppBundleID {
            content = .app(bundleID: bundleID)
        } else {
            content = .display(selectedDisplayID.map(DisplaySelection.id) ?? .main)
        }
        return CaptureConfiguration(
            content: content,
            microphone: pickedMicrophoneID.map { MicrophoneSelection.device(id: $0) } ?? .none,
            // Honor the pick (M8-T2): a specific device recovers only onto itself; Automatic
            // follows the current system default at return time.
            microphoneRecovery: microphonePreference == .automatic ? .systemDefault : .sameDevice,
            frameRateCap: frameRateCap,
            quality: quality)
    }

    /// The Source picker's one Hashable selection over its row kinds (docs/06 item 5, M7-T2/M11-T2).
    /// Writing one kind clears the others; the remembered display survives an app/region detour.
    /// The backing writes are batched (`isRehomingSources`) into ONE persist + rebuild.
    public var sourceChoice: SourceChoice {
        get {
            if let region = selectedRegion { return .region(display: region.displayID, rect: region.rect) }
            return selectedAppBundleID.map { .app(bundleID: $0) } ?? .display(selectedDisplayID)
        }
        set {
            guard newValue != sourceChoice else { return }
            isRehomingSources = true
            switch newValue {
            case .display(let id):
                selectedAppBundleID = nil
                selectedRegion = nil
                selectedDisplayID = id
            case .app(let bundleID):
                selectedAppBundleID = bundleID
                selectedRegion = nil
            case .region(let displayID, let rect):
                selectedAppBundleID = nil
                selectedRegion = RegionSelection(displayID: displayID, rect: rect)
            }
            isRehomingSources = false
            persist()
            replayConfigurationChanged()
        }
    }

    /// Sets a drawn region as the Source (M11-T2) — the overlay's one entry point. Goes through
    /// `sourceChoice` so it inherits the batched persist + single armed-stream rebuild.
    public func setRegion(displayID: CGDirectDisplayID?, rect: CGRect) {
        sourceChoice = .region(display: displayID, rect: rect)
    }

    /// Opens the drag-to-select overlay (M11-T2). Injected by the app — the overlay is AppKit,
    /// banned in AppCore; nil in tests. The menu's "Select Region…" calls this. `@MainActor`-typed
    /// like the other injections (it drives AppKit and `setRegion`).
    public var beginRegionSelection: (@MainActor () -> Void)?

    /// "<w>×<h>" for a region's size in points, e.g. the picker's `Region 820×512` row. The
    /// engine snaps to even pixels at capture (M11-T1); the menu shows the chosen point size.
    public static func regionLabel(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))×\(Int(size.height.rounded()))"
    }

    // MARK: - Actions (docs/06 "Menu — idle/recording state", items 2–3)

    public func start() async {
        // See `isSessionActive`: the menu is clickable again before the first frame lands.
        guard session == nil, !isCountingIn else { return }

        lastFailure = nil
        // The menu disables Start unless this holds; unreachable from the UI.
        guard readiness == .ready else { return }

        // Optional 3-2-1 count-in (M12-T6): show the overlay, then begin capture when it reaches
        // zero — the countdown itself isn't recorded. `isCountingIn` blocks a second Start during it.
        if countInEnabled, let runCountIn {
            isCountingIn = true
            runCountIn { [weak self] in
                Task { @MainActor in
                    self?.isCountingIn = false
                    await self?.beginCapture()
                }
            }
            return
        }
        await beginCapture()
    }

    /// The actual capture start, after any count-in. Split from `start()` so the count-in can defer it.
    private func beginCapture() async {
        guard session == nil else { return }

        var configuration = captureConfiguration
        configuration.microphone = resolvedMicrophone()
        activeAppName = selectedAppBundleID.map(appName(for:))
        activeRegion = selectedRegion?.rect.size

        let outputURL: URL
        do {
            outputURL = try outputLocation.reserveRecordingURL(date: Date())
        } catch {
            // Through `apply`, not a bare assignment: these failures produce no session and so
            // no event stream, and `lastFailure` alone reaches no surface — Start looks
            // unchanged and the user walks away believing they are recording (ADR-007).
            // `OutputLocation`'s own errors name the specific cause (missing/unwritable/interrupted
            // file); surface it rather than flattening to a generic line.
            let message = (error as? OutputLocation.ReservationError)?.errorDescription
                ?? "Couldn't create a recording in \"\(outputDirectory.lastPathComponent)\". "
                    + "Choose another folder."
            apply(.failed(message: message))
            return
        }

        let session: RecordingSession
        do {
            session = try RecordingSession(configuration: configuration, outputURL: outputURL)
        } catch {
            // The reservation is an O_EXCL placeholder at the `.partial` companion; with no
            // recorder, drop it rather than leave a 0-byte file and the name taken.
            try? FileManager.default.removeItem(at: OutputLocation.partialURL(for: outputURL))
            Self.log.error("recorder setup failed: \(error.localizedDescription, privacy: .public)")
            apply(.failed(message: "Couldn't start recording. Try a different output folder, "
                + "or restart ScreenRec if it keeps happening."))
            return
        }

        self.session = session
        currentOutputURL = outputURL
        elapsedSeconds = 0
        recordedBytes = 0

        // `activeMicrophoneName` is what `resolvedMicrophone()` above just resolved to; posting
        // here, after the session commits, keeps a failed start from claiming it began.
        if let notice = RecordingNotifications.recordingStart(
            microphonePreference: microphonePreference, resolvedMicName: activeMicrophoneName) {
            notifier?(notice)
        }

        // Armed replay rides the recording's stream from here (docs/01's key property; the
        // buffer restarts — a new stream is a new pts epoch).
        if isReplayArmed {
            replay.recordingStarted(
                router: session.router, configuration: configuration,
                seconds: Double(replaySeconds), outputDirectory: outputDirectory)
        }

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

    /// Throw the current take away: the file is removed and the session ends at `.discarded`,
    /// which — like every ending — returns to idle via `endSession`.
    public func discard() async {
        await session?.discard()
    }

    public func pause() async {
        await session?.pause()
    }

    public func resume() async {
        await session?.resume()
    }

    /// What the global start/stop shortcut does (M9-T4): a session in flight — recording or paused —
    /// stops and saves; otherwise a ready app starts, and a blocked one says why. Never a silent
    /// no-op — the shortcut advertised an action.
    public func toggleRecording() async {
        switch Self.recordToggleAction(isSessionActive: isSessionActive, isReady: readiness == .ready) {
        case .start: await start()
        case .stop: await stop()
        case .blockedNotify: notifier?(RecordingNotifications.recordingHotkeyBlocked())
        }
    }

    enum RecordToggleAction: Equatable { case start, stop, blockedNotify }

    /// Pure so the three branches are unit-tested without live capture (which `start`/`stop` need).
    static func recordToggleAction(isSessionActive: Bool, isReady: Bool) -> RecordToggleAction {
        if isSessionActive { return .stop }   // a paused session is still active — stop wins
        return isReady ? .start : .blockedNotify
    }

    /// What the global pause/resume shortcut does (M12-T6): a live recording pauses, a paused one
    /// resumes, and with nothing recording it does nothing (a silent no-op, not a failure).
    public func togglePause() async {
        switch Self.pauseToggleAction(isSessionActive: isSessionActive, isPaused: isPaused) {
        case .pause: await pause()
        case .resume: await resume()
        case .ignore: break
        }
    }

    enum PauseToggleAction: Equatable { case pause, resume, ignore }

    /// Pure so the three branches are unit-tested without live capture (which `pause`/`resume` need).
    static func pauseToggleAction(isSessionActive: Bool, isPaused: Bool) -> PauseToggleAction {
        guard isSessionActive else { return .ignore }   // nothing to pause
        return isPaused ? .resume : .pause
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
        case .started:
            recordingClock = RecordingClock(accumulated: 0, runningSince: Date())
            statusIcon = .recording
        case .resumed:
            recordingClock?.runningSince = Date()   // resume the span; keep what was banked
            statusIcon = .recording
        case .paused:
            recordingClock?.bankAndFreeze(now: Date())
            statusIcon = .paused
        case .stopped, .finished, .discarded:
            // Every ending is the same to the icon, including fail-stops (ADR-007 successes with
            // a cause) and discards. The cause, if any, reaches the user as a notification.
            recordingClock = nil
            statusIcon = .idle
        case .failed(let message):
            recordingClock = nil
            statusIcon = .idle
            lastFailure = message
        case .microphoneLost:
            // The one mid-recording problem that does not end the session (ADR-012): the
            // recording continues, and the icon must keep saying so. The rescue may clear it.
            lastFailure = "Microphone disconnected — still recording."
        case .microphoneRecovered:
            // The rescue spliced the mic back (M8-T2); the loss notice would now be a lie.
            lastFailure = nil
        case .microphoneDroppedAtStart:
            // The wanted mic never started (M13-T4); the recording continues without it. Say so in
            // the menu, or the active-mic-name row would name a mic that isn't in the take.
            lastFailure = "No microphone — it didn't start in time."
        case .recordingFileRestored:
            break   // recording unaffected; the notification carries the news
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
            // `hasStartedSession`, not the icon: the icon flips to `.recording` on the first
            // frame, before an unwritable-folder write failure surfaces (02 §2).
            hadStarted: session?.hasStartedSession ?? false) else { return }
        notifier?(notification)
    }

    private func endSession() {
        session = nil
        currentOutputURL = nil
        consumeTask = nil
        // The recording's stream is going away; an armed replay resumes on a private one.
        if isReplayArmed {
            replay.recordingEnded(
                configuration: replayCaptureConfiguration(), seconds: Double(replaySeconds),
                outputDirectory: outputDirectory)
        }
        activeMicrophoneName = nil
        activeAppName = nil
        activeRegion = nil
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

    /// Resolves the pick to a device (or none) for a recording, and names it for the menu — SCK
    /// needs an explicit device ID or capture fails with an opaque "invalid parameter" (02 §1).
    /// Shares `microphoneResolution()` with the replay path so the two never bind different mics.
    private func resolvedMicrophone() -> MicrophoneSelection {
        guard microphonePreference != .none else {
            activeMicrophoneName = nil
            return .none
        }
        switch microphoneResolution() {
        case .explicit(let resolved):
            activeMicrophoneName = AudioInputs.available().first { $0.uniqueID == resolved }?.name
            return .device(id: resolved)
        case .noDevice:
            // Record the screen anyway — losing a capture over a missing microphone is the worse
            // outcome (ADR-012) — but never silently (ADR-007).
            activeMicrophoneName = nil
            lastFailure = microphonePreference == .automatic
                ? "No microphone connected — recording without one."
                : "The selected microphone isn't connected — recording without it."
            return .none
        }
    }

}
