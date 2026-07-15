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

    public init(configuration: CaptureConfiguration, outputURL: URL) throws {
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
        (events, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
    }

    /// Attaches the recorder, begins forwarding/finalizing engine events, and starts capture.
    public func start() async {
        engine.router.attach(recorder)
        let engine = self.engine
        let recorder = self.recorder
        let continuation = self.continuation
        Task {
            var startFailure: String?
            var endReason: EndReason = .userStopped
            for await event in engine.events {
                switch event {
                case .started:
                    continuation.yield(.started)
                case .paused, .resumed, .fileProgress:
                    continuation.yield(event)          // M3 / M2-T5 pass-throughs
                case .failed(let message):
                    startFailure = message
                case .stopped(let reason):
                    endReason = reason
                case .finished:
                    break                              // engine never emits this
                }
            }
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
