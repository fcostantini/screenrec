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
    /// The whole screen minus one app (M21-T4): it is neither seen nor heard. The display stays
    /// whatever `sources.selectedDisplayID` says — this is a whole-screen pick with a hole in it.
    case displayExcluding(bundleID: String)
    /// A rectangle of a display (M11-T2). `rect` is SCK `sourceRect` points (top-left, docs/02 §1b);
    /// `display` nil ⇒ main. Chosen via the overlay, not typed — the picker only shows/re-picks it.
    case region(display: CGDirectDisplayID?, rect: CGRect)
    /// One window (M17-T2). Carries the whole selection, not just the id, so the tag of a picked
    /// window that has since gone still round-trips through the picker.
    case window(WindowSelection)
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

    // MARK: - Sources (docs/06 "Menu — idle state", items 5–7)

    /// What can be captured and what is picked (M22-T1). The properties below forward to it, so
    /// every existing caller — menu, Settings, tests — keeps naming `state.selectedWindow` and
    /// friends.
    public let sources = SourcesModel()

    public private(set) var microphones: [AudioInputDevice] = []


    /// The excluded app's name for the menu's honesty row (M21-T4), or nil when nothing is excluded.
    public var excludedAppName: String? { sources.excludedAppBundleID.map(sources.appName(for:)) }
    /// The excluded pick when it isn't on screen to be excluded — the row says so, and the start
    /// will too (M21-T4).
    public func refreshCapturableApps() async { await sources.refreshCapturableApps() }
    public func refreshCapturableWindows() async { await sources.refreshCapturableWindows() }
    public func setRegion(displayID: CGDirectDisplayID?, rect: CGRect) {
        sources.setRegion(displayID: displayID, rect: rect)
    }
    func refreshApps(_ apps: [CapturableApp], excluding own: String? = Bundle.main.bundleIdentifier) {
        sources.refreshApps(apps, excluding: own)
    }
    func refreshWindows(
        _ windows: [CapturableWindow], excluding own: String? = Bundle.main.bundleIdentifier
    ) {
        sources.refreshWindows(windows, excluding: own)
    }

    /// Publishes the screen list and re-reads the microphones; the view calls it at menu open.
    /// The display half re-homes a stale pick — see `SourcesModel.refreshDisplays`.
    ///
    /// The microphone pick deliberately survives its device's absence: clearing it here would
    /// forget the user's choice every time the AirPods sat in their case at menu-open. The menu's
    /// picker binding shows None while the device is away (`presentMicrophonePreference`), and
    /// stream starts resolve to the picked device or nothing, so nothing lies.
    public func refreshSources(displays: [DisplayOption]) {
        sources.refreshDisplays(displays)
        let microphones = AudioInputs.available()
        if self.microphones != microphones { self.microphones = microphones }
    }

    /// The user's microphone pick: a specific device, `.automatic` (follow the system default at
    /// capture start, M6-T13), or `.none`. Persisted, and survives its device's absence — resolution
    /// happens at every stream start (device-if-present, else no mic; the default for `.automatic`).
    public var microphonePreference: MicrophonePreference {   // set once in init, then by the picker
        didSet {
            guard microphonePreference != oldValue else { return }
            persist()
            replayConfigurationChanged()
        }
    }

    /// Whether recordings and replays capture what the Mac is playing (ADR-019). Like the mic pick,
    /// changing it while armed restarts the armed stream — SCK binds audio sources per stream.
    public var capturesSystemAudio: Bool {
        didSet {
            guard capturesSystemAudio != oldValue else { return }
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

    // MARK: - Settings (docs/06 "Settings window")

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

    /// Whether the label shows the live input meter while recording or armed (M16-T5). Its twin
    /// above: a display pref, persisted, opt-out.
    public var showsMenuBarLevel: Bool {
        didSet { if showsMenuBarLevel != oldValue { persist() } }
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

    /// The `Export as MP4` width cap (M18-T2), a `Settings.allowedMP4Widths` choice.
    public var mp4Width: Int {
        didSet { if mp4Width != oldValue { persist() } }
    }

    /// Stop a recording after this many minutes (M18-T4); 0 ⇒ off. Applies to the *next* start —
    /// changing it mid-recording would move a deadline the menu has already stated.
    public var stopAfterMinutes: Int {
        didSet { if stopAfterMinutes != oldValue { persist() } }
    }

    /// Seconds of recording the output volume still holds at the current settings (M18-T4), or nil
    /// when the geometry or the volume can't be read. Stored, not computed: reading it is volume
    /// I/O, and the menu is stamped at open (M6-T10).
    public private(set) var recordingRoomSeconds: TimeInterval?

    /// Re-reads the room figure. Volume I/O, so the menu calls it at open (M6-T10).
    public func refreshRecordingRoom() {
        guard let pixels = sources.capturePixelSize,
              let free = DiskSpaceMonitor.availableBytes(forVolumeAtPath: outputDirectory.path)
        else {
            recordingRoomSeconds = nil
            return
        }
        let seconds = RecordingRoom.seconds(
            freeBytes: free,
            bitsPerSecond: BitrateModel.averageBitrate(
                width: pixels.width, height: pixels.height,
                frameRate: frameRateCap, preset: quality))
        if recordingRoomSeconds != seconds { recordingRoomSeconds = seconds }
    }

    /// When the current take will stop itself, or nil when it won't. An absolute time, not a
    /// remaining count: the menu states it stamped at open and it must never tick (M6-T10).
    public private(set) var stopsAt: Date?
    private var automaticStop: Task<Void, Never>?

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

    /// Whether the start/stop shortcut also copies an MP4 when it stops (M24-T2). Off by default.
    /// Persisted. Only reachable while `recordHotkey` is set — the menu keeps both endings as rows.
    public var stopHotkeyCopies: Bool = false {
        didSet {
            guard stopHotkeyCopies != oldValue else { return }
            persist()
        }
    }

    /// Whether Start runs a 3-2-1 count-in first (M12-T6). Off by default. Persisted.
    public var countInEnabled: Bool = false {
        didSet {
            guard countInEnabled != oldValue else { return }
            persist()
        }
    }

    /// Whether a finished take asks to be named (M21-T3). Off by default. Persisted.
    public var namesTakeOnStop: Bool = false {
        didSet {
            guard namesTakeOnStop != oldValue else { return }
            persist()
        }
    }

    /// Runs the count-in overlay, reporting whether it reached zero or the user cancelled it
    /// (M12-T6; cancel M18-T4). Injected by the app (AppKit is banned in AppCore); nil in tests.
    /// Guarded by `isCountingIn` against re-entry.
    public var runCountIn: (@MainActor (@escaping @MainActor (CountInOutcome) -> Void) -> Void)?
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

    /// The recording in flight and what its events mean (M22-T2). The properties below forward,
    /// so views and tests keep naming `state.statusIcon`, `state.apply(…)` and friends. The
    /// *actions* stay here: `start()` needs the count-in, permissions, the output location and
    /// replay, none of which belong to a session's state.
    public let session = SessionModel()

    /// Drives the fold event by event rather than handing the stream to `session`, so everything
    /// `apply` adds on top of it runs in production and not only under test.
    public func consume(_ events: AsyncStream<EngineEvent>) async {
        for await event in events { apply(event) }
    }
    func apply(_ event: EngineEvent) {
        session.apply(event)
        // A take that ends while replay is armed has no banner to announce it (M5-T5), so without
        // this the stop is completely silent — the M23-T3 gap. Read here rather than in the fold:
        // `isReplayArmed` is AppState's, and so is the flash.
        if case .finished(_, let reason, _) = event,
           Self.stopNeedsFlash(isReplayArmed: isReplayArmed, reason: reason) {
            flashSaved()
        }
    }

    /// Permissions/onboarding, split out (M9-T7): AppState owns this sub-model and forwards to it.
    /// It needs one input, `microphoneRequired`, supplied from the mic pick; observation propagates
    /// through the nested `@Observable`, so views read `state.readiness`/`state.onboardingRows`/…
    /// unchanged.
    public let permissions = PermissionsModel()

    /// The one input the model needs: whether a mic is required (i.e. one is picked).
    private var microphoneRequired: Bool { microphonePreference != .none }

    /// Whether a recording could start right now (docs/06 item 1's header status, and what enables
    /// Start). Computed, not stored: SwiftUI builds menu rows before any `.task` runs, so a stored
    /// copy would lag one open (both TCC queries are cheap).
    public var readiness: RecordingReadiness {
        permissions.readiness(microphoneRequired: microphoneRequired)
    }

    /// Set when a recording didn't survive its own start, or degraded on the way. ADR-007
    /// forbids the silent version of either.
    public private(set) var lastFailure: String?
    /// Set by `.failed` so the reason survives the `endSession` that immediately follows it. A
    /// start failure DOES have a session — the engine yields `.failed` and finishes its stream, so
    /// teardown runs a moment later — whereas transient in-recording notices (a lost mic) must not
    /// outlive the recording they described.
    private var failureOutlivesSession = false

    public private(set) var recentRecordings: [URL] = []

    /// The Recent Exports group (M12-T2): the most-recent `.mp4`/`.gif` in the output directory, so
    /// derived share files have an in-menu home and inherit the file submenu. Refreshed with recents.
    public private(set) var recentExports: [URL] = []

    /// Length and size per recent row (M18-T3); each entry also carries the modification date it
    /// was read at, which is what lets an unchanged file skip the re-read.
    private(set) var recentDetails: [URL: RecentRecordings.RowDetail] = [:]
    private var isRefreshingRecentDetails = false

    /// The last replay saved this armed session, for the menu's banner-independent confirmation
    /// (M9-T2): the "Replay saved" notification is suppressed while armed (docs/06). Cleared on
    /// disarm; updated on each save.
    public private(set) var lastReplay: LastReplay?

    /// A brief menu-bar confirmation the label shows on a save (M9-T3): visible without opening
    /// the menu, unlike `lastReplay`'s row. Set on save success, auto-cleared after `flashDuration`.
    /// Since M23-T3 a finished *recording* raises it too, when its banner can't render.
    public private(set) var replaySavedFlash = false
    private var flashTask: Task<Void, Never>?
    private static let flashDuration: Duration = .seconds(2)

    /// Whether a take that just ended needs the menu-bar flash to say so. Pure, so the policy is
    /// asserted rather than inferred from a live capture.
    ///
    /// Only when replay is armed: an armed stream keeps the display captured, which is exactly when
    /// macOS suppresses banners (M5-T5), so a stop there is otherwise completely silent. An ordinary
    /// stop already gets a banner, and flashing as well would confirm the same thing twice.
    /// ⚠️ A proxy, not a certainty — the toggle that governs suppression has no public API (M12-T5),
    /// which is why the shipped copy says banners "may" be hidden.
    static func stopNeedsFlash(isReplayArmed: Bool, reason: EndReason) -> Bool {
        // A write failure leaves a file, but its notice is a problem to read, not a confirmation
        // to glance at — and `SessionModel` already withholds it from the naming prompt (M23-T1).
        guard reason != .writeFailed else { return false }
        return isReplayArmed
    }

    /// The export/trim cluster (M14-T1), the `PermissionsModel` pattern: AppState owns it and
    /// forwards the public surface below, so the view/CLI/test surface is unchanged. Its receipt
    /// persistence uses `defaults`; its notifications forward to `notifier` (both wired in `init`).
    /// Public so views read `state.exports.lastExport` directly (M23-T5) — the forwards that
    /// stood in for that are gone. The action methods above it stay: they supply the export
    /// configuration, which only AppState holds.
    public let exports: ExportModel

    /// The take that just finished — after any rename (M21-T3), so Stop & Copy MP4 shares the file
    /// under the name it was just given, and the menu's receipt row (M24-T3) names it correctly.
    /// Cleared when the next take starts. Only set for an ending that leaves an actionable file:
    /// `SessionModel.finishedRecording` already withholds `.writeFailed` (M23-T1).
    public private(set) var lastRecording: LastRecording?

    /// Asks what to call a take that just stopped (M21-T3), pre-filled with its date name; nil ⇒ keep
    /// that name. Wired by the app: an `NSAlert` is the only surface an `LSUIElement` app has for a
    /// text field, and AppKit doesn't belong here.
    public var promptForTakeName: (@MainActor (_ url: URL, _ duration: TimeInterval) -> String?)?

    // MARK: - Onboarding (docs/06 "Onboarding window") — delegated to PermissionsModel (M9-T7)

    /// Whether the setup window has anything to say: first launch or any missing permission,
    /// never once satisfied (docs/06).
    public var needsOnboarding: Bool { readiness != .ready }

    // The five members below are NOT scaffolding and stay: each supplies `microphoneRequired`,
    // which only AppState knows (it reads the mic pick). Deleting them would copy that rule to
    // every call site. What went was the pure pass-throughs — read those off `permissions`.
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
        capturesSystemAudio = settings.capturesSystemAudio
        // ⚠️ Seeded before `sources.onPickChanged` is wired below, so restoring a pick can't
        // persist it back or rebuild an armed stream that doesn't exist yet.
        sources.selectedAppBundleID = settings.captureAppBundleID
        sources.excludedAppBundleID = settings.excludedAppBundleID
        sources.selectedRegion = settings.captureRegion
        sources.selectedWindow = settings.captureWindow
        isReplayArmed = settings.replayArmed
        replaySeconds = settings.replaySeconds
        replayHotkey = settings.replayHotkey
        recordHotkey = settings.recordHotkey
        pauseHotkey = settings.pauseHotkey
        stopHotkeyCopies = settings.stopHotkeyCopies
        countInEnabled = settings.countInEnabled
        namesTakeOnStop = settings.namesTakeOnStop
        showsMenuBarTimer = settings.showsMenuBarTimer
        showsMenuBarLevel = settings.showsMenuBarLevel
        gifFPS = settings.gifFPS
        gifWidth = settings.gifWidth
        gifMaxSeconds = settings.gifMaxSeconds
        mp4Width = settings.mp4Width
        stopAfterMinutes = settings.stopAfterMinutes
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

        // The source picks live in their own model (M22-T1) but persistence and the armed stream
        // are AppState's, so it wires both back. The display pick is deliberately not persisted —
        // it names hardware that may be gone next launch.
        sources.onPickChanged = { [weak self] in
            self?.persist()
            self?.replayConfigurationChanged()
        }
        sources.onDisplayChanged = { [weak self] in self?.replayConfigurationChanged() }

        // The fold reports; AppState decides who hears it and what outlives the session
        // (M22-T2 ruling A — `lastFailure` is set before any session exists, M17-T2).
        session.notifier = { [weak self] in self?.notifier?($0) }
        session.reportFailure = { [weak self] message, outlivesSession in
            self?.lastFailure = message
            if outlivesSession { self?.failureOutlivesSession = true }
        }

        replay.onMicrophoneLost = { [weak self] in
            self?.notifier?(RecordingNotifications.replayMicrophoneLost())
        }
        replay.onMicrophoneRecovered = { [weak self] in
            self?.notifier?(RecordingNotifications.replayMicrophoneReconnected())
        }
        replay.onMicrophoneSilent = { [weak self] in
            self?.notifier?(RecordingNotifications.replayMicrophoneSilent())
        }
        replay.onMicrophoneAudible = { [weak self] in
            self?.notifier?(RecordingNotifications.replayMicrophoneAudible())
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
                capturesSystemAudio: capturesSystemAudio,
                captureAppBundleID: sources.selectedAppBundleID,
                excludedAppBundleID: sources.excludedAppBundleID,
                captureRegion: sources.selectedRegion,
                captureWindow: sources.selectedWindow,
                replayArmed: isReplayArmed, replaySeconds: replaySeconds,
                replayHotkey: replayHotkey, recordHotkey: recordHotkey,
                pauseHotkey: pauseHotkey, stopHotkeyCopies: stopHotkeyCopies,
                countInEnabled: countInEnabled,
                namesTakeOnStop: namesTakeOnStop,
                showsMenuBarTimer: showsMenuBarTimer, showsMenuBarLevel: showsMenuBarLevel,
                gifFPS: gifFPS, gifWidth: gifWidth, gifMaxSeconds: gifMaxSeconds,
                stopAfterMinutes: stopAfterMinutes, mp4Width: mp4Width,
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
              !permissions.needsRelaunchForScreenGrant else { return }
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
                    self.lastReplay = LastReplay(
                        url: saved.url, seconds: Int(saved.duration.rounded()))
                    self.flashSaved()              // and a signal without opening the menu (M9-T3)
                    self.notifier?(
                        RecordingNotifications.replaySaved(url: saved.url, duration: saved.duration))
                    self.refreshRecentRecordings() // the new clip belongs at the top
                case .failure(let error):
                    Self.log.error("replay save failed: \(error.localizedDescription, privacy: .public)")
                    self.notifier?(RecordingNotifications.replaySaveFailed())
                }
            }
        }
    }

    /// Shows the menu-bar save confirmation, then clears it after `flashDuration` (M9-T3). A new
    /// save restarts the window rather than stacking.
    func flashSaved() {
        replaySavedFlash = true
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.flashDuration)
            guard !Task.isCancelled else { return }
            self?.replaySavedFlash = false
        }
    }

    // Export/trim actions forward to `exports` (M14-T1). AppState owns the persisted export prefs,
    // so it builds each configuration and passes it in.
    public func exportToMP4(_ source: URL, range: ExportRange? = nil) {
        exports.exportToMP4(source, configuration: exportConfiguration, range: range)
    }
    public func exportAndCopy(_ source: URL, range: ExportRange? = nil, crop: CropRect? = nil) {
        exports.exportAndCopy(source, configuration: exportConfiguration, range: range, crop: crop)
    }
    public func exportToGIF(_ source: URL) { exports.exportToGIF(source, configuration: gifConfiguration) }
    public func trim(_ source: URL, from start: Double, to end: Double, mode: TrimMode = .lossless) {
        exports.trim(source, from: start, to: end, mode: mode)
    }

    /// The `Save as GIF` caps as a `GifConfiguration` (M10-T3 follow-up), built from the persisted
    /// settings AppState owns. Pure, so the settings→config mapping is testable on its own.
    var gifConfiguration: GifConfiguration {
        GifConfiguration(maxWidth: gifWidth, maxHeight: gifWidth, fps: gifFPS, maxSeconds: Double(gifMaxSeconds))
    }

    /// The `Export as MP4` size as an `ExportConfiguration` (M18-T2). Only the width is a setting —
    /// the height ceiling is a decoder limit, not a taste (`ExportConfiguration.maxHeight`). Public
    /// so a surface can state the size an export will really produce (M21-T1).
    public var exportConfiguration: ExportConfiguration {
        ExportConfiguration(maxWidth: mp4Width)
    }

    /// The `Stop & Copy MP4` row's title (M21-T2), estimate included. Stamped at menu open like
    /// every other number there (M6-T10), since `session.elapsedSeconds` is.
    public var stopAndCopyTitle: String {
        MenuHeader.stopAndCopy(maximumBytes: maximumShareBytes)
    }

    /// Which of the two Stop rows advertises the start/stop shortcut (M24-T2) — at most one, and
    /// the one the combo actually performs. Without them the menu would claim an ending the key
    /// doesn't have.
    public var stopAndSaveHotkey: Hotkey? { stopHotkeyCopies ? nil : recordHotkey }
    public var stopAndCopyHotkey: Hotkey? { stopHotkeyCopies ? recordHotkey : nil }

    /// The most a share export of the take running now can weigh — the Size picker's own rate
    /// budget (M19-T4) over the elapsed minutes. Nil without display geometry: no figure beats a
    /// wrong one.
    private var maximumShareBytes: Int64? {
        guard let pixels = sources.displayPixelSize, session.elapsedSeconds > 0 else { return nil }
        return exportConfiguration.projectedBytes(
            sourceWidth: pixels.width, sourceHeight: pixels.height, seconds: session.elapsedSeconds)
    }

    /// The Size picker's label for `width`: the size, then what a minute of it weighs (M19-T4) —
    /// every pick plays anywhere (M18-T2), so weight is what decides between them. The ceiling row
    /// states its real fit for the current source, which on a window pick is far below the ceiling.
    /// Without a source geometry the row is the size alone — never quote a figure that can't be
    /// computed (M16-T2).
    public func mp4SizeLabel(forWidth width: Int) -> String {
        let isCeiling = width == Settings.mp4CeilingWidth
        guard let pixels = sources.displayPixelSize else { return isCeiling ? "Largest" : "\(width) px" }
        let configuration = ExportConfiguration(maxWidth: width)
        let fitted = Exporter.fittedSize(
            width: pixels.width, height: pixels.height, configuration: configuration)
        let size = isCeiling ? "Largest (\(fitted.width) × \(fitted.height))" : "\(width) px"
        let perMinute = configuration.bytesPerMinute(forWidth: fitted.width, height: fitted.height)
        return "\(size) · ≈\(ApproximateBytes.formatted(perMinute)) per minute"
    }

    private func syncReplayArming() {
        if isReplayArmed {
            if let capture = session.capture {
                // Resolved, not raw: an absent picked mic must not attach a ring the
                // recording's router will never feed (picked-device-or-nothing, 02 §1).
                replay.recordingStarted(
                    router: capture.router, configuration: replayCaptureConfiguration(),
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
        if let capture = session.capture {
            // Mid-recording only quality/fps can reach here (sources are locked, and the buffer
            // length takes `windowChanged` instead); rebuild on the recording's stream, with
            // the mic pick resolved the same way every replay path resolves it.
            replay.recordingStarted(
                router: session.capture!.router, configuration: replayCaptureConfiguration(),
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
        guard let pixels = sources.capturePixelSize else { return nil }
        // `present…`, not the raw pick: an away device attaches no mic ring, so billing for one
        // would quote a buffer the armed stream isn't going to hold.
        return ReplayFootprint.estimatedBytes(
            width: pixels.width, height: pixels.height, frameRateCap: frameRateCap,
            seconds: Double(seconds), includesMicrophone: presentMicrophonePreference != .none)
    }

    // MARK: - Capability self-test (M16-T6)

    /// Where the onboarding self-test has got to. `nil` result ⇒ never run this launch.
    public enum SelfTestState: Sendable, Equatable {
        case idle
        case running
        case done(CaptureSelfTestResult)
    }
    public private(set) var selfTestState: SelfTestState = .idle

    /// The app's version, for the two footers (M16-T6). ADR-014 hands people a signed `.app`
    /// directly, so "am I on the build with the fix?" has to be answerable from inside it.
    public var versionLabel: String { "ScreenRec \(CoreInfo.version)" }

    /// Records five seconds, reports what came out, and deletes it — proof that capture works, as
    /// opposed to proof that TCC said yes. Writes to a scratch directory, never the output folder.
    public func runCaptureSelfTest() async {
        guard selfTestState != .running else { return }
        selfTestState = .running
        let resolution = microphoneResolution()
        var configuration = captureConfiguration
        configuration.microphone = micSelection(resolution)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenrec-selftest", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let result = await CaptureSelfTest.run(
            configuration: configuration, microphone: selfTestMicrophone(resolution), in: scratch)
        try? FileManager.default.removeItem(at: scratch)
        selfTestState = .done(result)
    }

    /// What the test should say about the mic: the user's pick as it actually resolved.
    private func selfTestMicrophone(_ resolution: MicrophoneResolution) -> MicrophoneExpectation {
        guard microphonePreference != .none else { return .notSelected }
        guard case .explicit(let id) = resolution else {
            let name = if case .device(let picked) = microphonePreference {
                microphones.first { $0.uniqueID == picked }?.name ?? "The selected microphone"
            } else {
                "No microphone"
            }
            return .unavailable(name: name)
        }
        return .expected(name: microphones.first { $0.uniqueID == id }?.name ?? "Microphone")
    }

    /// Loudest mic sample since the last call, for the menu-bar meter (M16-T5) — a recording's
    /// stream when one runs, else the armed stream's. A **method**, not a published property: the
    /// meter polls it off a timer, and a per-frame publish is exactly what M6-T10 forbids.
    public func takeMicrophoneLevel() -> Float {
        let source = session.capture?.microphoneLevel ?? replay.microphoneLevelSource
        return source?.takePeakLevel() ?? 0
    }

    /// Whether the label should draw the meter at all: only when a stream with a mic exists.
    public var showsMicrophoneLevel: Bool {
        guard showsMenuBarLevel, presentMicrophonePreference != .none else { return false }
        return session.isActive || isReplayArmed
    }

    /// docs/06: says so when both audio sources are off, so a silent take isn't discovered
    /// afterwards (ADR-019). Nil whenever any audio is being captured — no row in the common case.
    public var silentRecordingWarning: String? {
        guard !capturesSystemAudio, presentMicrophonePreference == .none else { return nil }
        return "This recording will have no audio"
    }

    /// docs/06: the Settings caption under the buffer slider. Both costs of arming, memory first —
    /// that's the one the slider changes.
    public func replayBufferCaption(seconds: Int) -> String {
        let awake = "While armed, ScreenRec keeps your Mac awake."
        guard let bytes = replayBufferBytes(seconds: seconds) else { return awake }
        return "A \(Self.bufferPhrase(seconds)) buffer holds about "
            + "\(ApproximateBytes.formatted(bytes)) in memory. \(awake)"
    }

    /// docs/06: the armed menu's dimmed cost row. Stamped at open, never ticking (M6-T10).
    public var replayBufferMenuLabel: String {
        guard let bytes = replayBufferBytes(seconds: replaySeconds) else {
            return "Mac stays awake while armed"
        }
        return "\(Self.shortBufferPhrase(replaySeconds)) buffer · "
            + "≈\(ApproximateBytes.formatted(bytes)) · Mac stays awake"
    }

    /// `45-second` / `1-minute` / `1:45` — whole minutes read better than `1:00`, and the slider's
    /// 15 s step makes the mixed case common enough to spell.
    static func bufferPhrase(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)-second" }
        if seconds % 60 == 0 { return "\(seconds / 60)-minute" }
        return Timecode.length(Double(seconds))
    }

    /// The menu's tighter column: `45 s` / `1 min` / `1:45`.
    static func shortBufferPhrase(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return Timecode.length(Double(seconds))
    }

    public func refreshRecentRecordings() {
        let recents = RecentRecordings.inDirectory(outputDirectory)
        if recentRecordings != recents { recentRecordings = recents }
        let exportFiles = RecentRecordings.inDirectory(
            outputDirectory, extensions: RecentRecordings.exportExtensions,
            limit: RecentRecordings.exportLimit)
        if recentExports != exportFiles { recentExports = exportFiles }
    }

    /// What each recent row says beyond its name (M18-T3), read off the menu open so the menu
    /// never waits on the filesystem. One at a time, like the app and window lists: a quick reopen
    /// would otherwise let a stale pass land last and drop a row's detail while the menu is up.
    public func refreshRecentDetails() async {
        guard !isRefreshingRecentDetails else { return }
        isRefreshingRecentDetails = true
        defer { isRefreshingRecentDetails = false }
        let fresh = await RecentRecordings.details(
            for: recentRecordings + recentExports, cached: recentDetails)
        if recentDetails != fresh { recentDetails = fresh }
    }

    /// A row's menu title, name-only until its details arrive.
    public func rowTitle(for url: URL) -> String {
        RecentRecordings.rowTitle(for: url, detail: recentDetails[url])
    }

    /// Drops a stale export receipt at menu open (M12-T3) — forwards to `exports` (M14-T1).

    /// Settles everything a quit must not kill: a recording finalizes (ADR-007), then an export
    /// finishes (M23-T2). One definition, so the menu's Quit and `applicationShouldTerminate`
    /// can't drift on what "safe to exit" means. Returns at once when nothing is in flight.
    public func finishWorkInFlight() async {
        if session.isActive { await stopAndWaitForFinalize() }
        await exports.waitForExportToFinish()
    }

    /// True when `url` is still on disk. The menu's rows are stamped at open, so a file can go
    /// away under them; every action checks first and reports rather than doing nothing (M18-T4).
    public func fileStillExists(_ url: URL) -> Bool {
        guard !FileManager.default.fileExists(atPath: url.path) else { return true }
        forget(url)
        notifier?(RecordingNotifications.fileMissing(url: url))
        return false
    }

    /// Drops the take receipt once it has aged past the export receipt's window, or if its file has
    /// gone (M24-T3). Called at menu open, riding the same stamp-at-open refresh as the recents and
    /// `exports.expireStaleReceipt()`. The row claims recency; `Recordings ▸` is where a take lives
    /// afterwards, so this expires rather than persisting.
    public func expireStaleRecordingReceipt() {
        guard let take = lastRecording else { return }
        if take.isStale(now: Date(), freshFor: ExportModel.receiptFreshness)
            || !FileManager.default.fileExists(atPath: take.url.path) {
            lastRecording = nil
        }
    }

    /// Drops every menu pointer to `url`. The replay receipt is the one that otherwise survives —
    /// it clears only on disarm, so without this a trashed clip keeps its row and re-reports.
    private func forget(_ url: URL) {
        exports.clearReceipt(for: url)
        if lastReplay?.url.isSameFile(as: url) == true { lastReplay = nil }
        if lastRecording?.url.isSameFile(as: url) == true { lastRecording = nil }
        refreshRecentRecordings()
    }

    /// Renames a recording or export in place, extension intact (M12-T2). A blank/unchanged name is
    /// a no-op; a collision resolves like the exporters (` 2`). Re-points the receipt if it named
    /// this file. The source of a derived export is untouched — each acts on its own URL, no cascade.
    @discardableResult
    public func rename(_ url: URL, to newBaseName: String) -> URL? {
        guard let preferred = RenameTarget.compute(for: url, newBaseName: newBaseName) else { return nil }
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
                return nil
            }
        }
        exports.renameReceipt(from: url, to: target)   // re-points the export receipt if it named this
        if let replay = lastReplay, replay.url.isSameFile(as: url) {
            lastReplay = LastReplay(url: target, seconds: replay.seconds)
        }
        if let take = lastRecording, take.url.isSameFile(as: url) {
            // Keeps the original date, so a renamed take doesn't become fresh again (M12-T3's rule).
            lastRecording = LastRecording(url: target, duration: take.duration, date: take.date)
        }
        refreshRecentRecordings()
        return target
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
        if lastRecording?.url.isSameFile(as: url) == true { lastRecording = nil }
        refreshRecentRecordings()
    }

    // MARK: - Configuration

    /// What the pickers currently describe. Pure, so the menu→capture translation is testable
    /// without starting anything.
    public var captureConfiguration: CaptureConfiguration {
        let content: ContentSelection
        if let window = sources.selectedWindow {
            // The owner travels with the id so capture can refuse a reused one (docs/02 §1c).
            content = .window(id: window.id, ownerBundleID: window.bundleID)
        } else if let region = sources.selectedRegion {
            content = .region(display: region.displayID.map(DisplaySelection.id) ?? .main, rect: region.rect)
        } else if let bundleID = sources.selectedAppBundleID {
            content = .app(bundleID: bundleID)
        } else if let excluded = sources.excludedAppBundleID {
            content = .displayExcluding(
                sources.selectedDisplayID.map(DisplaySelection.id) ?? .main, bundleID: excluded)
        } else {
            content = .display(sources.selectedDisplayID.map(DisplaySelection.id) ?? .main)
        }
        return CaptureConfiguration(
            content: content,
            microphone: pickedMicrophoneID.map { MicrophoneSelection.device(id: $0) } ?? .none,
            // Honor the pick (M8-T2): a specific device recovers only onto itself; Automatic
            // follows the current system default at return time.
            microphoneRecovery: microphonePreference == .automatic ? .systemDefault : .sameDevice,
            capturesSystemAudio: capturesSystemAudio,
            frameRateCap: frameRateCap,
            quality: quality)
    }

    /// Opens the drag-to-select overlay (M11-T2). Injected by the app — the overlay is AppKit,
    /// banned in AppCore; nil in tests. The menu's "Select Region…" calls this. `@MainActor`-typed
    /// like the other injections (it drives AppKit and `setRegion`).
    public var beginRegionSelection: (@MainActor () -> Void)?

    // MARK: - Actions (docs/06 "Menu — idle/recording state", items 2–3)

    public func start() async {
        // See `session.isActive`: the menu is clickable again before the first frame lands.
        guard !session.isActive, !isCountingIn else { return }

        lastFailure = nil
        failureOutlivesSession = false
        // The menu disables Start unless this holds; unreachable from the UI.
        guard readiness == .ready else { return }

        // Optional 3-2-1 count-in (M12-T6): show the overlay, then begin capture when it reaches
        // zero — the countdown itself isn't recorded. `isCountingIn` blocks a second Start during it.
        if countInEnabled, let runCountIn {
            isCountingIn = true
            runCountIn { [weak self] outcome in
                guard let self else { return }
                // Synchronously, before any hop: Start has to be usable the instant the count ends,
                // or a cancel-then-Start in the same beat is swallowed by this very guard.
                isCountingIn = false
                guard outcome == .finished else { return }   // cancelled: idle, nothing written
                Task { await self.beginCapture() }
            }
            return
        }
        await beginCapture()
    }

    /// The actual capture start, after any count-in. Split from `start()` so the count-in can defer it.
    private func beginCapture() async {
        guard !session.isActive else { return }

        var configuration = captureConfiguration
        let microphone = resolvedMicrophone()
        configuration.microphone = microphone.selection

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

        let capture: RecordingSession
        do {
            capture = try RecordingSession(configuration: configuration, outputURL: outputURL)
        } catch {
            // The reservation is an O_EXCL placeholder at the `.partial` companion; with no
            // recorder, drop it rather than leave a 0-byte file and the name taken.
            try? FileManager.default.removeItem(at: OutputLocation.partialURL(for: outputURL))
            Self.log.error("recorder setup failed: \(error.localizedDescription, privacy: .public)")
            apply(.failed(message: "Couldn't start recording. Try a different output folder, "
                + "or restart ScreenRec if it keeps happening."))
            return
        }

        lastRecording = nil   // a new take supersedes whatever the last one was named
        session.attach(
            capture, outputURL: outputURL, microphoneName: microphone.name,
            appName: sources.selectedAppBundleID.map(sources.appName(for:)), region: sources.selectedRegion?.rect.size)
        scheduleAutomaticStop()

        // `session.activeMicrophoneName` is what `resolvedMicrophone()` above just resolved to; posting
        // here, after the session commits, keeps a failed start from claiming it began.
        if let notice = RecordingNotifications.recordingStart(
            microphonePreference: microphonePreference, resolvedMicName: session.activeMicrophoneName) {
            notifier?(notice)
        }

        // Armed replay rides the recording's stream from here (docs/01's key property; the
        // buffer restarts — a new stream is a new pts epoch).
        if isReplayArmed {
            replay.recordingStarted(
                router: capture.router, configuration: configuration,
                seconds: Double(replaySeconds), outputDirectory: outputDirectory)
        }

        let events = capture.events
        session.consumeTask = Task { [weak self] in
            guard let self else { return }
            await consume(events)
            // Read before the teardown clears it, act after: the prompt (M21-T3) must not hold up
            // re-arming replay or cancelling the stop timer, and it must not run at all for a
            // discard or a start that left no file.
            let finished = session.finishedRecording
            endSession()
            finishTake(finished)
        }
        await capture.start()
    }

    /// Clean, user-initiated stop. The file finalizes and `finished` follows, which is what
    /// actually ends the session — see `endSession`.
    public func stop() async {
        await session.capture?.stop()
    }

    /// Names the take that just ended, if asked (M21-T3), and raises its menu receipt (M24-T3).
    /// Nil ⇒ the ending left no actionable file (a discard, a start that failed, a `.writeFailed`),
    /// and nothing is claimed. Internal rather than inline in the consume task, which no test can
    /// reach (M23-T3).
    func finishTake(_ finished: (url: URL, duration: TimeInterval)?) {
        guard let finished else { return }
        let url = nameTakeIfAsked(finished.url, duration: finished.duration) ?? finished.url
        lastRecording = LastRecording(url: url, duration: finished.duration, date: Date())
    }

    /// Asks what to call the take that just finished, if the user opted in (M21-T3), and renames it.
    /// A nil answer — Esc, Cancel, a blank or unchanged name — keeps the date name.
    /// Internal, not private, so the policy is testable without a capture session.
    @discardableResult
    func nameTakeIfAsked(_ url: URL, duration: TimeInterval) -> URL? {
        guard namesTakeOnStop, let prompt = promptForTakeName else { return nil }
        guard let chosen = prompt(url, duration) else { return nil }
        return rename(url, to: chosen)
    }

    /// Stop & Copy MP4 (M21-T2): finalize the take, then export it and leave the result on the
    /// pasteboard. The recording is kept (ADR-004) — the `.mp4` is derived beside it, exactly as
    /// `Export as MP4` derives one. The in-flight guard is belt and braces: the menu row is
    /// disabled while an export runs, so the press it would swallow can't be made.
    public func stopAndShare() async {
        guard session.isActive, exports.exportInProgress == nil else { return }
        await stopAndWaitForFinalize()
        // `lastRecording` is where the take actually ended up: the naming prompt (M21-T3)
        // runs inside the same task, so the `.mp4` inherits the chosen name instead of landing
        // beside it under the date. Nil ⇒ the take left no file (a discard, a start that failed).
        guard let finished = lastRecording?.url,
              FileManager.default.fileExists(atPath: finished.path)
        else { return }
        exportAndCopy(finished)
    }

    /// Arms the `Stop After` bound for this take (M18-T4), if one is set. Wall clock from the
    /// start, and it stops the same way the user would — `.userStopped`, so the file finalizes
    /// through the one path (the CLI's own `--duration` does this too).
    private func scheduleAutomaticStop() {
        automaticStop?.cancel()
        guard let deadline = Self.automaticStopDate(from: Date(), minutes: stopAfterMinutes) else {
            stopsAt = nil
            return
        }
        let seconds = deadline.timeIntervalSinceNow
        stopsAt = deadline
        automaticStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    /// When a take started at `now` under a `minutes` bound will stop itself; nil ⇒ no bound.
    /// Pure, so the deadline the menu states is testable without a capture session.
    static func automaticStopDate(from now: Date, minutes: Int) -> Date? {
        guard minutes > 0 else { return nil }
        return now.addingTimeInterval(Double(minutes) * 60)
    }

    /// Throw the current take away: the file is removed and the session ends at `.discarded`,
    /// which — like every ending — returns to idle via `endSession`.
    public func discard() async {
        await session.capture?.discard()
    }

    public func pause() async {
        await session.capture?.pause()
    }

    public func resume() async {
        await session.capture?.resume()
    }

    /// What the global start/stop shortcut does (M9-T4): a session in flight — recording or paused —
    /// stops and saves; otherwise a ready app starts, and a blocked one says why. Never a silent
    /// no-op — the shortcut advertised an action.
    public func toggleRecording() async {
        switch Self.recordToggleAction(
            isSessionActive: session.isActive, isReady: readiness == .ready,
            copiesOnStop: stopHotkeyCopies, isExporting: exports.exportInProgress != nil
        ) {
        case .start: await start()
        case .stop: await stop()
        case .stopAndCopy: await stopAndShare()
        case .stopWithoutCopy:
            // Waits for finalize, not just `stop()`: the take's own "Recording saved" is posted
            // when `.finished` drains, so notifying any earlier puts this notice on screen first
            // and lets the next banner bury it (measured — it lasted under 0.3 s).
            await stopAndWaitForFinalize()
            notifier?(RecordingNotifications.stopCopySkipped())
        case .blockedNotify: notifier?(RecordingNotifications.recordingHotkeyBlocked())
        }
    }

    enum RecordToggleAction: Equatable {
        case start, stop, stopAndCopy, stopWithoutCopy, blockedNotify
    }

    /// Pure so every branch is unit-tested without live capture (which `start`/`stop` need).
    ///
    /// `stopWithoutCopy` is the one non-obvious arm (M24-T2): an export is already running, and
    /// `performExport` would drop a second one. Stopping is the shortcut's primary contract, so it
    /// still stops — but the missing half has to be said, since a hotkey can't grey itself out the
    /// way the menu row does (M17-T2).
    /// Neither flag is defaulted: a caller that passed `copiesOnStop` and forgot `isExporting`
    /// would land in `stopAndShare`, whose own guard returns silently.
    static func recordToggleAction(
        isSessionActive: Bool, isReady: Bool, copiesOnStop: Bool, isExporting: Bool
    ) -> RecordToggleAction {
        guard isSessionActive else {   // a paused session is still active — stop wins
            return isReady ? .start : .blockedNotify
        }
        guard copiesOnStop else { return .stop }
        return isExporting ? .stopWithoutCopy : .stopAndCopy
    }

    /// What the global pause/resume shortcut does (M12-T6): a live recording pauses, a paused one
    /// resumes, and with nothing recording it does nothing (a silent no-op, not a failure).
    public func togglePause() async {
        switch Self.pauseToggleAction(isSessionActive: session.isActive, isPaused: session.isPaused) {
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
        guard let task = session.consumeTask else { return }
        await stop()
        await task.value
    }

    // MARK: - Event folding

    /// Internal, not private, so the failure-lifecycle tests can drive the teardown that
    /// lands on top of a start failure (the bug M17-T2 found live).
    func endSession() {
        session.clear()
        // The recording's stream is going away; an armed replay resumes on a private one.
        if isReplayArmed {
            replay.recordingEnded(
                configuration: replayCaptureConfiguration(), seconds: Double(replaySeconds),
                outputDirectory: outputDirectory)
        }
        automaticStop?.cancel()
        automaticStop = nil
        stopsAt = nil
        // A transient notice (a lost mic) must not outlive the recording it described. A failure
        // must: it is the only account the user gets of a Start that produced nothing, and the
        // engine yields it *through* the session, so teardown lands right on top of it.
        if failureOutlivesSession {
            failureOutlivesSession = false
        } else {
            lastFailure = nil
        }
        refreshRecentRecordings()      // the file that just finalized belongs at the top
    }

    // MARK: - Helpers

    /// Resolves the pick to a device (or none) for a recording, and names it for the menu — SCK
    /// needs an explicit device ID or capture fails with an opaque "invalid parameter" (02 §1).
    /// Shares `microphoneResolution()` with the replay path so the two never bind different mics.
    /// Returns the name alongside the selection: the name is session-scoped state (`SessionModel`
    /// takes it at `attach`), and this runs before a session exists.
    private func resolvedMicrophone() -> (selection: MicrophoneSelection, name: String?) {
        guard microphonePreference != .none else { return (.none, nil) }
        switch microphoneResolution() {
        case .explicit(let resolved):
            return (.device(id: resolved),
                    AudioInputs.available().first { $0.uniqueID == resolved }?.name)
        case .noDevice:
            // Record the screen anyway — losing a capture over a missing microphone is the worse
            // outcome (ADR-012) — but never silently (ADR-007).
            lastFailure = microphonePreference == .automatic
                ? "No microphone connected — recording without one."
                : "The selected microphone isn't connected — recording without it."
            return (.none, nil)
        }
    }

}
