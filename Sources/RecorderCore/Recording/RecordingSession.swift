import CoreMedia
import Foundation

/// Drives a full recording: owns a `CaptureEngine` and a `MovieRecorder`, wires the recorder
/// onto the engine's `SampleRouter`, and republishes one `EngineEvent` stream that adds the
/// `finished(url:reason:droppedFrames:)` the engine can't produce. Shared seam for the CLI's
/// `record` and the menu-bar app.
///
/// Fail-stop (ADR-007): whatever ends the engine is carried through as the `finished` reason,
/// so the outcome is a playable file plus a cause, or `failed` if nothing was written.
public final class RecordingSession: @unchecked Sendable {
    /// Unified event surface: `started`, forwarded progress/pause events, then exactly one of
    /// `finished` (file finalized) or `failed` (nothing playable), after which it finishes.
    public nonisolated let events: AsyncStream<EngineEvent>
    private nonisolated let continuation: AsyncStream<EngineEvent>.Continuation

    private let engine: CaptureEngine
    private let recorder: MovieRecorder
    /// The final `.mov` the caller asked for; the writer works on its `.partial` companion.
    private let finalURL: URL
    /// What the sentinel decided the file's fate was; set from its queue, read at teardown.
    private enum FileFate {
        case deleted
        /// Moved somewhere the rename-back failed from; the fragments there are intact.
        case strandedAt(String)
    }
    private let fileFate = LockedBox<FileFate>()
    /// Written from the capture queue (`onDidBeginWriting`), cancelled from the event-loop
    /// task — hence the lock. `sentinelTornDown` latches teardown so a late-firing attach
    /// can't install a sentinel nobody will ever cancel (it would rename the finished
    /// movie back to `.partial`).
    private let sentinelLock = NSLock()
    private var sentinel: RecordingFileSentinel?
    private var sentinelTornDown = false
    /// Guards the output volume; owned here because the engine doesn't know where the file lives.
    private let diskMonitor: DiskSpaceMonitor
    /// Held so `deinit` can cancel it: dropping a `Task` reference does not cancel it, and this
    /// one keeps `engine` alive through `onLow`. Written once by `start()`, which can't race
    /// deinit (the caller holds us).
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
        finalURL = outputURL
        // A mic swap mid-recording can't be handled transparently (ADR-007): stop cleanly so the
        // file finalizes with `.microphoneChanged`, flowing through the normal `.stopped` path.
        recorder = try MovieRecorder(
            outputURL: OutputLocation.partialURL(for: outputURL),
            frameRate: configuration.frameRateCap,
            preset: configuration.quality,
            includesMicrophone: configuration.microphone != .none,
            // ⚠️ `[weak engine]` is required: engine → router → recorder → closure, so a strong
            // capture closes the cycle and makes `CaptureEngine.deinit` unreachable.
            onMicrophoneFormatChange: { [weak engine] in
                Task { await engine?.stop(reason: .microphoneChanged) }
            },
            // The writer can never begin (unwritable output folder, 02 §2). Stop capture so the
            // event loop below ends and fails the session — nothing playable exists, so this is
            // `.failed`, not a `.finished` reason. Same `[weak engine]` cycle-break as above.
            onWriteFailure: { [weak engine] in
                Task { await engine?.stop() }
            })
        // Watches the output DIRECTORY, not the file: same volume, but it exists before the file
        // does — probing a not-yet-created path returns nil forever and disables the guard.
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
        // Set before capture starts so the write is visible to the capture queue that fires it.
        recorder.onDidBeginWriting = { [weak self] in self?.attachSentinel() }
        engine.router.attach(recorder)
        let engine = self.engine
        let recorder = self.recorder
        let continuation = self.continuation

