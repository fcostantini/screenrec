import Foundation
import RecorderCore

/// The permission a row is about.
public enum PermissionKind: Sendable, Equatable, CaseIterable {
    case screenRecording
    case microphone
    case notifications
}

/// A System Settings pane a row can send the user to. The URL lives here (Foundation) while
/// the opening is the app's job (NSWorkspace) — the usual split.
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
        /// "Open System Settings…" — asking is no longer a route (02 §2: macOS prompts once,
        /// ever), so hand the user the only door that's left.
        case openSettings(SettingsPane)
        /// Satisfied; no button.
        case none
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
/// Pure and injectable, so every combination is a unit test rather than a thing you have to
/// take on faith — which matters more here than anywhere else in the app, because most of these
/// states are ones this machine can't easily be put into.
public enum OnboardingModel {

    public static func rows(
        screen: PermissionState,
        hasAskedForScreen: Bool,
        microphone: PermissionState,
        microphoneRequired: Bool,
        notifications: PermissionState
    ) -> [OnboardingRow] {
        [screenRow(screen, hasAsked: hasAskedForScreen),
         microphoneRow(microphone, required: microphoneRequired),
         notificationsRow(notifications)]
    }

    /// Screen recording — always required, and the only row that has to guess.
    ///
    /// `Permissions.screenRecordingState()` collapses "never asked" and "declined" into
    /// `.notDetermined` (02 §2), so the row can't know which it's in. It doesn't need to: the
    /// remedy differs only in whether a prompt happens to appear. So the row asks once, and
    /// afterwards offers System Settings regardless — which covers the user who just declined,
    /// the user who declined months ago, *and* the user who granted it and needs the restart.
    /// Switching on "did we ask" rather than "were we denied" is what makes that possible;
    /// trying to detect the decline itself would be guessing at a state macOS won't report.
    private static func screenRow(_ state: PermissionState, hasAsked: Bool) -> OnboardingRow {
        let satisfied = state == .granted
        let detail: String
        let action: OnboardingRow.Action
        switch (satisfied, hasAsked) {
        case (true, _):
            detail = "ScreenRec can record your screen and system audio."
            action = .none
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

    /// Microphone — needed only when one is selected, and the one row that never has to guess:
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
            action = .none
        case .notDetermined:
            // "Optional" is only true until they pick one. Said while Start is greyed out
            // *because of this row*, it reads as "this isn't your problem" to the one person
            // whose problem it is.
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

    /// Notifications — optional, and never blocks anything (docs/06). The app is fully
    /// functional without them; they only carry the "saved / ended because…" message (M4-T5).
    private static func notificationsRow(_ state: PermissionState) -> OnboardingRow {
        let satisfied = state == .granted
        let detail: String
        let action: OnboardingRow.Action
        switch state {
        case .granted:
            detail = "ScreenRec will tell you when a recording is saved."
            action = .none
        case .notDetermined:
            detail = "Optional — tells you when a recording is saved, and why it ended."
            action = .request
        case .denied:
            detail = "Skipped. ScreenRec works fine without notifications."
            action = .openSettings(.notifications)
        }
        return OnboardingRow(
            id: .notifications, title: "Notifications", detail: detail,
            isSatisfied: satisfied, action: action, blocksRecording: false)
    }
}
