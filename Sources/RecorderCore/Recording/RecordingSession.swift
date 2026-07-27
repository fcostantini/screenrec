import CoreMedia
import Foundation
import os

/// Drives a full recording: owns a `CaptureEngine` and a `MovieRecorder`, wires the recorder
/// onto the engine's `SampleRouter`, and republishes one `EngineEvent` stream that adds the
/// `finished(url:reason:droppedFrames:)` the engine can't produce. Shared seam for the CLI's
/// `record` and the menu-bar app.
///
/// Fail-stop (ADR-007): whatever ends the engine is carried through as the `finished` reason,
/// so the outcome is a playable file plus a cause, or `failed` if nothing was written.
public final class RecordingSession: @unchecked Sendable {
    private static let log = Logger(subsystem: "dev.fcostantini.screenrec", category: "recording")
    /// A finish that threw leaves a `.partial` on disk (fragmented, playable) that the next
    /// launch's recovery sweep renames — so point there, not at an opaque NSError.
    static let finalizeFailureMessage =
        "Couldn't finish saving the recording. A recovered copy may appear the next time you open ScreenRec."

    /// Logs the raw error (opaque to the user) and yields a plain `.failed` with `message`.
    private static func finalizeFailed(
        _ error: Error, message: String, on continuation: AsyncStream<EngineEvent>.Continuation
    ) {
        log.error("finalize failed: \(error.localizedDescription, privacy: .public)")
        continuation.yield(.failed(message: message))
    }

    /// The decided fate of a finished recording's file — the pure output of `finalizePlan`, run by
    /// `executeFinalize`. One case per branch, and the priority they're chosen in is what a lost
    /// take turns on, so it's unit-tested exhaustively (M13-T3).
    enum FinalizePlan: Equatable {
        /// The user threw the take away: remove the file everywhere it might be, finalize nothing.
        case discard(strandedPath: String?)
        /// The recording never really started; nothing playable exists.
        case failToStart(message: String)
        /// The partial was unlinked mid-recording — unsalvageable (no relink API).
        case failDeleted
        /// The file was moved intact and the writer's fd still points at it — finalize there.
        case finalizeStranded(path: String, reason: EndReason)
        /// The writer never began (unwritable output folder, 02 §2).
        case failWriteNeverBegan
        /// The ordinary path: finish the writer and finalize the partial.
        case finalizeNormal(reason: EndReason)
    }

    /// Decides a finished recording's fate from the end-of-loop state. Pure, so the priority is
    /// exhaustively testable: a **discard** wins over everything, then a **start failure**, then the
    /// sentinel's **fate** (deleted/stranded), then a writer that **never began**, else the normal
    /// finish. Side effects (cancel/finish/remove) belong to `executeFinalize`.
    static func finalizePlan(
        discardRequested: Bool, startFailure: String?, fate: FileFate?,
        failedToBeginWriting: Bool, endReason: EndReason
    ) -> FinalizePlan {
        if discardRequested {
            if case .strandedAt(let path) = fate { return .discard(strandedPath: path) }
            return .discard(strandedPath: nil)
        }
        if let startFailure { return .failToStart(message: startFailure) }
        switch fate {
        case .deleted: return .failDeleted
        case .strandedAt(let path): return .finalizeStranded(path: path, reason: endReason)
        case nil: break
        }
        if failedToBeginWriting { return .failWriteNeverBegan }
        return .finalizeNormal(reason: endReason)
    }

    static let deletedMessage =
        "The recording file was deleted while recording, so the video couldn't be saved."
    static func writeNeverBeganMessage(folder: String) -> String {
        "Couldn't write the recording to \"\(folder)\". Choose another folder."
    }
    static func strandedFinalizeFailedMessage(path: String) -> String {
        "Couldn't finish saving the recording. The file is at \(path)."
    }

    /// Unified event surface: `started`, forwarded progress/pause events, then exactly one of
    /// `finished` (file finalized) or `failed` (nothing playable), after which it finishes.
    public nonisolated let events: AsyncStream<EngineEvent>
    private nonisolated let continuation: AsyncStream<EngineEvent>.Continuation