        // Poll the disk guard only once there is something worth saving: stopping before the
        // first frame throws `noFramesWritten` and yields no file at all. Gating on the writer's
        // state rather than a fixed delay — engine start can outlast any sleep.
        let diskMonitor = self.diskMonitor
        let diskTask = pollingTask(every: DiskSpaceMonitor.checkInterval) {
            guard recorder.hasStartedSession else { return }
            diskMonitor.check()
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
                    continuation.yield(event)
                case .failed(let message):
                    startFailure = message
                case .stopped(let reason):
                    endReason = reason
                case .finished, .recordingFileRestored:
                    break                              // session-emitted; engine never sends them
                }
            }
            diskTask.cancel()
            engine.router.detach(recorder)
            // Before finalize's own rename, or the sentinel would fight it.
            self.cancelSentinel()

            if let startFailure {
                recorder.cancel()
                continuation.yield(.failed(message: startFailure))
            } else if let fate = fileFate.value {
                switch fate {
                case .deleted:
                    // The partial was unlinked mid-recording; the writer has been feeding a
                    // doomed inode ever since. Unsalvageable (no relink API) — say so plainly.
                    recorder.cancel()
                    continuation.yield(.failed(message:
                        "The recording file was deleted while recording, so the video couldn't be saved."))
                case .strandedAt(let path):
                    // The file is intact wherever it went, and the writer's fd still points at
                    // it — finalize there and report a save, never a loss.
                    do {
                        _ = try await recorder.finish()
                        var url = URL(fileURLWithPath: path)
                        if url.pathExtension == "partial",
                           let final = try? OutputLocation.finalizePartial(url) {
                            url = final
                        }
                        continuation.yield(.finished(
                            url: url, reason: endReason, droppedFrames: recorder.droppedFrameCount))
                    } catch {
                        continuation.yield(.failed(message:
                            "Couldn't finalize the recording: \(error.localizedDescription)"))
                    }
                }
            } else if recorder.failedToBeginWriting {
                // The writer never began (unwritable output, 02 §2). Cancel to drop the O_EXCL
                // placeholder; fail with the folder named — there is nothing to finalize.
                recorder.cancel()
                let folder = recorder.outputURL.deletingLastPathComponent().lastPathComponent
                continuation.yield(.failed(message:
                    "Couldn't write the recording to \"\(folder)\". Choose another folder."))
            } else {
                do {
                    let partial = try await recorder.finish()
                    // Rename failure after a successful finish is NOT a lost recording — the
                    // complete movie sits at the partial path. Report it saved there; the next
                    // launch's recovery sweep renames it.
                    let url = (try? OutputLocation.finalizePartial(partial)) ?? partial
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

    /// Guards the partial. Runs from `onDidBeginWriting` — the one moment that's provably
    /// after `startWriting()` created the real file. Attaching any earlier (e.g. on the
    /// engine's `.started`, which races the writer) can open the reservation placeholder's
    /// inode, which `beginWriting` replaces — a false `.deleted` on a healthy start.
    /// `movedAndUnrestorable` is treated as deleted: finalize could no longer find the file,
    /// so failing now with the truth beats failing later opaquely.
    private func attachSentinel() {
        let engine = self.engine
        let continuation = self.continuation
        let fileFate = self.fileFate
        let sentinel = RecordingFileSentinel(url: recorder.outputURL) { incident in
            switch incident {
            case .movedAndRestored:
                continuation.yield(.recordingFileRestored)
            case .deleted:
                fileFate.set(.deleted)
                Task { await engine.stop() }
            case .movedAndUnrestorable(let path):
                fileFate.set(.strandedAt(path))
                Task { await engine.stop() }
            }
        }
        sentinelLock.lock()
        if sentinelTornDown {
            sentinelLock.unlock()
            sentinel?.cancel()      // teardown already ran; nobody would ever cancel this one
            return
        }
        self.sentinel = sentinel
        sentinelLock.unlock()
    }

    private func cancelSentinel() {
        sentinelLock.lock()
        sentinelTornDown = true
        let sentinel = self.sentinel
        self.sentinel = nil
        sentinelLock.unlock()
        // Waits out an in-flight handler: finalize's rename must not race a rename-back.
        sentinel?.cancelAndWait()
    }

    /// Pause the recording: the output timeline stops advancing and the paused span is removed
    /// (docs/02 §5). The stream keeps running; resume with `resume()`. `.paused` fires only if
    /// the recorder actually froze the timeline — pausing before the first frame is a no-op.
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
        // Disarm before teardown (see `pollingTask`): `engine.stop()` suspends for seconds while
        // the engine stays `.running`, so a disk check landing in that window would report
        // `.diskAlmostFull` instead of `.userStopped`.
        diskTask?.cancel()
        await engine.stop()
    }

    /// The stream's fan-out, so replay consumers can share a recording's capture
    /// (docs/01's key property — the armed replay pipeline attaches here).
    public var router: SampleRouter { engine.router }

    /// Media duration written so far, for a progress ticker; `.invalid` before capture starts.
    public var recordedDuration: CMTime { recorder.recordedDuration }

    /// Whether the writer has a session yet — i.e. there is something worth saving.
    public var hasStartedSession: Bool { recorder.hasStartedSession }
}
