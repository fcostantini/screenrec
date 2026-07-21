import AppCore
import ServiceManagement
import SwiftUI

/// Window IDs for `openWindow`.
let onboardingWindowID = "onboarding"
let settingsWindowID = "settings"

/// The menu-bar app (docs/06 "Shell"): `LSUIElement`, so the status item and its menu are the
/// app's surface. Owns the one `AppState`; the only windows are Onboarding and Settings.
@main
struct ScreenRecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    init() {
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
        // Global shortcuts (M9-T4): map each intent to a Carbon hotkey id + the action it fires.
        // Carbon lives here; AppCore stays framework-free. Weak captures — the closure is stored on
        // `state`, which owns it.
        let hotkeys = ScreenRecApp.hotkeys
        let state = state
        state.hotkeyRegistrar = { [weak hotkeys, weak state] hotkey, which in
            guard let hotkeys, let state else { return false }
            switch which {
            case .saveReplay:
                return hotkeys.setHotkey(hotkey, id: 1) { [weak state] in state?.saveReplay() }
            case .toggleRecording:
                return hotkeys.setHotkey(hotkey, id: 2) { [weak state] in
                    Task { await state?.toggleRecording() }
                }
            }
        }
    }

    /// Shared with the delegate, which installs it before launch completes.
    fileprivate static let notifier = Notifier()
    fileprivate static let hotkeys = HotkeyCenter()

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
    }
}

/// Exists for one reason: the notification delegate must be installed before launch finishes, or
/// a click that *launches* the app is delivered to nobody.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        ScreenRecApp.notifier.install()
        // docs/03's verify hook: print what was delivered, then exit before any UI appears.
        if CommandLine.arguments.contains("--print-delivered-notifications") {
            Notifier.printDeliveredAndExit()
        }
        ScreenRecApp.notifier.requestAuthorizationIfNeeded()
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
            replaySavedFlash: state.replaySavedFlash)
            .task {
                // A persisted armed state resumes at launch; `init` never arms (tests
                // construct AppState freely and must not spin capture).
                state.activateReplayIfArmed()
                // The start/stop shortcut isn't tied to arming, so it registers on its own (M9-T4).
                state.activateRecordHotkey()
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
