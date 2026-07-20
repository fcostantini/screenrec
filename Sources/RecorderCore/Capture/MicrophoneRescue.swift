import CoreAudio
import CoreMedia
import Foundation
import ScreenCaptureKit
import os

/// Brings a lost microphone back (M8-T2, Route 2): a CoreAudio HAL device-list listener waits
/// for the rebind target, then a mic-only `SCStream` splices fixed-format buffers into the
/// same `SampleRouter` — the primary stream, recording file and replay rings are never
/// touched, and the loss window is an honest silent gap. Best-effort: no return ⇒ ADR-012's
/// notify-and-continue outcome. A fresh `SCStream` binds a previously-died device normally
/// (the poisoning is per-stream, docs/02 §4).
///
/// Owns the whole loss→wait→splice→re-arm cycle, including the `watchdog` that detects loss —
/// the engine attaches it to the router and polls it, but the cycle wiring lives here.
///
/// Thread-shape: loss arrives from the watchdog's poll, HAL notifications from a CoreAudio
/// queue, teardown from `cancel()` — state is lock-guarded, the lock is never held across
/// device enumeration or SCK calls, and the bind runs in its own `Task`.
final class MicrophoneRescue: @unchecked Sendable {

    /// Pure rebind decision — nil means keep waiting. `devices` is the live bindable list
    /// (`AudioInputs.available()`), so a returned target is one SCK can bind.
    static func rebindTarget(
        policy: MicrophoneRecovery, lostDeviceID: String, devices: [AudioInputDevice]
    ) -> String? {
        switch policy {
        case .sameDevice:
            return devices.contains { $0.uniqueID == lostDeviceID } ? lostDeviceID : nil
        case .systemDefault:
            return devices.first(where: \.isDefault)?.uniqueID
        }
    }

    /// How long the fresh stream gets to deliver its first buffer before the attempt is
    /// abandoned (a HAL-listed device can still be unbindable for a beat after return).
    /// Flat wait, deliberately: confirming at the first buffer would only advance the
    /// notification by ~2 s at the cost of a continuation race.
    static let bindConfirmationTimeout: TimeInterval = 3

    /// A rescue-stream death without a device-list change (an SCK-side failure) fires no HAL
    /// event, so the retry is self-scheduled; the delay keeps a persistently failing device
    /// from a tight bind loop.
    static let streamDeathRetryDelay: TimeInterval = 2

    private static let log = Logger(subsystem: "dev.fcostantini.screenrec", category: "capture")

    /// The loss detector for the session's mic path. The engine attaches it to the router and
    /// drives `check()`; the rescue chains the loss cycle behind the engine's event yield.
    let watchdog: MicrophoneWatchdog

    private let policy: MicrophoneRecovery
    private let pickedDeviceID: String
    private let router: SampleRouter
    /// Fired once per successful splice, off the rescue's queues (the engine yields the event).
    private let onSpliced: @Sendable () -> Void

    private let lock = NSLock()
    private enum State { case idle, waiting, binding, spliced, cancelled }
    private var state: State = .idle
    private var stream: SCStream?
    private var handler: RescueHandler?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private let listenerQueue = DispatchQueue(label: "dev.fcostantini.screenrec.micrescue")
    /// Never the listener queue: enumeration work there must not stall live mic delivery
    /// (docs/01 — never block an SCK callback queue).
    private let sampleQueue = DispatchQueue(label: "dev.fcostantini.screenrec.micrescue.samples")

    init(
        policy: MicrophoneRecovery, pickedDeviceID: String, router: SampleRouter,
        onLoss: @escaping @Sendable () -> Void, onSpliced: @escaping @Sendable () -> Void
    ) {
        self.policy = policy
        self.pickedDeviceID = pickedDeviceID
        self.router = router
        self.onSpliced = onSpliced
        watchdog = MicrophoneWatchdog(onLoss: onLoss)
        // Chained after init: neither object can capture the other during its own init.
        watchdog.setOnLoss { [weak self] in
            onLoss()
            self?.microphoneLost()
        }
    }

    /// The active mic (primary or a spliced rescue) died: drop any rescue stream and wait for
    /// the target to come back. Safe to call repeatedly.
    func microphoneLost() {
        lock.lock()
        guard state != .cancelled else { return lock.unlock() }
        state = .waiting
        let stale = takeStreamLocked()
        installListenerLocked()
        lock.unlock()
        stopStream(stale)
        attemptRebind()   // the target may already be present (systemDefault: the built-in)
    }

    /// Idempotent teardown; after this the rescue never binds again.
    func cancel() {
        lock.lock()
        guard state != .cancelled else { return lock.unlock() }
        state = .cancelled
        let stale = takeStreamLocked()
        let block = listenerBlock
        listenerBlock = nil
        lock.unlock()
        stopStream(stale)
        if let block {
            var address = AudioInputs.globalAddress(kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, block)
        }
    }

    deinit {
        cancel()
    }

    // MARK: - Return detection

