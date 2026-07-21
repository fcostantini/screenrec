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

    // MARK: - Instant replay (docs/06 idle item 3, Settings "Instant Replay")

    /// Arming starts the rolling buffer (its own capture stream while idle; a recording's
    /// stream while one runs) and registers the hotkey. Persisted; restored at launch via
    /// `activateReplayIfArmed()` — never from `init`, which tests construct freely.
    public var isReplayArmed: Bool {
        didSet {
            guard isReplayArmed != oldValue else { return }
            persist()
            syncReplayArming()
        }
    }

    /// The rolling window; docs/06 offers 30/60/120. Changing it resizes the rings in place —
    /// the buffer survives: grow fills over time, shrink evicts the excess now.
    public var replaySeconds: Int {
        didSet {
            persist()
            if replaySeconds != oldValue, isReplayArmed {
                replay.windowChanged(seconds: Double(replaySeconds))
            }
        }
    }

    public var replayHotkey: ReplayHotkey {
        didSet {
            persist()
            if isReplayArmed { registerReplayHotkey() }
        }
    }

    /// Registers/unregisters the global save shortcut, reporting whether the system accepted
    /// it. Injected by the app (Carbon lives there, not in AppCore); nil means unregister.
    public var hotkeyRegistrar: (@MainActor (ReplayHotkey?) -> Bool)?

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
            microphoneRequired: microphonePreference != .none)
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
    /// The app being recorded, for the recording menu's "Recording <app> only" line (docs/06,
    /// M7-T2); nil for whole-screen. Named at start — the pick is locked for the session.
    public private(set) var activeAppName: String?
    /// Set when a recording didn't survive its own start, or degraded on the way. ADR-007
    /// forbids the silent version of either.
    public private(set) var lastFailure: String?

    public private(set) var recentRecordings: [URL] = []

    /// The last replay saved this armed session, for the menu's banner-independent confirmation
    /// (M9-T2): the "Replay saved" notification is suppressed while armed (docs/06). Cleared on
    /// disarm; updated on each save.
    public private(set) var lastReplay: LastReplay?

    /// A brief menu-bar confirmation the label shows on a save (M9-T3): visible without opening
    /// the menu, unlike `lastReplay`'s row. Set on save success, auto-cleared after `flashDuration`.
    public private(set) var replaySavedFlash = false
    private var flashTask: Task<Void, Never>?
    private static let flashDuration: Duration = .seconds(2)

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
            microphoneRequired: microphonePreference != .none,
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
        isReplayArmed = settings.replayArmed
        replaySeconds = settings.replaySeconds
        replayHotkey = settings.replayHotkey
        showsMenuBarTimer = settings.showsMenuBarTimer
        replay = replayController ?? ReplayController()
        screenWasGrantedAtLaunch = Permissions.screenRecordingState() == .granted
        refreshOnboarding()          // populated before the first render, or the window flickers

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
                replayArmed: isReplayArmed, replaySeconds: replaySeconds,
                replayHotkey: replayHotkey, showsMenuBarTimer: showsMenuBarTimer),
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
            _ = hotkeyRegistrar?(nil)
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

    /// Registers the shortcut and tells the user if the system refused it (combo taken by
    /// another app) — every UI surface advertises the combo, so a silent failure means a
    /// keypress that saves nothing.
    private func registerReplayHotkey() {
        guard let hotkeyRegistrar else { return }
        if !hotkeyRegistrar(replayHotkey) {
            notifier?(RecordingNotifications.replayHotkeyUnavailable())
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

    public func refreshRecentRecordings() {
        let recents = RecentRecordings.inDirectory(outputDirectory)
        if recentRecordings != recents { recentRecordings = recents }
    }

    /// Re-reads the writer's duration and the file's size on disk.
    ///
    /// Polled, not pushed: `EngineEvent.fileProgress` is declared but nothing emits it. Suits
    /// docs/06 here anyway ("≤ 1 Hz, menu open only").
    public func refreshProgress() {
        let duration = session?.recordedDuration.seconds ?? 0
        // NaN until the first frame starts the session (docs/02 §10).
        let seconds = duration.isFinite ? duration : 0
        let bytes = currentOutputURL.map(Self.fileSize) ?? 0
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
        CaptureConfiguration(
            content: selectedAppBundleID.map { ContentSelection.app(bundleID: $0) }
                ?? .display(selectedDisplayID.map(DisplaySelection.id) ?? .main),
            microphone: pickedMicrophoneID.map { MicrophoneSelection.device(id: $0) } ?? .none,
            // Honor the pick (M8-T2): a specific device recovers only onto itself; Automatic
            // follows the current system default at return time.
            microphoneRecovery: microphonePreference == .automatic ? .systemDefault : .sameDevice,
            frameRateCap: frameRateCap,
            quality: quality)
    }

    /// The Source picker's one Hashable selection over both row kinds (docs/06 item 5, M7-T2).
    /// Writing `.display` clears the app pick; the remembered display survives an app detour.
    /// The two backing writes are batched (`isRehomingSources`) into ONE persist + rebuild.
    public var sourceChoice: SourceChoice {
        get { selectedAppBundleID.map { .app(bundleID: $0) } ?? .display(selectedDisplayID) }
        set {
            guard newValue != sourceChoice else { return }
            isRehomingSources = true
            switch newValue {
            case .display(let id):
                selectedAppBundleID = nil
                selectedDisplayID = id
            case .app(let bundleID):
                selectedAppBundleID = bundleID
            }
            isRehomingSources = false
            persist()
            replayConfigurationChanged()
        }
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
        activeAppName = selectedAppBundleID.map(appName(for:))

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
        case .recordingFileRestored:
            break   // recording unaffected; the notification carries the news
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

    private static func fileSize(_ url: URL) -> Int64 {
        // In-progress recordings live at the `.partial` companion; the final name appears
        // only at finalize. Probe the partial first so the header's size isn't stuck at zero.
        for candidate in [OutputLocation.partialURL(for: url), url] {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path),
               let size = attributes[.size] as? NSNumber {
                return size.int64Value
            }
        }
        return 0
    }
}
