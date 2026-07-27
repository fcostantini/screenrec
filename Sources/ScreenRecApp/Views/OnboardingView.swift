import AppCore
import RecorderCore
import AppKit
import SwiftUI
import UserNotifications

/// The setup window (docs/06 "Onboarding window"): a checklist of three rows, each with live
/// status and one button.
struct OnboardingView: View {
    let state: AppState

    /// Permissions are granted in System Settings with no callback, so polling while the window
    /// is open is the only way to notice.
    private static let pollInterval = Duration.seconds(1)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window is both the first-run checklist and the app's permissions screen, so
            // the intro tracks `needsOnboarding`.
            Text(state.needsOnboarding
                 ? "ScreenRec needs two permissions from macOS before it can record."
                 : "ScreenRec has everything it needs. Change any of these at any time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                // Wrap, don't truncate: a `Text` in a fixed-width window otherwise trims to one
                // line and ends in an ellipsis.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 18)

            ForEach(state.onboardingRows) { row in
                PermissionRowView(row: row, act: { act(on: row) })
                Divider()
            }

            // M16-T6: green ticks only mean TCC said yes. This is the claim that matters —
            // a recording comes out, with the sources the pickers name.
            SelfTestSection(state: state)

            Divider().padding(.top, 14)
            Text(state.versionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(22)
        .frame(width: 460)
        .task { await pollUntilSatisfied() }
    }

    /// The five-second capability test and its verdict (M16-T6).
private struct SelfTestSection: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check that recording works").fontWeight(.semibold)
                    Text("Records five seconds and throws it away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(state.selfTestState == .running ? "Testing…" : "Run a test") {
                    Task { await state.runCaptureSelfTest() }
                }
                .disabled(state.selfTestState == .running)
            }
            if case .done(let result) = state.selfTestState {
                VStack(alignment: .leading, spacing: 3) {
                    line("screen", result.screen)
                    line("system audio", result.systemAudio)
                    line("microphone", result.microphone)
                }
                .font(.caption.monospaced())
                .padding(.top, 2)
            }
        }
        .padding(.top, 14)
    }

    /// `✓ microphone · MacBook Pro Microphone` — symbol, source, then whatever the outcome adds.
    private func line(_ label: String, _ outcome: SelfTestOutcome) -> some View {
        let (symbol, detail, colour): (String, String?, Color) = switch outcome {
        case .ok(let detail): ("✓", detail, .green)
        case .skipped(let reason): ("—", reason, .secondary)
        case .warning(let message): ("!", message, .orange)
        case .failed(let message): ("✗", message, .red)
        }
        return Text("\(symbol) \(label)").foregroundStyle(colour)
            + Text(detail.map { " · \($0)" } ?? "").foregroundStyle(.secondary)
    }
}

/// One button, whatever the row says it should do.
    private func act(on row: OnboardingRow) {
        switch row.action {
        case .openSettings(let pane), .review(let pane):
            NSWorkspace.shared.open(pane.url)
        case .request:
            switch row.id {
            case .screenRecording:
                // Effectively always returns false: granting happens in System Settings and
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
    /// bundle, which `swift test` has none of. AppCore keeps the state; the app supplies it.
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

    /// Keeps the rows honest while the window is up. Does not relaunch — that lives in
    /// `App.swift`, on a task that outlives this closable window. Both permission sources are
    /// re-read every tick: they're granted elsewhere, with no callback.
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

            // Bordered when there's something to do, a plain link when there isn't: an all-green
            // checklist shouldn't read as unfinished.
            if row.action.isCallToAction {
                Button(buttonTitle, action: act)
            } else {
                Button(buttonTitle, action: act)
                    .buttonStyle(.link)
                    .accessibilityLabel("\(row.title): open System Settings to change this")
            }
        }
        .padding(.vertical, 12)
    }

    private var buttonTitle: String {
        switch row.action {
        case .request: "Grant…"
        case .openSettings: "Open System Settings…"
        case .review: "System Settings"
        }
    }
}
