import Foundation
import Testing

@testable import RecorderCore

/// The tap's teardown contract (M30-T1). These pin idempotence, which is what makes the single
/// teardown site in `CaptureEngine.cancelWatchdogs()` safe to reach twice — `stop()` calls it, then
/// `terminate()` calls it again a moment later.
///
/// ⚠️ **What no test here can prove:** that a terminated engine actually calls `stop()`. The engine
/// builds its tap internally and needs a live `SCStream` to have one at all, so that claim belongs to
/// the live A/B in G30 (`screenrec-cli record --window … --mute-app … --audit-tap`), not here.
@Suite struct SystemAudioTapTests {

    @Test func aTapThatNeverStartedIsNotRunning() {
        let tap = SystemAudioTap(router: SampleRouter())
        #expect(!tap.isRunning)
    }

    /// `CaptureEngine.deinit` cannot reach `cancelWatchdogs()` (actor isolation), so the tap's own
    /// `deinit` calls `stop()` — which has to be safe on a tap that never started.
    @Test func stoppingATapThatNeverStartedIsSafe() {
        let tap = SystemAudioTap(router: SampleRouter())
        tap.stop()
        tap.stop()
        #expect(!tap.isRunning)
    }

    /// The double call the fix relies on: `stop()` tears down through `cancelWatchdogs()`, and
    /// `terminate()` runs the same path again on its way out.
    @Test func stoppingTwiceLeavesItStopped() {
        let tap = SystemAudioTap(router: SampleRouter())
        for _ in 0..<5 { tap.stop() }
        #expect(!tap.isRunning)
    }

    /// `screenrec-cli`'s `--audit-tap` matches the aggregate device by this name from another module,
    /// where the compiler cannot check it. Renaming the constant should fail here — and the message
    /// says where else to change it — rather than silently turning the audit into a check that can
    /// only ever report "clean".
    @Test func theAggregateDeviceNameIsTheOneTapAuditMatches() {
        #expect(
            SystemAudioTap.aggregateDeviceName == "screenrec system audio",
            "screenrec-cli/TapAudit.swift hard-codes this name — change it there too")
    }
}
