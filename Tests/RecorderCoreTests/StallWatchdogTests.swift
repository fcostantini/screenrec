import CoreMedia
import Foundation
import Testing
@testable import RecorderCore

/// Clock, idle probe and `check()` are all injected/driven, so these run in zero real time and
/// need no real input.
@Suite struct StallWatchdogTests {

    /// Hand-cranked clock + idle probe. Lock-guarded: in production the watchdog reads these
    /// under its own lock from a capture queue.
    private final class TestEnvironment: @unchecked Sendable {
        private let lock = NSLock()
        private var time: TimeInterval = 0
        private var idle: TimeInterval = 0
        var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return time }
        var idleSeconds: TimeInterval { lock.lock(); defer { lock.unlock() }; return idle }
        /// Advances time. `userActive` keeps the idle probe pinned near zero (someone is typing);
        /// otherwise idle advances alongside the clock (nobody is there).
        func advance(_ seconds: TimeInterval, userActive: Bool) {
            lock.lock()
            time += seconds
            idle = userActive ? 0 : idle + seconds
            lock.unlock()
        }
    }

    private static let timeout: TimeInterval = 30

    private func makeWatchdog(
        _ environment: TestEnvironment, onStall: @escaping @Sendable (TimeInterval) -> Void
    ) -> StallWatchdog {
        StallWatchdog(
            timeout: Self.timeout,
            now: { environment.now },
            secondsSinceUserInput: { environment.idleSeconds },
            onStall: onStall)
    }

    @Test func reportsOnceWhenVideoStopsWhileTheUserIsActive() async {
        let environment = TestEnvironment()
        // Exactly one line per episode — a wedged stream would otherwise spam every poll.
        await confirmation("stall reported exactly once") { stalled in
            let watchdog = makeWatchdog(environment) { _ in stalled() }
            watchdog.consume(makeMarkerBuffer(), type: .screen)
            environment.advance(Self.timeout + 1, userActive: true)
            watchdog.check()
            watchdog.check()
            watchdog.check()
        }
    }

    @Test func silentWhenNobodyIsUsingTheMachine() async {
        let environment = TestEnvironment()
        // THE central case: SCK is frame-on-change, so an idle user's static screen delivers no
        // frames for minutes and that is entirely healthy (G2 §3.4). Reporting it would make the
        // watchdog cry wolf on every coffee break.
        await confirmation("no stall when the user is idle", expectedCount: 0) { stalled in
            let watchdog = makeWatchdog(environment) { _ in stalled() }
            watchdog.consume(makeMarkerBuffer(), type: .screen)
            environment.advance(Self.timeout * 10, userActive: false)
            watchdog.check()
        }
    }

    @Test func silentWhenTheUserTouchedNothingSinceLeaving() async {
        // The case that caught a real bug, and that the two extremes above structurally CANNOT
        // express: input once, then leave. A lone modifier key changes nothing on screen, so it
        // yields no frame — and the earlier condition (`idle < silence`, i.e. "any input since
        // the last frame") then stayed true forever afterwards, reporting a stall on every poll
        // of an untouched machine. Only *recent* activity may count.
        let environment = TestEnvironment()
        await confirmation("no stall after the user walked away", expectedCount: 0) { stalled in
            let watchdog = makeWatchdog(environment) { _ in stalled() }
            watchdog.consume(makeMarkerBuffer(), type: .screen)
            environment.advance(1, userActive: true)              // one inert keypress…
            environment.advance(Self.timeout * 10, userActive: false)  // …then a coffee break
            watchdog.check()
        }
    }

    @Test func silentBeforeTheTimeout() async {
        let environment = TestEnvironment()
        await confirmation("no stall before the timeout", expectedCount: 0) { stalled in
            let watchdog = makeWatchdog(environment) { _ in stalled() }
            watchdog.consume(makeMarkerBuffer(), type: .screen)
            environment.advance(Self.timeout - 1, userActive: true)
            watchdog.check()
        }
    }

    @Test func silentWhileFramesKeepArriving() async {
        let environment = TestEnvironment()
        await confirmation("no stall while the stream is alive", expectedCount: 0) { stalled in
            let watchdog = makeWatchdog(environment) { _ in stalled() }
            for _ in 0..<10 {
                watchdog.consume(makeMarkerBuffer(), type: .screen)
                environment.advance(Self.timeout - 1, userActive: true)
                watchdog.check()
            }
        }
    }

    @Test func silentBeforeTheFirstFrameEverArrives() async {
        let environment = TestEnvironment()
        // A capture that never started isn't a stall; startup failures surface elsewhere.
        await confirmation("no stall before the first frame", expectedCount: 0) { stalled in
            let watchdog = makeWatchdog(environment) { _ in stalled() }
            environment.advance(Self.timeout * 5, userActive: true)
            watchdog.check()
        }
    }

    @Test func reArmsSoASecondStallIsAlsoReported() async {
        let environment = TestEnvironment()
        // Unlike a mic disconnect (permanent — 02 §4), a stall can pass. A recovered-then-wedged
        // stream is two separate incidents and worth two lines.
        await confirmation("both stall episodes reported", expectedCount: 2) { stalled in
            let watchdog = makeWatchdog(environment) { _ in stalled() }
            watchdog.consume(makeMarkerBuffer(), type: .screen)
            environment.advance(Self.timeout + 1, userActive: true)
            watchdog.check()                                  // episode 1
            watchdog.consume(makeMarkerBuffer(), type: .screen)     // stream recovers → re-arm
            environment.advance(Self.timeout + 1, userActive: true)
            watchdog.check()                                  // episode 2
        }
    }

    @Test func onlyVideoFramesCountAsProofOfLife() async {
        let environment = TestEnvironment()
        // Audio keeps flowing at ~40/s through a video stall, so counting it as a heartbeat
        // would mask exactly the wedged stream this exists to catch.
        await confirmation("audio does not mask a video stall") { stalled in
            let watchdog = makeWatchdog(environment) { _ in stalled() }
            watchdog.consume(makeMarkerBuffer(), type: .screen)
            environment.advance(Self.timeout + 1, userActive: true)
            watchdog.consume(makeMarkerBuffer(), type: .systemAudio)
            watchdog.consume(makeMarkerBuffer(), type: .microphone)
            watchdog.check()
        }
    }

    /// Captures the reported figure across the @Sendable callback boundary.
    private final class Recorded: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TimeInterval?
        func set(_ seconds: TimeInterval) { lock.lock(); value = seconds; lock.unlock() }
        var seconds: TimeInterval? { lock.lock(); defer { lock.unlock() }; return value }
    }

    @Test func reportsTheMeasuredSilenceNotTheTimeout() {
        let environment = TestEnvironment()
        // The log line's whole value is "how long was it wedged" — a constant would be useless.
        let recorded = Recorded()
        let watchdog = makeWatchdog(environment) { recorded.set($0) }
        watchdog.consume(makeMarkerBuffer(), type: .screen)
        environment.advance(90, userActive: true)
        watchdog.check()
        #expect(recorded.seconds == 90)
    }
}
