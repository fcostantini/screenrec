import AppCore
import AppKit
import ServiceManagement

/// The Trim window's title, shared with `TrimView`'s key monitor, which scopes itself by it.
let trimWindowTitle = "Trim"

/// The menu-bar app (docs/06 "Shell"): `LSUIElement`, so the status item and its menu are the app's
/// surface. Onboarding, Settings and Trim are the only windows, and `WindowPresenter` builds them.
///
/// The module's whole public surface: everything else stays internal, which is what lets the tests
/// reach it through `@testable import`.
@MainActor
public enum ScreenRec {
    /// Hands control to AppKit; does not return until the app quits.
    public static func run() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }

    /// `NSApplication.delegate` is weak, so the app's owner has to be this.
    private static let delegate = AppDelegate()
}

/// Owns the one `AppState` and everything AppKit that hangs off it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private let notifier = Notifier()
    private let hotkeys = HotkeyCenter()
    /// One overlay controller, reused per region pick (M11-T2).
    private let regionSelector = RegionSelectionController()
    private let windows = WindowPresenter()
    private lazy var countIn = CountInController(hotkeys: hotkeys)
    private var statusItem: StatusItemController?
    /// Held so the watch outlives `applicationDidFinishLaunching`.
    private var screenGrantWatch: Task<Void, Never>?

    override init() {
        super.init()
        windows.state = state
        // Posting is the app's job; AppCore may not import UserNotifications (docs/01).
        state.notifier = { [weak notifier] in notifier?.post($0) }
        // SMAppService is a system service, not UI, but the seam keeps AppState testable.
        state.loginItem = SMLoginItem()
        // Names a picked-but-closed app for the Source picker's "(not running)" row (M7-T2).
        // NSWorkspace is AppKit, so the resolver is injected rather than living in AppCore.
        // Cached: the row is rebuilt per menu open, and each miss is a LaunchServices DB query plus
        // disk metadata; an installed app's name can't change mid-run.
        var appNameCache: [String: String] = [:]
        state.sources.appDisplayName = { bundleID in
            if let cached = appNameCache[bundleID] { return cached }
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { FileManager.default.displayName(atPath: $0.path) }
            if let name { appNameCache[bundleID] = name }
            return name
        }
        // Keeps the Source picker to apps a user would record: SCShareableContent also lists
        // windowed system chrome (Dock, Control Center…). Whole-list shape so one process-table
        // snapshot serves every app; the CLI's `list-apps` deliberately stays unfiltered.
        state.sources.recordableAppsFilter = { apps in
            let regular = Set(NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier))
            return apps.filter { regular.contains($0.bundleID) }
        }
        // Region selection (M11-T2): the menu's "Select Region…" opens the drag overlay, which
        // hands back a rect in SCK points; AppKit lives here, not in AppCore. Weak capture — the
        // closure is stored on `state`, which the controller must not retain.
        state.beginRegionSelection = { [weak self, weak state] in
            self?.regionSelector.present(seededWith: state?.sources.selectedRegion) { display, rect in
                state?.setRegion(displayID: display, rect: rect)
            }
        }
        // First-arm banner-suppression alert (M12-T5): AppKit lives here, fired once ever.
        state.onReplayBannerWarning = { NotificationSettings.showArmedBannerWarning() }
        // Stop & Copy MP4 (M21-T2): the pasteboard is AppKit, so the app performs the copy the
        // export path asks for — the same write the per-file `Copy` row does.
        state.exports.copyToPasteboard = { ShareActions.copy($0) }
        // Naming a take as it stops (M21-T3): the same `NSAlert` the Rename… row uses.
        state.promptForTakeName = { ShareActions.nameTake($0, duration: $1) }
        // Global shortcuts (M9-T4): map each intent to a Carbon hotkey id + the action it fires.
        // Carbon lives here; AppCore stays framework-free.
        state.hotkeyRegistrar = { [weak self, weak state] hotkey, which in
            guard let hotkeys = self?.hotkeys, let state else { return false }
            switch which {
            case .saveReplay:
                return hotkeys.setHotkey(hotkey, id: .saveReplay) { [weak state] in
                    state?.saveReplay()
                }
            case .toggleRecording:
                return hotkeys.setHotkey(hotkey, id: .toggleRecording) { [weak state] in
                    Task { await state?.toggleRecording() }
                }
            case .togglePause:
                return hotkeys.setHotkey(hotkey, id: .togglePause) { [weak state] in
                    Task { await state?.togglePause() }
                }
            }
        }
        // The 3-2-1 count-in (M12-T6): AppKit overlay lives here, run before capture by AppState.
        state.runCountIn = { [weak self] completion in self?.countIn.run(completion: completion) }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        notifier.install()
        // docs/03's verify hook: print what was delivered, then exit before any UI appears.
        if CommandLine.arguments.contains("--print-delivered-notifications") {
            Notifier.printDeliveredAndExit()
        }
        // After the hook above, so the diagnostic still works while the app is running. A second
        // copy would otherwise fight the first for the hotkeys and hold a second armed ring.
        let others = Self.otherRunningInstances()
        if LaunchPolicy.yieldsToRunningInstance(
            arguments: CommandLine.arguments, otherInstances: others.count) {
            others.first?.activate()
            exit(0)   // nothing has been built yet, so there is nothing to tear down
        }
        notifier.requestAuthorizationIfNeeded()
    }

    /// Copies of this app running under the same bundle id, excluding this process — so a build in
    /// `~/Downloads` and one in `/Applications` count as each other's.
    private static func otherRunningInstances() -> [NSRunningApplication] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != .current }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(state: state, windows: windows)
        // A persisted armed state resumes at launch; `AppState.init` never arms (tests construct
        // one freely and must not spin capture).
        state.activateReplayIfArmed()
        // The start/stop shortcut isn't tied to arming, so it registers on its own (M9-T4)…
        state.activateRecordHotkey()
        // …and likewise the pause/resume one (M12-T6).
        state.activatePauseHotkey()
        state.syncLaunchAtLogin()
        // Before any recording can start, so a live partial is never mistaken for a crash orphan.
        state.recoverInterruptedRecordings()
        // After recovery, so the recents can't list a partial that is about to be renamed.
        statusItem?.refreshMenuData()
        // docs/06: appears on first launch or any missing permission, never once satisfied.
        if state.needsOnboarding { windows.show(.onboarding) }
        screenGrantWatch = Task { [weak self] in await self?.relaunchWhenScreenGrantLands() }

    }

    /// Finishes work in flight before exit — an in-progress recording (ADR-007) or an export
    /// (M23-T2) — on every quit route, including logout, shutdown, a software update, and `⌘Q`
    /// while a window is key. Idle / armed-replay have nothing on disk to save.
    ///
    /// Silent by design: a modal during logout can stall it. The menu's Quit does the asking, and
    /// arrives here with its answer already applied — a take finalized, or an abandoned export
    /// already cleared — so this sees nothing left to wait for.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state.session.isActive || state.exports.exportInProgress != nil else {
            return .terminateNow
        }
        Task { @MainActor in
            await state.finishWorkInFlight()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Watches for the screen grant and reopens the app. Keys on the grant landing, not on the
    /// `Grant…` button — the user may grant straight from System Settings, which needs the same
    /// restart (02 §2).
    private func relaunchWhenScreenGrantLands() async {
        // Already granted at launch ⇒ no transition to wait for; also what stops a relaunch loop.
        guard !state.permissions.screenWasGrantedAtLaunch else { return }

        let launchedAt = ContinuousClock.now
        while !Task.isCancelled {
            // Should be unreachable — Start is disabled while blocked — but never terminate on a
            // live writer (ADR-007).
            if state.permissions.needsRelaunchForScreenGrant, !state.session.isActive {
                Relaunch.now()
                // Reached only if the spawn failed; `now()` terminates on success. The back-off is
                // long so a failing spawn can't launch copies while `terminate` unwinds.
                try? await Task.sleep(for: .seconds(5))
                continue
            }
            try? await Task.sleep(
                for: LaunchPolicy.grantPollInterval(sinceLaunch: ContinuousClock.now - launchedAt))
        }
    }
}
