import CoreGraphics
import Testing
@testable import RecorderCore

/// M16-T6. The point of the test is the *partial* passes: "you turned it off" and "it's broken"
/// must never read alike, and a condition M16-T4 already named keeps T4's words.
@Suite struct CaptureSelfTestTests {

    private static let display = CGSize(width: 4112, height: 2570)
    /// Room tone on either mic clears T4's floor comfortably (docs/07).
    private static let roomTone: Float = 0.0006

    private func verdict(
        video: CGSize? = CaptureSelfTestTests.display,
        stereo: Bool = true, mono: Bool = true, systemAudioRequested: Bool = true,
        microphone: MicrophoneExpectation = .expected(name: "MacBook Pro Microphone"),
        peak: Float = CaptureSelfTestTests.roomTone
    ) -> CaptureSelfTestResult {
        CaptureSelfTest.verdict(
            videoPixelSize: video, hasStereoAudioTrack: stereo, hasMonoAudioTrack: mono,
            systemAudioRequested: systemAudioRequested, microphone: microphone,
            microphonePeak: peak)
    }

    @Test func everythingWorkingNamesTheDeviceAndTheSize() {
        let result = verdict()
        #expect(result.screen == .ok("4112 × 2570"))
        #expect(result.systemAudio == .ok(nil))
        #expect(result.microphone == .ok("MacBook Pro Microphone"))
    }

    @Test func aDeliberateAbsenceIsNotAFailure() {
        // Both are the user's own choice (M16-T3's off switch, and a None mic), so neither may
        // read as a problem.
        let result = verdict(
            stereo: false, mono: false, systemAudioRequested: false, microphone: .notSelected)
        #expect(result.systemAudio == .skipped("turned off"))
        #expect(result.microphone == .skipped("not selected"))
        #expect(result.screen == .ok("4112 × 2570"))
    }

    @Test func aSilentMicrophoneKeepsTheWordsM16T4Chose() {
        let result = verdict(peak: 0)
        #expect(result.microphone == .warning("silent — check that it isn't muted"))
    }

    @Test func aQuietRoomIsNotASilentMicrophone() {
        // The whole reason the floor was measured: -90 dBFS sits far below real room tone.
        #expect(verdict(peak: Self.roomTone).microphone == .ok("MacBook Pro Microphone"))
        #expect(verdict(peak: MicrophoneSilence.floor).microphone == .ok("MacBook Pro Microphone"))
    }

    @Test func anAbsentPickIsReportedByName() {
        let result = verdict(mono: false, microphone: .unavailable(name: "AirPods Pro"))
        #expect(result.microphone == .warning("AirPods Pro isn't connected"))
    }

    @Test func aWantedSourceThatRecordedNothingIsAWarningNotASkip() {
        #expect(verdict(stereo: false).systemAudio == .warning("nothing was captured"))
        #expect(verdict(mono: false).microphone
            == .warning("MacBook Pro Microphone recorded nothing"))
    }

    @Test func noVideoIsTheOneRealFailure() {
        let result = verdict(video: nil)
        #expect(result.screen == .failed("nothing was recorded"))
        // A zero-size track is the same thing as none.
        #expect(verdict(video: .zero).screen == .failed("nothing was recorded"))
    }
}
