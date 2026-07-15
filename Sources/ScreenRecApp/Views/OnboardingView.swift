import AppCore
import AppKit
import SwiftUI
import UserNotifications

/// The setup window (docs/06 "Onboarding window"): a checklist of three rows, each with live
/// status and one button. No wizard, no marketing, no Continue — it closes itself when the rows
/// that matter go green.
struct OnboardingView: View {
    let state: AppState

    /// Screen recording is granted somewhere else entirely — in System Settings, minutes later —
    /// and nothing calls back to say so. Polling while the window is open is the only way to
    /// notice, and it's the same ≤1 Hz, only-while-visible discipline the menu uses.
    private static let pollInterval = Duration.seconds(1)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ScreenRec needs two permissions from macOS before it can record.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)

            ForEach(state.onboardingRows) { row in
                PermissionRowView(row: row, act: { act(on: row) })
                if row.id != .notifications { Divider() }
            }
        }
        .padding(22)
        .frame(width: 460)
        .task { await pollUntilSatisfied() }
    }

    /// One button, whatever the row says it should do.
    private func act(on row: OnboardingRow) {
        switch row.action {
        case .none:
            break
        case .openSettings(let pane):
            NSWorkspace.shared.open(pane.url)
        case .request:
            switch row.id {
            case .screenRecording:
                // Returns false essentially always — granting happens in System Settings and
                // needs a restart (02 §2). `pollUntilSatisfied` is what notices.
                state.requestScreenRecording()
            case .microphone:
                Task { await state.requestMicrophoneAccess() }
            case .notifications:
                Task { await requestNotifications() }
            }
        }
    }

    /// UserNotifications lives here rather than in AppCore because the live call needs a real
    /// bundle — `swift test` has none, so a call from AppCore would be untestable at best and a
    /// crash at worst. AppCore keeps the state; the app supplies it.
    private func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        state.setNotificationState(granted ? .granted : .denied)
    }

    private func refreshNotificationState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: state.setNotificationState(.granted)
        case .denied: state.setNotificationState(.denied)
        case .notDetermined: state.setNotificationState(.notDetermined)
        @unknown default: state.setNotificationState(.notDetermined)
        }
    }

    /// Keeps the rows honest while the window is up. **Does not relaunch** — that lives in
    /// `App.swift`, on a task that outlives this window, because the user can close this one at
    /// any moment and the promise to reopen must survive that.
    ///
    /// The refresh is the load-bearing part: every permission this window shows is granted
    /// somewhere we aren't — in System Settings, minutes later — so nothing here notices on its
    /// own. Both sources get re-read every tick; reading notification settings once before the
    /// loop had the identical bug the microphone row shipped with.
    private func pollUntilSatisfied() async {
        while !Task.isCancelled {
            await refreshNotificationState()
            state.refreshOnboarding()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}

/// One checklist row: mark, title, explainer, and at most one button.
private struct PermissionRowView: View {
    let row: OnboardingRow
    let act: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: row.isSatisfied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(row.isSatisfied ? .green : .secondary)
                .accessibilityLabel(row.isSatisfied ? "Granted" : "Not granted")

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).fontWeight(.semibold)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let title = buttonTitle {
                Button(title, action: act)
            }
        }
        .padding(.vertical, 12)
    }

    private var buttonTitle: String? {
        switch row.action {
        case .request: "Grant…"
        case .openSettings: "Open System Settings…"
        case .none: nil
        }
    }
}
