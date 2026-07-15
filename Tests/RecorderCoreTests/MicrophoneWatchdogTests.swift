import CoreMedia
import Foundation
import Testing
@testable import RecorderCore

/// The watchdog's clock and `check()` are both injected/driven, so these run in zero real time.
@Suite struct MicrophoneWatchdogTests {

    /// Hand-cranked monotonic clock. Lock-guarded because the watchdog reads it under its own
    /// lock from what is, in production, a capture queue.
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TimeInterval = 0
        var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
    }

    /// A minimal empty CMSampleBuffer — the watchdog only inspects the `type` it is routed as.
    private static func markerBuffer() -> CMSampleBuffer {
        var buffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: nil,
            sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer)
        precondition(status == noErr, "CMSampleBufferCreate failed: \(status)")
        return buffer!
    }

    private static let timeout: TimeInterval = 3

    @Test func firesOnceWhenMicrophoneStopsDelivering() async {
        let clock = TestClock()
        // Exactly one event: a disconnect is permanent (verified — a reconnected device never
        // resumes), so repeated checks must not re-fire.
        await confirmation("microphone loss reported exactly once") { lost in
            let watchdog = MicrophoneWatchdog(
                timeout: Self.timeout, now: { clock.now }, onLoss: { lost() })
            watchdog.consume(Self.markerBuffer(), type: .microphone)  // mic is alive…
            clock.advance(Self.timeout + 1)                           // …then it goes away
            watchdog.check()
            watchdog.check()
            watchdog.check()
        }
    }

    @Test func doesNotFireWhileBuffersKeepArriving() async {
        let clock = TestClock()
        await confirmation("no loss while the mic is delivering", expectedCount: 0) { lost in
            let watchdog = MicrophoneWatchdog(
                timeout: Self.timeout, now: { clock.now }, onLoss: { lost() })
            // Heartbeats keep the gap under the timeout across a span far longer than it.
            for _ in 0..<10 {
                watchdog.consume(Self.markerBuffer(), type: .microphone)
                clock.advance(Self.timeout - 1)
                watchdog.check()
            }
        }
    }

    @Test func doesNotFireBeforeTheTimeoutElapses() async {
        let clock = TestClock()
        await confirmation("no loss before the timeout", expectedCount: 0) { lost in
            let watchdog = MicrophoneWatchdog(
                timeout: Self.timeout, now: { clock.now }, onLoss: { lost() })
            watchdog.consume(Self.markerBuffer(), type: .microphone)
            clock.advance(Self.timeout - 0.01)
            watchdog.check()
        }
    }

    @Test func doesNotFireWhenMicrophoneNeverDelivered() async {
        let clock = TestClock()
        // A mic that never produced a buffer was never *lost* — it never worked. MovieRecorder's
        // startup grace owns that case; reporting a disconnect here would be a lie.
        await confirmation("no loss for a mic that never delivered", expectedCount: 0) { lost in
            let watchdog = MicrophoneWatchdog(
                timeout: Self.timeout, now: { clock.now }, onLoss: { lost() })
            clock.advance(Self.timeout * 10)
            watchdog.check()
        }
    }

    @Test func onlyMicrophoneBuffersCountAsHeartbeats() async {
        let clock = TestClock()
        // The `type == .microphone` filter is the load-bearing line: screen and system-audio
        // buffers keep flowing after the mic disconnects, so if they counted as heartbeats the
        // loss would never be reported and the user would record silence unwarned.
        await confirmation("other sources don't mask a dead mic") { lost in
            let watchdog = MicrophoneWatchdog(
                timeout: Self.timeout, now: { clock.now }, onLoss: { lost() })
            watchdog.consume(Self.markerBuffer(), type: .microphone)
            clock.advance(Self.timeout + 1)
            watchdog.consume(Self.markerBuffer(), type: .systemAudio)
            watchdog.consume(Self.markerBuffer(), type: .screen)
            watchdog.check()
        }
    }
}
