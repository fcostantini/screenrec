import Foundation
import Observation
import RecorderCore

/// The permission/onboarding state, split out of `AppState` (M9-T7). Self-contained but for one
/// input — `microphoneRequired`, which the caller supplies from the mic pick — because readiness
/// and the onboarding checklist both depend on whether a mic is required.
@MainActor
@Observable
public final class PermissionsModel {

    /// Whether the screen-recording prompt has been fired this launch. This — not "were we denied"
    /// — flips the row to the System Settings route: preflight reads false for "never asked" and
    /// "declined" alike (02 §2), and after asking the remedy is the same either way.
    public private(set) var hasAskedForScreenRecording = false

    /// Notification authorization. Held rather than queried because, unlike TCC, reading it is
    /// async — and the live call needs a real bundle, so the app supplies it and tests inject it.
    public private(set) var notificationState: PermissionState = .notDetermined

    /// The checklist. Stored and refreshed, unlike the computed `readiness`, because the window
    /// stays open while the user crosses to System Settings: TCC changes outside the process, so
    /// `@Observable` has nothing to observe and a computed value would never redraw. The window
    /// polls, and the poll writes here.
    public private(set) var onboardingRows: [OnboardingRow] = []

    /// Whether screen recording was already granted when this process started. The relaunch
    /// decision keys on the transition (ungranted at launch → granted now), not on whether our
    /// button was pressed — a grant flipped straight in System Settings needs the same restart —
    /// and keying on the snapshot avoids a relaunch loop when the app launched already-granted.
    public let screenWasGrantedAtLaunch: Bool

    public init() {
        screenWasGrantedAtLaunch = Permissions.screenRecordingState() == .granted
    }

    /// The grant has landed but this process can't use it yet.
    public var needsRelaunchForScreenGrant: Bool {
        !screenWasGrantedAtLaunch && Permissions.screenRecordingState() == .granted
    }

    /// Whether a recording could start right now (docs/06 item 1's header status). A grant this
    /// process hasn't restarted into is not readiness: preflight flips true the moment the switch
    /// lands, but the process keeps its launch-time TCC decision until a full restart (02 §2).
    public func readiness(microphoneRequired: Bool) -> RecordingReadiness {
        if needsRelaunchForScreenGrant {
            return .blocked(reason: "ScreenRec needs to reopen to finish turning on screen "
                + "recording. It will do that on its own in a moment.")
        }
        return Permissions.recordingReadiness(
            screen: Permissions.screenRecordingState(),
            microphone: Permissions.microphoneState(),
            microphoneRequired: microphoneRequired)
    }

    /// Re-reads the permission states. Assigns only on a real change: `@Observable` publishes on
    /// every set, not every change, so an unconditional write would redraw the window once a second.
    public func refreshOnboarding(microphoneRequired: Bool, banners: BannerVisibility) {
        let fresh = OnboardingModel.rows(
            screen: Permissions.screenRecordingState(),
            hasAskedForScreen: hasAskedForScreenRecording,
            microphone: Permissions.microphoneState(),
            microphoneRequired: microphoneRequired,
            notifications: notificationState,
            banners: banners)
        if fresh != onboardingRows { onboardingRows = fresh }
    }

    /// Fires the screen-recording prompt and latches that it has been asked. Returns whether the
    /// grant landed — it essentially never does on the spot: macOS makes the user cross to System
    /// Settings and restart the app (02 §2). The window polls for it instead.
    @discardableResult
    public func requestScreenRecording(microphoneRequired: Bool, banners: BannerVisibility) -> Bool {
        hasAskedForScreenRecording = true
        let granted = Permissions.requestScreenRecording()
        refreshOnboarding(microphoneRequired: microphoneRequired, banners: banners)   // row → System Settings
        return granted
    }

    public func requestMicrophoneAccess(microphoneRequired: Bool, banners: BannerVisibility) async {
        _ = await Permissions.requestMicrophoneAccess()
        refreshOnboarding(microphoneRequired: microphoneRequired, banners: banners)
    }

    public func setNotificationState(
        _ state: PermissionState, microphoneRequired: Bool, banners: BannerVisibility
    ) {
        notificationState = state
        refreshOnboarding(microphoneRequired: microphoneRequired, banners: banners)
    }
}
