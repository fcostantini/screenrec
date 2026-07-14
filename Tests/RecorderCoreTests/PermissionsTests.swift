import Testing
@testable import RecorderCore

@Suite struct PermissionsTests {

    // MARK: recordingReadiness decision table

    @Test func readyWhenScreenAndMicGranted() {
        #expect(Permissions.recordingReadiness(screen: .granted, microphone: .granted, microphoneRequired: true) == .ready)
    }

    @Test func readyWhenScreenGrantedAndMicNotRequired() {
        // A denied mic doesn't block when the user chose no microphone.
        #expect(Permissions.recordingReadiness(screen: .granted, microphone: .denied, microphoneRequired: false) == .ready)
    }

    @Test func needsScreenWhenScreenNotDetermined() {
        #expect(Permissions.recordingReadiness(screen: .notDetermined, microphone: .granted, microphoneRequired: true) == .needsScreenRecording)
    }

    @Test func blockedWhenScreenDenied() {
        guard case .blocked = Permissions.recordingReadiness(screen: .denied, microphone: .granted, microphoneRequired: true) else {
            Issue.record("expected .blocked when screen recording is denied")
            return
        }
    }

    @Test func needsMicWhenMicNotDetermined() {
        #expect(Permissions.recordingReadiness(screen: .granted, microphone: .notDetermined, microphoneRequired: true) == .needsMicrophone)
    }

    @Test func blockedWhenMicDeniedAndRequired() {
        guard case .blocked = Permissions.recordingReadiness(screen: .granted, microphone: .denied, microphoneRequired: true) else {
            Issue.record("expected .blocked when a required microphone is denied")
            return
        }
    }

    // MARK: microphone resolution (the ⚠️ nil-mic-ID lesson)

    @Test func micResolutionPrefersExplicitID() {
        #expect(Permissions.resolveMicrophoneID(preferred: "ABC") { "DEF" } == .explicit("ABC"))
    }

    @Test func micResolutionFallsBackToDefault() {
        #expect(Permissions.resolveMicrophoneID(preferred: nil) { "DEF" } == .explicit("DEF"))
    }

    @Test func micResolutionEmptyPreferredIsTreatedAsUnset() {
        #expect(Permissions.resolveMicrophoneID(preferred: "") { "DEF" } == .explicit("DEF"))
    }

    @Test func micResolutionNoDeviceWhenNoDefault() {
        guard case .noDevice = Permissions.resolveMicrophoneID(preferred: nil, defaultDeviceID: { nil }) else {
            Issue.record("expected .noDevice when there is no preferred or default microphone")
            return
        }
    }

    @Test func micResolutionFallsBackWhenPreferredDeviceGone() {
        // Preferred ID persisted but the device was unplugged → fall back, don't pass a dead ID.
        let result = Permissions.resolveMicrophoneID(
            preferred: "DEAD", deviceExists: { _ in false }, defaultDeviceID: { "DEFAULT" })
        #expect(result == .explicit("DEFAULT"))
    }

    @Test func micResolutionNoDeviceWhenPreferredGoneAndNoDefault() {
        guard case .noDevice = Permissions.resolveMicrophoneID(
            preferred: "DEAD", deviceExists: { _ in false }, defaultDeviceID: { nil }) else {
            Issue.record("expected .noDevice when the preferred device is gone and there is no default")
            return
        }
    }

    @Test func micResolutionEmptyDefaultIsTreatedAsNoDevice() {
        guard case .noDevice = Permissions.resolveMicrophoneID(preferred: nil, defaultDeviceID: { "" }) else {
            Issue.record("expected .noDevice for an empty default device ID")
            return
        }
    }
}
