import Foundation
import RecorderCore

/// The permission a row is about.
public enum PermissionKind: Sendable, Equatable, CaseIterable {
    case screenRecording
    case microphone
    case notifications
}

/// A System Settings pane a row can send the user to. The URL lives here (Foundation); opening
/// it is the app's job (NSWorkspace).
public enum SettingsPane: Sendable, Equatable {
    case screenRecording
    case microphone
    case notifications

    public var url: URL {
        // Invariant: these are compile-time-constant literals, valid by inspection.
        switch self {
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .notifications:
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        }
    }
}

/// One row of the onboarding checklist (docs/06 "Onboarding window").
public struct OnboardingRow: Sendable, Equatable, Identifiable {

    /// The row's single button.
    public enum Action: Sendable, Equatable {
        /// "Grant…" — ask macOS.
        case request
        /// "Open System Settings…" — macOS prompts once ever (02 §2), so after a decline this is
        /// the only route left.
        case openSettings(SettingsPane)
        /// "System Settings" — a quiet way to review or revoke a granted permission. A link, not
        /// a button: nothing needs doing.
        case review(SettingsPane)

        /// Whether this row is asking for something. Drives the button's prominence: bordered
        /// means there is something to do, a plain link means there isn't.
        public var isCallToAction: Bool {
            switch self {
            case .request, .openSettings: true
            case .review: false
            }
        }

        /// Where the button goes, if anywhere.
        public var settingsPane: SettingsPane? {
            switch self {
            case .openSettings(let pane), .review(let pane): pane
            case .request: nil
            }
        }
    }

    public let id: PermissionKind
    public let title: String
    /// The explainer, or the remedy. docs/06's copy rule: name the fix, not the API.
    public let detail: String
    /// ✓ vs ○.
    public let isSatisfied: Bool
    public let action: Action
    /// Whether recording stays blocked while this row is unsatisfied.
    public let blocksRecording: Bool
}

/// Builds the onboarding checklist from permission states.
///
/// Pure and injectable: most of these permission states can't easily be reproduced on a dev
/// machine, so every combination is a unit test.
public enum OnboardingModel {

    public static func rows(
        screen: PermissionState,
        hasAskedForScreen: Bool,
        microphone: PermissionState,
        microphoneRequired: Bool,
        notifications: PermissionState,
        banners: BannerVisibility
    ) -> [OnboardingRow] {
        [screenRow(screen, hasAsked: hasAskedForScreen),
         microphoneRow(microphone, required: microphoneRequired),
         notificationsRow(notifications, banners: banners)]
    }

    /// Screen recording — always required.
    ///
    /// `Permissions.screenRecordingState()` collapses "never asked" and "declined" into
    /// `.notDetermined` (02 §2), so the row switches on `hasAsked` instead: ask once, then offer
    /// System Settings regardless. That covers decline, old decline, and grant-needs-restart
    /// alike.
    private static func screenRow(_ state: PermissionState, hasAsked: Bool) -> OnboardingRow {
        let satisfied = state == .granted
        let detail: String
        let action: OnboardingRow.Action
        switch (satisfied, hasAsked) {
        case (true, _):
            detail = "ScreenRec can record your screen and system audio."
            action = .review(.screenRecording)
        case (false, false):
            detail = "macOS requires quitting and reopening ScreenRec after granting — "
                + "we'll relaunch automatically."
            action = .request
        case (false, true):
            detail = "Turn on ScreenRec in System Settings, then reopen it. "
                + "If you just granted it, ScreenRec will relaunch on its own."
            action = .openSettings(.screenRecording)
        }
        return OnboardingRow(
            id: .screenRecording, title: "Screen & System Audio Recording",
            detail: detail, isSatisfied: satisfied, action: action,
            blocksRecording: !satisfied)
    }

    /// Microphone — needed only when one is selected. The one row that never has to guess:
    /// `authorizationStatus` reports a real `.denied` (02 §2).
    private static func microphoneRow(
        _ state: PermissionState, required: Bool
    ) -> OnboardingRow {
        let satisfied = state == .granted
        let detail: String
        let action: OnboardingRow.Action
        switch state {
        case .granted:
            detail = "ScreenRec can record your microphone onto its own track."
            action = .review(.microphone)
        case .notDetermined:
            // "Optional" stops being true once a mic is picked: Start is greyed out because of
            // this row.
            detail = required
                ? "Needed for the microphone you selected. Recording is paused until this is on."
                : "Only needed if you record a microphone."
            action = .request
        case .denied:
            detail = required
                ? "Turn on ScreenRec in System Settings — recording is paused until this is on. "
                    + "No restart needed."
                : "Turn on ScreenRec in System Settings. No restart needed."
            action = .openSettings(.microphone)
        }
        return OnboardingRow(
            id: .microphone, title: "Microphone", detail: detail,
            isSatisfied: satisfied, action: action,
            blocksRecording: required && !satisfied)
    }

    /// Notifications — optional, never blocks anything (docs/06). They only carry the
    /// "saved / ended because…" message.
    /// ⚠️ The mark stays a tick when banners are suppressed (M35-T3): notifications *are* granted, and
    /// the sharing toggle is macOS's rather than a permission given to us.
    private static func notificationsRow(
        _ state: PermissionState, banners: BannerVisibility
    ) -> OnboardingRow {
        let action: OnboardingRow.Action
        switch state {
        case .granted: action = .review(.notifications)
        case .notDetermined: action = .request
        case .denied: action = .openSettings(.notifications)
        }
        return OnboardingRow(
            id: .notifications, title: "Notifications",
            detail: notificationsDetail(state, banners: banners),
            isSatisfied: state == .granted, action: action, blocksRecording: false)
    }

    /// What the row says. The *action* depends only on the permission; only the **copy** depends on
    /// whether banners will actually render, which is why the two are decided apart.
    private static func notificationsDetail(
        _ state: PermissionState, banners: BannerVisibility
    ) -> String {
        // Nothing is delivered at all, so what happens to banners while armed is moot — and a user
        // who declined must not be lectured about a setting that would change nothing for them.
        guard state != .denied else { return "Skipped. ScreenRec works fine without notifications." }
        let granted = state == .granted
        switch banners {
        case .hidden where granted:
            return "Banners are hidden while replay is armed. Turn on “Allow notifications when "
                + "mirroring or sharing the display” to see them."
        case .shown where granted:
            return "ScreenRec will tell you when a recording is saved — including while replay is "
                + "armed."
        case .hidden:
            return "Optional — tells you when a recording is saved, and why it ended. "
                + "While armed, macOS hides banners from other apps."
        case .shown:
            return "Optional — tells you when a recording is saved, and why it ended."
        // ADR-022: a read that failed keeps the hedge the app used when it could read nothing at all.
        case .unknown where granted:
            return "ScreenRec will tell you when a recording is saved. "
                + "While replay is armed, macOS may hide banners from other apps."
        case .unknown:
            return "Optional — tells you when a recording is saved, and why it ended. "
                + "While armed, macOS may hide banners from other apps."
        }
    }
}
