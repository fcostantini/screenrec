import Foundation
import RecorderCore

/// What `AppState` needs from the armed-replay machinery. A protocol so transition wiring is
/// unit-testable with a spy — the real controller spins live capture engines.
@MainActor
public protocol ReplayControlling: AnyObject {
    /// Fired when the armed stream's own mic dies (docs/02 §4: gone for that stream's life).
    var onMicrophoneLost: (@MainActor () -> Void)? { get set }
    /// Fired when the pipeline itself fails (encoder death); the controller has already
    /// disarmed itself when this runs.
    var onPipelineFailure: (@MainActor (String) -> Void)? { get set }

    func arm(configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL)
    func disarm()
    /// A recording started: share its stream (docs/01's key property). The replay buffer
    /// restarts — a new stream is a new pts epoch; the pre-record buffer is deliberately not
    /// carried over.
    func recordingStarted(router: SampleRouter, configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL)
    /// The recording ended (any reason): leave its stream and, if armed, resume a private one.
    func recordingEnded(configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL)
    /// A capture-affecting setting changed (sources, quality, fps, buffer length): restart the
    /// armed stream so it captures what the pickers now say. The buffer resets — unavoidable,
    /// SCK binds sources once per stream (docs/02 §4).
    func configurationChanged(configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL)
    /// Output folder changes rebuild only the muxer — the buffer survives.
    func setOutputDirectory(_ url: URL)
    @discardableResult
    func requestSave(completion: @escaping @Sendable (Result<ReplayMuxer.SavedReplay, Error>) -> Void) -> Bool
}

/// Owns the armed instant-replay pipeline (docs/01, 02 §9): a capture stream feeding
/// `ReplayEncoder` + two `ReplayAudioRing`s + a `ReplayMuxer`. Idle-armed it runs its own
/// `CaptureEngine`; while a recording runs it rides that stream instead. Each attach builds a
/// fresh pipeline — rings are epoch-bound, and fresh beats clearing.
///
/// The armed state survives stream death (display sleep kills SCK streams): the controller
/// retries its own stream every few seconds until it comes back or the user disarms — armed is
/// a standing intent, and waking from a coffee break should not have silently turned it off.
@MainActor
public final class ReplayController: ReplayControlling {
    public var onMicrophoneLost: (@MainActor () -> Void)?
    public var onPipelineFailure: (@MainActor (String) -> Void)?

    private var isArmed = false
    /// The stream currently feeding the pipeline: our own engine, or a recording's router.
    private var ownEngine: CaptureEngine?
    private var ownEngineTask: Task<Void, Never>?
    private var attachedRouter: SampleRouter?

    private var encoder: ReplayEncoder?
    private var systemRing: ReplayAudioRing?
    private var microphoneRing: ReplayAudioRing?
    private var muxer: ReplayMuxer?

    /// Bumped on every deliberate teardown so a dead stream's restart loop from a previous
    /// epoch can't resurrect anything.
    private var epoch = 0

    private static let restartRetryInterval: Duration = .seconds(5)

    public init() {}

    public func arm(configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL) {
        guard !isArmed else { return }
        isArmed = true
        startOwnStream(configuration: configuration, seconds: seconds, outputDirectory: outputDirectory)
    }

    public func disarm() {
        guard isArmed else { return }
        isArmed = false
        tearDown()
    }

    public func recordingStarted(
        router: SampleRouter, configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL
    ) {
        guard isArmed else { return }
        tearDown()
        buildPipeline(
            on: router, configuration: configuration, seconds: seconds,
            outputDirectory: outputDirectory)
        attachedRouter = router
    }

    public func recordingEnded(
        configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL
    ) {
        guard isArmed else { return }
        tearDown()
        startOwnStream(configuration: configuration, seconds: seconds, outputDirectory: outputDirectory)
    }

    public func configurationChanged(
        configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL
    ) {
        // Own-stream mode only; while riding a recording, `recordingStarted` is the rebuild path.
        guard isArmed, attachedRouter == nil else { return }
        tearDown()
        startOwnStream(configuration: configuration, seconds: seconds, outputDirectory: outputDirectory)
    }

    public func setOutputDirectory(_ url: URL) {
        guard isArmed, let encoder, let systemRing else { return }
        muxer = ReplayMuxer(
            encoder: encoder, systemRing: systemRing, microphoneRing: microphoneRing,
            seconds: currentSeconds, outputDirectory: url)
        currentOutputDirectory = url
    }

