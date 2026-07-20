import ScreenCaptureKit
import Foundation
import Testing
@testable import RecorderCore

@Suite struct CaptureEngineTests {

    // The start gate, with injected permission state + display count (the denied-path
    // unit test — live TCC revocation would destroy this terminal's own grant, docs/02 §2).

    @Test func failsWhenScreenExplicitlyDenied() {
        guard case .fail = CaptureEngine.startDecision(
            screenPermission: .denied, availableDisplays: 1,
            content: .display(.main), runningBundleIDs: []) else {
            Issue.record("expected .fail when screen recording is denied")
            return
        }
    }

    @Test func neverBlamesPermissionForZeroDisplays() {
        // Zero displays cannot mean "ungranted": an ungranted process THROWS from
        // SCShareableContent (02 §10) instead of enumerating zero, so getting here at all means
        // we are authorized. The only measured zero-display state is locked+slept (02 §7).
        // Both live preflight values must say so — `.notDetermined` especially, since that is
        // what a freshly-built CLI binary reports even when it captures fine (02 §10), and it
        // is the only cell the CLI can reach.
        #expect(CaptureEngine.startDecision(
            screenPermission: .granted, availableDisplays: 0,
            content: .display(.main), runningBundleIDs: [])
            == .fail(CaptureEngine.noDisplaysGuidance))
        #expect(CaptureEngine.startDecision(
            screenPermission: .notDetermined, availableDisplays: 0,
            content: .display(.main), runningBundleIDs: [])
            == .fail(CaptureEngine.noDisplaysGuidance))
    }

    @Test func deniedBeatsDisplaysPresent() {
        // Displays present, but the grant is explicitly refused — permission still wins.
        // (Defensive: Permissions.screenRecordingState() cannot currently produce `.denied`.)
        #expect(CaptureEngine.startDecision(
            screenPermission: .denied, availableDisplays: 2,
            content: .display(.main), runningBundleIDs: [])
            == .fail(CaptureEngine.permissionGuidance))
    }

    @Test func proceedsWhenGrantedWithDisplays() {
        #expect(CaptureEngine.startDecision(
            screenPermission: .granted, availableDisplays: 2,
            content: .display(.main), runningBundleIDs: []) == .proceed)
    }

    @Test func proceedsWhenNotDeterminedButDisplaysPresent() {
        // CGPreflight is unreliable for CLI binaries; visible displays mean we can capture.
        #expect(CaptureEngine.startDecision(
            screenPermission: .notDetermined, availableDisplays: 1,
            content: .display(.main), runningBundleIDs: []) == .proceed)
    }

    // Start-error → user-facing message (the thrown-permission path, docs/02 §2/§10).

    @Test func startErrorMapsSCKDeclineToGuidance() {
        let declined = NSError(domain: SCStreamError.errorDomain, code: -3801)
        #expect(CaptureEngine.startErrorMessage(declined) == CaptureEngine.permissionGuidance)
    }

    @Test func startErrorMapsLostDisplayToNoDisplaysGuidance() {
        // The display can vanish inside the start window too — enumeration succeeds, then
        // startCapture throws -3815. Same condition as the other two surfaces, same wording.
        let lost = NSError(domain: SCStreamError.errorDomain, code: -3815)
        #expect(CaptureEngine.startErrorMessage(lost) == CaptureEngine.noDisplaysGuidance)
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

    // Stream death → EndReason (docs/01). -3815 was measured, not guessed: `pmset
    // displaysleepnow` mid-recording (02 §7). Lid-close and unplug are still unobserved.

    @Test func streamErrorMapsLostDisplayToDisplayDisconnected() {
        let lost = NSError(domain: SCStreamError.errorDomain, code: -3815)  // measured
        #expect(CaptureEngine.endReason(forStreamError: lost) == .displayDisconnected)
        let noList = NSError(domain: SCStreamError.errorDomain, code: -3814)  // by kinship
        #expect(CaptureEngine.endReason(forStreamError: noList) == .displayDisconnected)
    }

    @Test func streamErrorMapsSystemIndicatorStopToUserStopped() {
        // macOS's screen-recording indicator lets the user stop the capture; SCK reports that
        // as -3817. Anything but `.userStopped` makes ADR-007 read the most ordinary stop there
        // is as a fail-stop, and M4 would fire an "ended unexpectedly" notification for it.
        let stopped = NSError(domain: SCStreamError.errorDomain, code: -3817)
        #expect(CaptureEngine.endReason(forStreamError: stopped) == .userStopped)
    }

    @Test func streamErrorKeepsTheCodeForUnmappedSCKErrors() {
        // SCK errors are opaque (02 §2); carrying the code is how -3815 was identified at all.
        let unknown = NSError(domain: SCStreamError.errorDomain, code: -3811,
            userInfo: [NSLocalizedDescriptionKey: "internal error"])
        #expect(CaptureEngine.endReason(forStreamError: unknown)
            == .streamError("internal error [SCStreamError -3811]"))
    }

    @Test func streamErrorPassesThroughNonSCKErrors() {
        let other = NSError(domain: "Foo", code: 7, userInfo: [NSLocalizedDescriptionKey: "kaboom"])
        #expect(CaptureEngine.endReason(forStreamError: other) == .streamError("kaboom"))
    }

    // MARK: per-app content (M7-T1)

    @Test func appContentResolvesAgainstRunningApps() {
        #expect(CaptureEngine.startDecision(
            screenPermission: .granted, availableDisplays: 1,
            content: .app(bundleID: "com.example.app"),
            runningBundleIDs: ["com.other", "com.example.app"]) == .proceed)
    }

    @Test func missingAppFailsWithActionableCopy() {
        let decision = CaptureEngine.startDecision(
            screenPermission: .granted, availableDisplays: 1,
            content: .app(bundleID: "com.example.gone"), runningBundleIDs: ["com.other"])
        // Says what happened AND what to do (M6-T3 bar), and names the app.
        guard case .fail(let message) = decision else {
            Issue.record("expected .fail for an unlisted app")
            return
        }
        #expect(message.contains("com.example.gone"))
        #expect(message.contains("Open the app"))
    }

    @Test func stallWatchdogOnlyAttachesForDisplayContent() {
        // Its "user active ⇒ frames expected" premise fails under an app filter (docs/02 §7).
        #expect(CaptureEngine.attachesStallWatchdog(to: .display(.main)))
        #expect(CaptureEngine.attachesStallWatchdog(to: .display(.id(7))))
        #expect(!CaptureEngine.attachesStallWatchdog(to: .app(bundleID: "com.example.app")))
    }
}