    private let engine: CaptureEngine
    private let recorder: MovieRecorder
    /// The final `.mov` the caller asked for; the writer works on its `.partial` companion.
    private let finalURL: URL
    /// What the sentinel decided the file's fate was; set from its queue, read at teardown.
    /// Internal (not private) so `finalizePlan` can be fed it in tests (M13-T3).
    enum FileFate {
        case deleted
        /// Moved somewhere the rename-back failed from; the fragments there are intact.
        case strandedAt(String)
    }
    private let fileFate = LockedBox<FileFate>()
    /// Set by `discard()` before it stops the engine; read by the event-loop task once the stream
    /// ends. When true, the recording is cancelled (file removed) rather than finalized.
    private let discardRequested = LockedBox<Bool>()
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
        let engine = CaptureEngine(configuration: configuration, purpose: .recording)
        self.engine = engine
        finalURL = outputURL
        recorder = try MovieRecorder(
            outputURL: OutputLocation.partialURL(for: outputURL),
            frameRate: configuration.frameRateCap,
            preset: configuration.quality,
            includesMicrophone: configuration.microphone != .none,
            includesSystemAudio: configuration.capturesSystemAudio,
            // The writer can never begin (unwritable output folder, 02 §2). Stop capture so the
            // event loop below ends and fails the session — nothing playable exists, so this is
            // `.failed`, not a `.finished` reason.
            // ⚠️ `[weak engine]` is required: engine → router → recorder → closure, so a strong
            // capture closes the cycle and makes `CaptureEngine.deinit` unreachable.
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
        // A wanted mic that never delivered → tell the caller (M13-T4). Republished as a
        // session-emitted event, like `.discarded`.
        recorder.onMicrophoneDroppedAtStart = { [weak self] in
            self?.continuation.yield(.microphoneDroppedAtStart)
        }
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
                case .paused, .resumed, .microphoneLost, .microphoneRecovered:
                    continuation.yield(event)
                case .failed(let message):
                    startFailure = message
                case .stopped(let reason):
                    endReason = reason
                case .finished, .recordingFileRestored, .discarded, .microphoneDroppedAtStart:
                    break                              // session-emitted; engine never sends them
                }
            }
            diskTask.cancel()
            engine.router.detach(recorder)
            // Before finalize's own rename, or the sentinel would fight it.
            self.cancelSentinel()

            let plan = Self.finalizePlan(
                discardRequested: discardRequested.value == true,
                startFailure: startFailure, fate: fileFate.value,
                failedToBeginWriting: recorder.failedToBeginWriting, endReason: endReason)
            await executeFinalize(plan)
            continuation.finish()
        }
        await engine.start()
    }

    /// Runs a `FinalizePlan`'s side effects and yields exactly one terminal event. The branch was
    /// chosen by the pure `finalizePlan`; this does the mechanical cancel/finish/remove and maps a
    /// `finish()` success/failure to `finished`/`failed`.
    private func executeFinalize(_ plan: FinalizePlan) async {
        switch plan {
        case .discard(let strandedPath):
            // Never finalize; make sure the file is gone in every writer state. `cancel()` removes
            // the `.partial` only while `.writing`; a `.failed` writer, or a file moved out from
            // under us, would otherwise survive for the launch recovery sweep to resurrect.
            recorder.cancel()
            try? FileManager.default.removeItem(at: recorder.outputURL)
            if let strandedPath { try? FileManager.default.removeItem(atPath: strandedPath) }
            continuation.yield(.discarded)
        case .failToStart(let message):
            recorder.cancel()
            continuation.yield(.failed(message: message))
        case .failDeleted:
            // The partial was unlinked mid-recording; the writer has been feeding a doomed inode
            // ever since. Unsalvageable (no relink API) — say so plainly.
            recorder.cancel()
            continuation.yield(.failed(message: Self.deletedMessage))
        case .finalizeStranded(let path, let reason):
            // The file is intact wherever it went, and the writer's fd still points at it —
            // finalize there and report a save, never a loss.
            do {
                _ = try await recorder.finish()
                var url = URL(fileURLWithPath: path)
                if url.pathExtension == "partial",
                   let final = try? OutputLocation.finalizePartial(url) {
                    url = final
                }
                continuation.yield(.finished(
                    url: url, reason: reason, droppedFrames: recorder.droppedFrameCount))
            } catch {
                // The file is at the moved-to path, outside the output folder, so launch recovery
                // won't sweep it — name where it actually is.
                Self.finalizeFailed(
                    error, message: Self.strandedFinalizeFailedMessage(path: path), on: continuation)
            }
        case .failWriteNeverBegan:
            // Cancel to drop the O_EXCL placeholder; fail with the folder named — nothing to finalize.
            recorder.cancel()
            let folder = recorder.outputURL.deletingLastPathComponent().lastPathComponent
            continuation.yield(.failed(message: Self.writeNeverBeganMessage(folder: folder)))
        case .finalizeNormal(let reason):
            do {
                let partial = try await recorder.finish()
                // A rename failure after a successful finish is NOT a lost recording — the complete
                // movie sits at the partial path; the next launch's sweep renames it.
                let url = (try? OutputLocation.finalizePartial(partial)) ?? partial
                continuation.yield(.finished(
                    url: url, reason: reason, droppedFrames: recorder.droppedFrameCount))
            } catch {
                // The `.partial` sits in the output folder; the next launch's sweep renames it.
                Self.finalizeFailed(error, message: Self.finalizeFailureMessage, on: continuation)
            }
        }
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

    /// Throw the take away: stop the engine and remove the file instead of finalizing it. Flagged
    /// before the stop so the event loop routes to `cancel()`; a `discarded` event follows.
    public func discard() async {
        discardRequested.set(true)
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
