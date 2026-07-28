import AVFoundation
import Foundation
import Testing
@testable import RecorderCore

/// The drain skeleton `ReplayMuxer` and `Exporter` share (M14-T2). Its whole job is the bookkeeping
/// around `requestMediaDataWhenReady`: pump until the producer says stop, mark the input finished,
/// and leave the group **exactly once** — a missed leave deadlocks `group.wait()`, which is how the
/// replay `isSaving` latch wedges every later save.
@Suite struct WriterDrainTests {

    /// Drains `samples` PCM buffers into a real writer and returns how the run went.
    private func drainRun(samples: Int) async throws
        -> (pumpCalls: Int, waited: DispatchTimeoutResult, url: URL)
    {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drain-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let format = makeAudioFormat(sampleRate: 48_000, channels: 1)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "drain-test")
        let calls = Counter()
        var appended = 0
        WriterDrain.drain(into: input, on: queue, group: group) {
            calls.increment()
            guard appended < samples else { return false }
            let pts = CMTime(value: CMTimeValue(appended), timescale: 10)
            let ok = input.append(makeAudioSampleBuffer(format: format, frames: 4_800, pts: pts))
            appended += 1
            return ok
        }
        // Bounded, so a drain that never leaves fails the test instead of hanging it (M15-T1).
        let waited = group.wait(timeout: .now() + 5)
        await writer.finishWriting()
        return (calls.value, waited, url)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    @Test func pumpsUntilTheProducerStopsThenLeavesTheGroup() async throws {
        let run = try await drainRun(samples: 8)
        defer { try? FileManager.default.removeItem(at: run.url) }

        #expect(run.waited == .success, "the group was never left — this is the deadlock")
        // Eight appends plus the call that returned false: a drain that stopped early would
        // silently truncate a replay clip or an export.
        #expect(run.pumpCalls == 9)

        let asset = AVURLAsset(url: run.url)
        let duration = try await asset.load(.duration).seconds
        #expect(duration > 0.7, "the appended samples didn't reach the file")
    }

    @Test func stoppingOnTheFirstPumpStillLeavesTheGroup() async throws {
        // The empty case: nothing to write is a clean end, not a hang.
        let run = try await drainRun(samples: 0)
        defer { try? FileManager.default.removeItem(at: run.url) }

        #expect(run.waited == .success)
        #expect(run.pumpCalls == 1)
    }

    @Test func firstErrorKeepsTheFirstMessage() {
        // Later failures are the fallout of the first, and the surface shows one line (M14-T2).
        let error = FirstError()
        #expect(error.message == nil)
        error.report("the writer refused the video track")
        error.report("and then everything else broke")
        #expect(error.message == "the writer refused the video track")
    }
}