    /// Must hold `lock`. The listener stays installed across loss cycles; one per rescue.
    private func installListenerLocked() {
        guard listenerBlock == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.attemptRebind()
        }
        var address = AudioInputs.globalAddress(kAudioHardwarePropertyDevices)
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, block) == noErr
        else {
            Self.log.error("mic rescue: HAL listener registration failed — no recovery this session")
            return
        }
        listenerBlock = block
    }

    private func attemptRebind() {
        lock.lock()
        let shouldScan = state == .waiting
        lock.unlock()
        guard shouldScan,
              let target = Self.rebindTarget(
                policy: policy, lostDeviceID: pickedDeviceID, devices: AudioInputs.available())
        else { return }

        lock.lock()
        guard state == .waiting else { return lock.unlock() }
        state = .binding
        lock.unlock()

        Task { [weak self] in
            await self?.bind(to: target)
        }
    }

    private func bind(to deviceID: String) async {
        let built: (SCStream, RescueHandler)?
        do {
            let content = try await SCShareableContent.forCapture()
            guard let display = content.displays.first else { throw RescueError.noDisplay }
            let handler = RescueHandler(router: router) { [weak self] in
                self?.rescueStreamDied()
            }
            // Mic-only: minimal video config, no `.screen`/`.audio` output attached;
            // `capturesAudio` stays on — the audio-config contract is one helper (docs/02 §1).
            let configuration = SCStreamConfiguration()
            configuration.width = 640
            configuration.height = 360
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 5)
            configuration.queueDepth = 5
            configuration.applyAudioCapture(microphoneID: deviceID)
            let stream = SCStream(
                filter: SCContentFilter(display: display, excludingWindows: []),
                configuration: configuration, delegate: handler)
            try stream.addStreamOutput(handler, type: .microphone, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
            built = (stream, handler)
        } catch {
            Self.log.info("mic rescue: bind attempt failed (\(error.localizedDescription, privacy: .public)) — waiting for the next device change")
            built = nil
        }

        guard let built else { return backToWaitingAfterFailedBind() }
        guard adopt(built.0, built.1) else { return stopStream(built.0) }

        // A HAL-listed device can still deliver nothing (dead-but-listed): confirm by first
        // buffer, else abandon and wait for the next change event.
        try? await Task.sleep(nanoseconds: UInt64(Self.bindConfirmationTimeout * 1_000_000_000))
        switch confirmDelivery(of: built.1) {
        case .spliced:
            Self.log.info("mic rescue: spliced \(deviceID, privacy: .public)")
            watchdog.rearm()
            onSpliced()
        case .abandoned:
            stopStream(built.0)
        case .stale:
            break   // cancelled or re-lost meanwhile; whoever moved the state owns cleanup
        }
    }

    // Sync helpers: NSLock may not be taken directly in an async frame.

    private func backToWaitingAfterFailedBind() {
        lock.lock()
        if state == .binding { state = .waiting }
        lock.unlock()
    }

    /// Adopts a freshly-built stream unless the state moved on (cancel/re-loss) meanwhile —
    /// false means the caller must stop the orphaned stream.
    private func adopt(_ stream: SCStream, _ handler: RescueHandler) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .binding else { return false }
        self.stream = stream
        self.handler = handler
        return true
    }

    private enum ConfirmOutcome { case spliced, abandoned, stale }

    private func confirmDelivery(of expected: RescueHandler) -> ConfirmOutcome {
        lock.lock()
        defer { lock.unlock() }
        guard state == .binding, handler === expected else { return .stale }
        if expected.hasDelivered {
            state = .spliced
            return .spliced
        }
        state = .waiting
        stream = nil
        handler = nil
        expected.mute()
        return .abandoned
    }

    /// The rescue stream itself died (device vanished again, SCK error): back to waiting, and
    /// retry unaided — see `streamDeathRetryDelay`.
    private func rescueStreamDied() {
        lock.lock()
        guard state == .spliced || state == .binding else { return lock.unlock() }
        state = .waiting
        let stale = takeStreamLocked()
        lock.unlock()
        stopStream(stale)
        listenerQueue.asyncAfter(deadline: .now() + Self.streamDeathRetryDelay) { [weak self] in
            self?.attemptRebind()
        }
    }

    // MARK: - Stream plumbing

    private enum RescueError: Error { case noDisplay }

    /// Must hold `lock`. Mutes the handler so an orphaned stream can't route buffers in the
    /// window before its async `stopCapture` lands.
    private func takeStreamLocked() -> SCStream? {
        handler?.mute()
        defer { stream = nil; handler = nil }
        return stream
    }

    private func stopStream(_ stream: SCStream?) {
        guard let stream else { return }
        Task { try? await stream.stopCapture() }
    }
}

/// Routes the rescue stream's mic buffers into the shared router through its own
/// `ResampledMicInput` (converter state is per-stream). Screen/audio outputs are never
/// attached, so only mic buffers arrive.
private final class RescueHandler: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let router: SampleRouter
    private let onStreamDied: @Sendable () -> Void
    private let resampler = ResampledMicInput()
    private let lock = NSLock()
    private var delivered = false
    private var isMuted = false

    var hasDelivered: Bool {
        lock.lock(); defer { lock.unlock() }
        return delivered
    }

    /// One-way: a muted handler belongs to a stream that is already being torn down.
    func mute() {
        lock.lock(); isMuted = true; lock.unlock()
    }

    init(router: SampleRouter, onStreamDied: @escaping @Sendable () -> Void) {
        self.router = router
        self.onStreamDied = onStreamDied
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .microphone else { return }
        lock.lock()
        delivered = true
        let muted = isMuted
        lock.unlock()
        guard !muted, let normalized = resampler.convert(sampleBuffer) else { return }
        router.route(normalized, type: .microphone)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamDied()
    }
}
