import AppCore
import SwiftUI

/// Identifies the onboarding window to `openWindow`. Both the launch check and the menu's
/// blocked header open the same one.
let onboardingWindowID = "onboarding"

/// The menu-bar app (docs/06 "Shell"): no Dock icon, no main window — `LSUIElement` in
/// Info.plist — so the status item and its menu are the app's surface. The only windows that
/// exist are Onboarding (here) and Settings (M4-T4).
///
/// The shell owns the one `AppState`; `MenuView` is the menu, `StatusIconView` the icon.
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
    }
}

/// The status item, plus the first-launch onboarding check.
///
/// The check lives on the *label* because the label is the only view that exists from the moment
/// the app launches — menu content isn't built until someone opens the menu, and an app whose
/// onboarding waits for the user to go looking for it has no onboarding at all.
private struct StatusIconLabel: View {
    let state: AppState

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        StatusIconView(icon: state.statusIcon)
            .task {
                // docs/06: the window appears on first launch or any missing permission, and
                // never once satisfied.
                if state.needsOnboarding {
                    openWindow(id: onboardingWindowID)
                    // An LSUIElement app is an accessory: without this the window opens behind
                    // whatever the user is looking at, which on a first launch is
                    // indistinguishable from the app having done nothing at all.
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                await relaunchWhenScreenGrantLands()
            }
    }

    /// Watches for the screen grant and reopens the app — the promise the onboarding row makes.
    ///
    /// It lives *here*, on the status item, and not in the onboarding window, because the window
    /// is closable and the promise isn't: close it mid-flow and a relaunch driven from there
    /// would silently never happen, leaving preflight saying `granted` while this process still
    /// can't capture (02 §2). This task lives as long as the app does.
    ///
    /// It also keys on the grant *landing*, not on our `Grant…` button being pressed — the user
    /// may simply flip the switch in System Settings, which needs exactly the same restart.
    private func relaunchWhenScreenGrantLands() async {
        // Launched already-granted ⇒ there is no transition to wait for, and no loop to run.
        // This is also what stops an already-granted app relaunching itself forever.
        guard !state.screenWasGrantedAtLaunch else { return }

        while !Task.isCancelled {
            // `isSessionActive` is the guard that makes terminating safe. It should be
            // unreachable — `readiness` reports blocked until the relaunch happens, so Start is
            // disabled — but "should be" is not a thing to abandon a live writer on (ADR-007).
            if state.needsRelaunchForScreenGrant, !state.isSessionActive {
                Relaunch.now()
                // Reached only if the spawn failed — `now()` terminates on success. Back off
                // before retrying rather than returning: the app must not settle into a state
                // it has already been told it can't record from. The wait is deliberately long
                // so a failing spawn can't launch a herd of copies while `terminate` is still
                // unwinding.
                try? await Task.sleep(for: .seconds(5))
                continue
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