    @discardableResult
    public func requestSave(
        completion: @escaping @Sendable (Result<ReplayMuxer.SavedReplay, Error>) -> Void
    ) -> Bool {
        guard let muxer else {
            completion(.failure(ReplayMuxerError.nothingBuffered))
            return true
        }
        return muxer.requestSave(completion: completion)
    }

    // MARK: - Pipeline

    // The live pipeline's parameters — what a retry rebuilds from, so a folder or setting
    // change between failure and retry isn't silently reverted to captured closure state.
    private var currentConfiguration = CaptureConfiguration()
    private var currentSeconds: Double = 60
    private var currentOutputDirectory = OutputLocation.defaultDirectory()

    private func buildPipeline(
        on router: SampleRouter, configuration: CaptureConfiguration, seconds: Double,
        outputDirectory: URL
    ) {
        currentConfiguration = configuration
        currentSeconds = seconds
        currentOutputDirectory = outputDirectory
        let currentEpoch = epoch
        let encoder = ReplayEncoder(
            seconds: seconds, frameRateCap: configuration.frameRateCap
        ) { [weak self] message in
            Task { @MainActor [weak self] in self?.pipelineFailed(message, inEpoch: currentEpoch) }
        }
        let systemRing = ReplayAudioRing(source: .systemAudio, seconds: seconds)
        router.attach(encoder)
        router.attach(systemRing)
        var microphoneRing: ReplayAudioRing?
        if configuration.microphone != .none {
            let ring = ReplayAudioRing(source: .microphone, seconds: seconds)
            router.attach(ring)
            microphoneRing = ring
        }
        self.encoder = encoder
        self.systemRing = systemRing
        self.microphoneRing = microphoneRing
        muxer = ReplayMuxer(
            encoder: encoder, systemRing: systemRing, microphoneRing: microphoneRing,
            seconds: seconds, outputDirectory: outputDirectory)
    }

    /// Detaches consumers, stops any private engine, and invalidates the epoch. Safe when
    /// nothing is up.
    private func tearDown() {
        epoch += 1
        if let attachedRouter {
            if let encoder { attachedRouter.detach(encoder) }
            if let systemRing { attachedRouter.detach(systemRing) }
            if let microphoneRing { attachedRouter.detach(microphoneRing) }
        }
        attachedRouter = nil
        encoder?.invalidate()
        encoder = nil
        systemRing = nil
        microphoneRing = nil
        muxer = nil
        ownEngineTask?.cancel()
        ownEngineTask = nil
        if let engine = ownEngine {
            ownEngine = nil
            Task { await engine.stop() }
        }
    }

    private func startOwnStream(
        configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL
    ) {
        let engine = CaptureEngine(configuration: configuration)
        buildPipeline(
            on: engine.router, configuration: configuration, seconds: seconds,
            outputDirectory: outputDirectory)
        ownEngine = engine
        let currentEpoch = epoch
        ownEngineTask = Task { [weak self] in
            for await event in engine.events {
                guard let self, self.epoch == currentEpoch else { return }
                switch event {
                case .microphoneLost:
                    onMicrophoneLost?()
                case .stopped, .failed:
                    // The stream died under us (display sleep/lock, SCK hiccup). Armed is a
                    // standing intent: wait out the condition and come back — the buffer is a
                    // new epoch either way.
                    await retryOwnStream(epoch: currentEpoch)
                    return
                default:
                    break
                }
            }
        }
        Task { await engine.start() }
    }

    private func retryOwnStream(epoch: Int) async {
        try? await Task.sleep(for: Self.restartRetryInterval)
        guard isArmed, self.epoch == epoch else { return }
        // Rebuild from the CURRENT parameters, not the failed stream's — the user may have
        // changed the output folder (or anything else) while the stream was down.
        let (configuration, seconds, outputDirectory) =
            (currentConfiguration, currentSeconds, currentOutputDirectory)
        tearDown()
        startOwnStream(configuration: configuration, seconds: seconds, outputDirectory: outputDirectory)
    }

    private func pipelineFailed(_ message: String, inEpoch failedEpoch: Int) {
        guard epoch == failedEpoch, isArmed else { return }
        isArmed = false
        tearDown()
        onPipelineFailure?("Screen encoding stopped working: \(message)")
    }
}
