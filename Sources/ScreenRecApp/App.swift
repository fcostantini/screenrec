import AppCore
import ServiceManagement
import SwiftUI

/// Window IDs for `openWindow`.
let onboardingWindowID = "onboarding"
let settingsWindowID = "settings"
let trimWindowID = "trim"

/// The menu-bar app (docs/06 "Shell"): `LSUIElement`, so the status item and its menu are the
/// app's surface. Owns the one `AppState`; the only windows are Onboarding and Settings.
@main
struct ScreenRecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    init() {
        // So a non-menu quit (logout/shutdown/⌘Q-from-a-window) finalizes an in-progress recording
        // (M13-T2). Read on the main thread from `applicationShouldTerminate`.
        delegate.appState = state
        let notifier = ScreenRecApp.notifier
        // Posting is the app's job; AppCore may not import UserNotifications (docs/01).
        state.notifier = { [weak notifier] in notifier?.post($0) }
        // SMAppService is a system service, not UI, but the seam keeps AppState testable.
        state.loginItem = SMLoginItem()
        // Names a picked-but-closed app for the Source picker's "(not running)" row (M7-T2).
        // NSWorkspace is AppKit, so the resolver is injected rather than living in AppCore.
        // Cached: the row re-renders per menu publish, and each miss is a LaunchServices DB
        // query plus disk metadata; an installed app's name can't change mid-run.
        var appNameCache: [String: String] = [:]
        state.appDisplayName = { bundleID in
            if let cached = appNameCache[bundleID] { return cached }
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { FileManager.default.displayName(atPath: $0.path) }
            if let name { appNameCache[bundleID] = name }
            return name
        }
        // Keeps the Source picker to apps a user would record: SCShareableContent also lists
        // windowed system chrome (Dock, Control Center…). Whole-list shape so one process-table
        // snapshot serves every app; the CLI's `list-apps` deliberately stays unfiltered.
        state.recordableAppsFilter = { apps in
            let regular = Set(NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier))
            return apps.filter { regular.contains($0.bundleID) }
        }
        // Region selection (M11-T2): the menu's "Select Region…" opens the drag overlay, which
        // hands back a rect in SCK points; AppKit lives here, not in AppCore. Weak capture — the
        // closure is stored on `state`, which the controller must not retain.
        let regionSelector = ScreenRecApp.regionSelector
        state.beginRegionSelection = { [weak state] in
            regionSelector.present(seededWith: state?.selectedRegion) { displayID, rect in
                state?.setRegion(displayID: displayID, rect: rect)
            }
        }
        // First-arm banner-suppression alert (M12-T5): AppKit lives here, fired once ever by AppState.
        state.onReplayBannerWarning = { NotificationSettings.showArmedBannerWarning() }
        // Global shortcuts (M9-T4): map each intent to a Carbon hotkey id + the action it fires.
        // Carbon lives here; AppCore stays framework-free. Weak captures — the closure is stored on
        // `state`, which owns it.
        let hotkeys = ScreenRecApp.hotkeys
        let state = state
        state.hotkeyRegistrar = { [weak hotkeys, weak state] hotkey, which in
            guard let hotkeys, let state else { return false }
            switch which {
            case .saveReplay:
                return hotkeys.setHotkey(hotkey, id: .saveReplay) { [weak state] in state?.saveReplay() }
            case .toggleRecording:
                return hotkeys.setHotkey(hotkey, id: .toggleRecording) { [weak state] in
                    Task { await state?.toggleRecording() }
                }
            case .togglePause:
                return hotkeys.setHotkey(hotkey, id: .togglePause) { [weak state] in
                    Task { await state?.togglePause() }
                }
            case .addMark:
                return hotkeys.setHotkey(hotkey, id: .addMark) { [weak state] in state?.addMark() }
            }
        }
        // The 3-2-1 count-in (M12-T6): AppKit overlay lives here, run before capture by AppState.
        let countIn = ScreenRecApp.countIn
        state.runCountIn = { completion in countIn.run(completion: completion) }
    }

    /// Shared with the delegate, which installs it before launch completes.
    fileprivate static let notifier = Notifier()
    fileprivate static let hotkeys = HotkeyCenter()
    /// One overlay controller, reused per region pick (M11-T2).
    fileprivate static let regionSelector = RegionSelectionController()
    /// One count-in overlay controller, reused per recording start (M12-T6).
    fileprivate static let countIn = CountInController(hotkeys: hotkeys)

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: state)
        } label: {
            StatusIconLabel(state: state)
        }
        .menuBarExtraStyle(.menu)

        Window("Set Up ScreenRec", id: onboardingWindowID) {
            OnboardingView(state: state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // A plain `Window`, not SwiftUI's `Settings` scene: `Settings` exists to route ⌘, through
        // the app menu, which an LSUIElement app doesn't have — ⌘, is bound on the menu item.
        Window("ScreenRec Settings", id: settingsWindowID) {
            SettingsView(state: state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // The Trim window (M10-T4): a fixed window that reads `state.trimTarget`, set by the menu's
        // "Trim…" — a plain `Window`, like Settings, since an LSUIElement app has no ⌘N to spawn one.
        Window("Trim", id: trimWindowID) {
            TrimView(state: state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Installs the notification delegate before launch finishes (or a launching click is delivered to
/// nobody), and finalizes an in-progress recording on any quit route (M13-T2).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `ScreenRecApp.init`. Weak — the App's `@State` owns it; this is a back-reference.
    weak var appState: AppState?

    func applicationWillFinishLaunching(_ notification: Notification) {
        ScreenRecApp.notifier.install()
        // docs/03's verify hook: print what was delivered, then exit before any UI appears.
        if CommandLine.arguments.contains("--print-delivered-notifications") {
            Notifier.printDeliveredAndExit()
        }
        ScreenRecApp.notifier.requestAuthorizationIfNeeded()
    }

    /// Finalizes an in-progress recording before exit on quit routes that skip the menu's Quit —
    /// logout, shutdown, a software update, or `⌘Q` while a window is key (ADR-007). The menu Quit
    /// finalizes first, so `session` is already gone here (→ `.terminateNow`); idle / armed-replay
    /// have nothing on disk to save. Silent by design — a modal during logout can stall it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState, appState.isSessionActive else { return .terminateNow }
        Task { @MainActor in
            await appState.stopAndWaitForFinalize()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// The status item, plus the first-launch onboarding check.
///
/// The check lives on the label because the label is the only view that exists from launch —
/// menu content isn't built until the menu opens.
private struct StatusIconLabel: View {
    let state: AppState

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        StatusIconView(
            icon: state.statusIcon,
            isReplayArmed: state.isReplayArmed,
            recordingClock: state.recordingClock,
            showsTimer: state.showsMenuBarTimer,
            replaySavedFlash: state.replaySavedFlash,
            markAddedFlash: state.markAddedFlash,
            microphoneLevel: state.showsMicrophoneLevel ? { state.takeMicrophoneLevel() } : nil)
            .task {
                // A persisted armed state resumes at launch; `init` never arms (tests
                // construct AppState freely and must not spin capture).
                state.activateReplayIfArmed()
                // The start/stop shortcut isn't tied to arming, so it registers on its own (M9-T4).
                state.activateRecordHotkey()
                // Likewise the pause/resume shortcut (M12-T6) and the mark shortcut (M20-T1).
                state.activatePauseHotkey()
                state.activateMarkHotkey()
                state.syncLaunchAtLogin()
                // Before any recording can start, so a live partial is never mistaken
                // for a crash orphan.
                state.recoverInterruptedRecordings()
                // docs/06: appears on first launch or any missing permission, never once
                // satisfied.
                if state.needsOnboarding {
                    openWindow(id: onboardingWindowID)
                    // An accessory (LSUIElement) app's windows open behind the frontmost app
                    // unless it activates.
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                await relaunchWhenScreenGrantLands()
            }
    }

    /// Watches for the screen grant and reopens the app.
    ///
    /// Lives on the status item, not the onboarding window: the window is closable and this must
    /// outlive it. Keys on the grant landing, not on the Grant… button — the user may grant
    /// straight from System Settings, which needs the same restart (02 §2).
    private func relaunchWhenScreenGrantLands() async {
        // Already granted at launch ⇒ no transition to wait for; also what stops a relaunch loop.
        guard !state.screenWasGrantedAtLaunch else { return }

        while !Task.isCancelled {
            // Should be unreachable — Start is disabled while blocked — but never terminate on a
            // live writer (ADR-007).
            if state.needsRelaunchForScreenGrant, !state.isSessionActive {
                Relaunch.now()
                // Reached only if the spawn failed; `now()` terminates on success. The back-off
                // is long so a failing spawn can't launch copies while `terminate` unwinds.
                try? await Task.sleep(for: .seconds(5))
                continue
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
