import CoreMedia
import Foundation
import Testing
@testable import RecorderCore

/// M16-T4. The levels here are the ones measured on real hardware (docs/07), not invented: the
/// point of the suite is that a *quiet room* never trips the detector while a *muted* mic always
/// does, so the room-tone cases are the load-bearing ones.
@Suite struct MicrophoneSilenceWatchdogTests {

    /// dBFS as the linear peak amplitude a buffer would carry.
    private static func amplitude(dBFS: Float) -> Float { pow(10, dBFS / 20) }

    /// `ResampledMicInput`'s fixed output — 48 kHz mono Float32 — which is the only format the
    /// detector ever sees (anything else reads as unreadable and is skipped).
    private static let format = makeAudioFormat(
        sampleRate: 48_000, channels: 1, planarFloat32: true)

    private func buffer(dBFS: Float?, at seconds: Double) -> CMSampleBuffer {
        makeAudioSampleBuffer(
            format: Self.format, frames: 480,
            pts: CMTime(seconds: seconds, preferredTimescale: 600),
            amplitude: dBFS.map { Self.amplitude(dBFS: $0) } ?? 0)
    }

    /// Drives a watchdog over `seconds` of buffers at one level, checking every second.
    private func run(
        dBFS: Float?, seconds: Int, silenceDuration: TimeInterval = MicrophoneSilence.duration
    ) -> (silent: Int, audible: Int) {
        var clock: TimeInterval = 0
        let silent = Counter(), audible = Counter()
        let watchdog = MicrophoneSilenceWatchdog(
            duration: silenceDuration, now: { clock },
            onSilent: { silent.bump() }, onAudible: { audible.bump() })
        for _ in 0..<seconds {
            watchdog.consume(buffer(dBFS: dBFS, at: clock), type: .microphone)
            watchdog.check()
            clock += 1
        }
        return (silent.value, audible.value)
    }

    @Test func aMutedMicrophoneIsReportedExactlyOnce() {
        // Measured: a muted device delivers exact digital zeros, every window, -∞ dBFS.
        let result = run(dBFS: nil, seconds: 30)
        #expect(result.silent == 1)
        #expect(result.audible == 0)
    }

    @Test(arguments: [Float(-78.9), -65.5, -45.5, -42.7, -20, -6])
    func realRoomToneNeverTripsIt(dBFS: Float) {
        // -78.9 and -65.5 are the AirPods' quietest and median windows in a quiet room; -45.5 and
        // -42.7 the built-in mic's. If any of these fire, the feature is a nuisance, not a notice.
        let result = run(dBFS: dBFS, seconds: 60)
        #expect(result.silent == 0)
        #expect(result.audible == 0)
    }

    @Test func aBriefStartupRunOfZerosIsNotSilence() {
        // Measured: SCK delivers ~1 s of exact zeros while a Bluetooth route spins up. The run
        // length is what protects against it — never "this buffer is quiet".
        var clock: TimeInterval = 0
        let silent = Counter(), audible = Counter()
        let watchdog = MicrophoneSilenceWatchdog(
            now: { clock }, onSilent: { silent.bump() }, onAudible: { audible.bump() })
        for _ in 0..<2 {                       // 2 s of digital zeros
            watchdog.consume(buffer(dBFS: nil, at: clock), type: .microphone)
            watchdog.check()
            clock += 1
        }
        for _ in 0..<30 {                      // then a normal quiet room
            watchdog.consume(buffer(dBFS: -65.5, at: clock), type: .microphone)
            watchdog.check()
            clock += 1
        }
        #expect(silent.value == 0)
        #expect(audible.value == 0)
    }

    @Test func soundReturningPairsTheNoticeWithARecovery() {
        var clock: TimeInterval = 0
        let silent = Counter(), audible = Counter()
        let watchdog = MicrophoneSilenceWatchdog(
            now: { clock }, onSilent: { silent.bump() }, onAudible: { audible.bump() })

        for _ in 0..<15 {                      // muted long enough to report
            watchdog.consume(buffer(dBFS: nil, at: clock), type: .microphone)
            watchdog.check()
            clock += 1
        }
        #expect(silent.value == 1)

        watchdog.consume(buffer(dBFS: -50, at: clock), type: .microphone)   // unmuted
        #expect(audible.value == 1)

        for _ in 0..<15 {                      // muted again — a second run reports again
            clock += 1
            watchdog.consume(buffer(dBFS: nil, at: clock), type: .microphone)
            watchdog.check()
        }
        #expect(silent.value == 2)
        #expect(audible.value == 1)
    }

    @Test func onlyMicrophoneBuffersAreJudged() {
        // System audio is silent whenever nothing is playing; reporting that would train the user
        // to ignore the notice (docs/03 M16-T4 ruling).
        var clock: TimeInterval = 0
        let silent = Counter()
        let watchdog = MicrophoneSilenceWatchdog(
            now: { clock }, onSilent: { silent.bump() }, onAudible: {})
        for _ in 0..<30 {
            watchdog.consume(buffer(dBFS: nil, at: clock), type: .systemAudio)
            watchdog.check()
            clock += 1
        }
        #expect(silent.value == 0)
    }

    @Test func peakReadsTheLoudestSampleNotTheAverage() {
        #expect(MicrophoneSilenceWatchdog.peakAmplitude(of: buffer(dBFS: nil, at: 0)) == 0)
        let loud = MicrophoneSilenceWatchdog.peakAmplitude(of: buffer(dBFS: -20, at: 0))
        #expect(loud != nil)
        #expect(abs((loud ?? 0) - Self.amplitude(dBFS: -20)) < 0.0001)
    }

    @Test func theFloorSitsBelowEveryMeasuredRoomToneAndAboveNothing() {
        // The margin this whole task turns on: -90 dBFS is ~11 dB under the quietest real window
        // measured (AirPods, -78.9) and above digital zero.
        #expect(MicrophoneSilence.floor < Self.amplitude(dBFS: -78.9))
        #expect(MicrophoneSilence.floor > 0)
        #expect(MicrophoneSilence.floorDBFS == -90)
    }
}

/// Counts handler fires across the watchdog's lock without importing a whole spy type.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
