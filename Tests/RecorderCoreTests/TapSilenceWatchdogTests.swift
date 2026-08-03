import Foundation
import Testing

@testable import RecorderCore

/// The tap silence decision (M27-T4). Every test here is really one question: can it tell a broken
/// tap from a quiet room? The two look identical on the wire — an ungranted tap streams zeros and
/// reports success (docs/07).
@Suite struct TapSilenceWatchdogTests {

    /// A clock the test drives, so no test waits on real seconds.
    private final class Clock: @unchecked Sendable {
        var uptime: TimeInterval = 100
    }

    private func makeWatchdog(
        playing: @escaping @Sendable () -> Bool, clock: Clock, reported: Reported
    ) -> TapSilenceWatchdog {
        TapSilenceWatchdog(
            duration: 5, now: { clock.uptime }, isAnythingPlaying: playing,
            onSilent: { reported.count += 1 })
    }

    private final class Reported: @unchecked Sendable {
        var count = 0
    }

    @Test func reportsWhenSomethingIsPlayingAndTheTapHearsNothing() {
        let clock = Clock(), reported = Reported()
        let watchdog = makeWatchdog(playing: { true }, clock: clock, reported: reported)
        watchdog.note(peak: 0)
        clock.uptime += 6
        watchdog.check()
        #expect(reported.count == 1)
    }

    @Test func staysQuietWhenTheMacIsSimplyQuiet() {
        // The control the whole design turns on: silence with nothing playing is not a fault, and
        // firing here would train the user to ignore the notice.
        let clock = Clock(), reported = Reported()
        let watchdog = makeWatchdog(playing: { false }, clock: clock, reported: reported)
        watchdog.note(peak: 0)
        clock.uptime += 600
        watchdog.check()
        #expect(reported.count == 0)
    }

    @Test func saysNothingBeforeTheRunIsLongEnough() {
        let clock = Clock(), reported = Reported()
        let watchdog = makeWatchdog(playing: { true }, clock: clock, reported: reported)
        watchdog.note(peak: 0)
        clock.uptime += 4                       // under the 5 s run
        watchdog.check()
        #expect(reported.count == 0)
    }

    @Test func audibleAudioClearsTheRun() {
        let clock = Clock(), reported = Reported()
        let watchdog = makeWatchdog(playing: { true }, clock: clock, reported: reported)
        watchdog.note(peak: 0)
        clock.uptime += 4
        watchdog.note(peak: 0.4)                // sound arrived
        clock.uptime += 4                       // 8 s total, but the run restarted
        watchdog.check()
        #expect(reported.count == 0)
    }

    @Test func reportsOncePerOutageRatherThanEverySecond() {
        let clock = Clock(), reported = Reported()
        let watchdog = makeWatchdog(playing: { true }, clock: clock, reported: reported)
        watchdog.note(peak: 0)
        clock.uptime += 6
        for _ in 0..<10 { watchdog.check() }    // a poll every second
        #expect(reported.count == 1)

        // A later outage is a new fault, and worth its own notice.
        watchdog.note(peak: 0.4)
        watchdog.note(peak: 0)
        clock.uptime += 6
        watchdog.check()
        #expect(reported.count == 2)
    }

    @Test func aBufferAtTheNoiseFloorIsStillSilence() {
        // Float dither is not audio. Anything under the floor counts as nothing arriving.
        let clock = Clock(), reported = Reported()
        let watchdog = makeWatchdog(playing: { true }, clock: clock, reported: reported)
        watchdog.note(peak: TapSilenceWatchdog.floor / 2)
        clock.uptime += 6
        watchdog.check()
        #expect(reported.count == 1)
    }
}
