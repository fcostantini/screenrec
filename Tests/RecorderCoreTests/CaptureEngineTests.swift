import Foundation
import Testing
@testable import RecorderCore

@Suite struct CaptureEngineTests {

    // The start gate, with injected permission state + display count (the denied-path
    // unit test — live TCC revocation would destroy this terminal's own grant, docs/02 §2).

    @Test func failsWhenScreenExplicitlyDenied() {
        guard case .fail = CaptureEngine.startDecision(screenPermission: .denied, availableDisplays: 1) else {
            Issue.record("expected .fail when screen recording is denied")
            return
        }
    }

    @Test func failsWhenNoDisplaysAvailable() {
        // Zero shareable displays is the real live signal of missing permission (docs/02 §1).
        guard case .fail = CaptureEngine.startDecision(screenPermission: .notDetermined, availableDisplays: 0) else {
            Issue.record("expected .fail when no displays are available")
            return
        }
    }

    @Test func proceedsWhenGrantedWithDisplays() {
        #expect(CaptureEngine.startDecision(screenPermission: .granted, availableDisplays: 2) == .proceed)
    }

    @Test func proceedsWhenNotDeterminedButDisplaysPresent() {
        // CGPreflight is unreliable for CLI binaries; visible displays mean we can capture.
        #expect(CaptureEngine.startDecision(screenPermission: .notDetermined, availableDisplays: 1) == .proceed)
    }

    // Start-error → user-facing message (the thrown-permission path, docs/02 §2/§10).

    @Test func startErrorMapsSCKDeclineToGuidance() {
        let declined = NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: -3801)
        #expect(CaptureEngine.startErrorMessage(declined) == CaptureEngine.permissionGuidance)
    }

    @Test func startErrorMapsDeclineMessageToGuidance() {
        let declined = NSError(domain: "Other", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The user declined TCCs for display capture"])
        #expect(CaptureEngine.startErrorMessage(declined) == CaptureEngine.permissionGuidance)
    }

    @Test func startErrorPassesThroughOtherErrors() {
        let other = NSError(domain: "Foo", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk on fire"])
        #expect(CaptureEngine.startErrorMessage(other) == "disk on fire")
    }
}
