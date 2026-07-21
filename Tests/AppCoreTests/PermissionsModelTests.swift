import Foundation
import Testing
@testable import AppCore
import RecorderCore

/// The permission/onboarding sub-model split from AppState (M9-T7). It reads live TCC state (not
/// injectable, same as before the split), so these assert only what's independent of the grant
/// state; the checklist's per-row logic is covered by OnboardingModelTests.
@MainActor
@Suite struct PermissionsModelTests {

    @Test func startsUnaskedAndUndeterminedWithNoRowsUntilRefreshed() {
        let model = PermissionsModel()
        #expect(!model.hasAskedForScreenRecording)
        #expect(model.notificationState == .notDetermined)
        #expect(model.onboardingRows.isEmpty)          // init doesn't refresh; AppState does
    }

    @Test func setNotificationStateUpdatesTheHeldValueAndRefreshes() {
        let model = PermissionsModel()
        model.setNotificationState(.granted, microphoneRequired: false)
        #expect(model.notificationState == .granted)
        #expect(model.onboardingRows.count == 3)       // screen · microphone · notifications
    }
}
