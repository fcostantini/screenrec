import CoreMedia
import Foundation

/// Drives a full recording: it owns a `CaptureEngine` and a `MovieRecorder`, wires the
/// recorder onto the engine's `SampleRouter`, and republishes a single `EngineEvent` stream
/// that adds the `finished(url:reason:droppedFrames:)` the engine alone can't produce (the
/// file is the recorder's to finalize). This is the seam the CLI's `record` and, later, the
/// menu-bar app share so neither re-implements the capture/write/finalize handshake.
///
/// Fail-stop (ADR-007): whatever ends the engine — a user stop or a stream death — is carried
/// through as the `finished` reason, so the outcome is always a playable file plus a cause,
/// or a `failed` if nothing was ever written.
public final class RecordingSession: @unchecked Sendable {
    /// Unified event surface: `started`, forwarded progress/pause events, then exactly one of
    /// `finished` (file finalized) or `failed` (nothing playable), after which it finishes.
    public nonisolated let events: AsyncStream<EngineEvent>
    private nonisolated let continuation: AsyncStream<EngineEvent>.Continuation

    private let engine: CaptureEngine
    private let recorder: MovieRecorder
    /// Guards the output volume; the session owns it because the engine has no idea where the
    /// file lives. Polled for the life of the capture (below).
    private let diskMonitor: DiskSpaceMonitor
    /// Held only so `deinit` can cancel it: dropping a `Task` reference does not cancel it, and
    /// this one keeps `engine` alive through `onLow`, which would also defeat the engine's own
    /// deinit. Written once by `start()`, which cannot race deinit (the caller holds us).
    private var diskTask: Task<Void, Never>?

    /// `diskFloorBytes` overrides the 2 GB free-space floor (docs/02 §7) — the CLI's
    /// `--test-disk-floor` passes an absurd value to trip the guard on demand.
    public init(
        configuration: CaptureConfiguration,
        outputURL: URL,
        diskFloorBytes: Int64? = nil
    ) throws {
        let engine = CaptureEngine(configuration: configuration)
        self.engine = engine
        // A mic device swap mid-recording can't be handled transparently (v1: no hot-reconfig,
        // ADR-007). Stop the stream cleanly so the file finalizes with `.microphoneChanged` as
        // its cause — that reason then flows through the normal `.stopped` → `.finished` path.
        recorder = try MovieRecorder(
            outputURL: outputURL,
            frameRate: configuration.frameRateCap,
            preset: configuration.quality,
            includesMicrophone: configuration.microphone != .none,
            onMicrophoneFormatChange: { Task { await engine.stop(reason: .microphoneChanged) } })
        // Same fail-stop seam, different trigger: run out of room and we finalize what we have
        // rather than let the writer wedge against a full volume. Watches the output
        // DIRECTORY — same volume, but it exists before the file does, and probing a
        // not-yet-created path would return nil forever and quietly disable the guard.
        diskMonitor = DiskSpaceMonitor(
            floorBytes: diskFloorBytes ?? DiskSpaceMonitor.defaultFloorBytes,
            watching: outputURL.deletingLastPathComponent(),
            onLow: { Task { await engine.stop(reason: .diskAlmostFull) } })
        (events, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
    }

    deinit {
        diskTask?.cancel()
    }

    /// Attaches the recorder, begins forwarding/finalizing engine events, and starts capture.
    public func start() async {
        engine.router.attach(recorder)
        let engine = self.engine
        let recorder = self.recorder
        let continuation = self.continuation

        // Poll the disk guard, but only once there is something worth saving: stopping before
        // the first frame throws `noFramesWritten` and yields NO file, instead of ADR-007's
        // playable clip. Waiting on the writer's own state rather than a wall-clock delay
        // removes that race instead of narrowing it — engine start can outlast any fixed sleep
        // (first launch, Bluetooth mic binding), and a thrashing near-full volume is precisely
        // when it does. `recordedDuration` is NaN until the first frame starts the session.
        let diskMonitor = self.diskMonitor
        let diskTask = Task { [recorder] in
            while !Task.isCancelled, recorder.recordedDuration.seconds.isNaN {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(DiskSpaceMonitor.checkInterval)) }
                catch { return }
                diskMonitor.check()
            }
        }
        self.diskTask = diskTask

        Task {
            var startFailure: String?
            var endReason: EndReason = .userStopped
            for await event in engine.events {
                switch event {
                case .started:
                    continuation.yield(.started)
                case .paused, .resumed, .microphoneLost, .fileProgress:
                    continuation.yield(event)          // M3 / M2-T5 pass-throughs
                case .failed(let message):
                    startFailure = message
                case .stopped(let reason):
                    endReason = reason
                case .finished:
                    break                              // engine never emits this
                }
            }
            diskTask.cancel()
            engine.router.detach(recorder)

            if let startFailure {
                recorder.cancel()
                continuation.yield(.failed(message: startFailure))
            } else {
                do {
                    let url = try await recorder.finish()
                    continuation.yield(.finished(
                        url: url, reason: endReason, droppedFrames: recorder.droppedFrameCount))
                } catch {
                    continuation.yield(.failed(message:
                        "Couldn't finalize the recording: \(error.localizedDescription)"))
                }
            }
            continuation.finish()
        }
        await engine.start()
    }

    /// Pause the recording: the output timeline stops advancing and the paused span is removed
    /// (docs/02 §5). The stream keeps running; resume with `resume()`. The engine's `.paused`
    /// event fires only if the recorder actually froze the timeline — pausing in the startup
    /// window before the first frame is a no-op, and must not emit a pause that didn't happen.
    public func pause() async {
        guard recorder.pause() else { return }
        await engine.pause()
    }

    /// Resume a paused recording; the timeline re-anchors on the next complete video frame.
    /// `.resumed` fires only if the recorder was actually paused.
    public func resume() async {
        guard recorder.resume() else { return }
        await engine.resume()
    }

    /// Clean, user-initiated stop; the file is finalized and a `finished` event follows.
    public func stop() async {
        await engine.stop()
    }

    /// Media duration written so far, for a progress ticker; `.invalid` before capture starts.
    public var recordedDuration: CMTime { recorder.recordedDuration }
}
