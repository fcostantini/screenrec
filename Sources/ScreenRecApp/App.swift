import AppCore
import SwiftUI

/// Window IDs for `openWindow`.
let onboardingWindowID = "onboarding"
let settingsWindowID = "settings"

/// The menu-bar app (docs/06 "Shell"): `LSUIElement`, so the status item and its menu are the
/// app's surface. Owns the one `AppState`; the only windows are Onboarding and Settings.
@main
struct ScreenRecApp: App {
    @State private var state = AppState()

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

/// The status item, plus the first-launch onboarding check.
///
/// The check lives on the label because the label is the only view that exists from launch —
/// menu content isn't built until the menu opens.
private struct StatusIconLabel: View {
    let state: AppState

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        StatusIconView(icon: state.statusIcon)
            .task {
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
