import AppCore
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
        // Same split for the hotkey: Carbon lives here, AppCore stays framework-free.
        let hotkeys = ScreenRecApp.hotkeys
        state.hotkeyRegistrar = { [weak hotkeys] in hotkeys?.setHotkey($0) ?? false }
        let state = state
        hotkeys.onHotkey = { state.saveReplay() }
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
        StatusIconView(icon: state.statusIcon, isReplayArmed: state.isReplayArmed)
            .task {
                // A persisted armed state resumes at launch; `init` never arms (tests
                // construct AppState freely and must not spin capture).
                state.activateReplayIfArmed()
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
