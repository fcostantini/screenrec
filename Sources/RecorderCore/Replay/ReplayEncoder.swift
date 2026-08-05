import CoreMedia
import Foundation
import VideoToolbox

/// Encodes `.screen` frames into a rolling `RingBuffer` for instant replay (docs/01, 02 §9).
/// A second `SampleRouter` consumer, independent of `MovieRecorder` — recording and replay tap
/// the same stream without knowing about each other.
///
/// Concurrency: `consume` runs on SCK's screen queue and must not block it (docs/01); the
/// VT session is `RealTime` and the encode call is asynchronous, with output arriving on
/// VideoToolbox's own thread. Shared state is `NSLock`-guarded; the lock is never held across
/// the encode call, so a synchronously-invoked output handler cannot deadlock.
public final class ReplayEncoder: SampleConsumer, @unchecked Sendable {
    /// A point-in-time read of the ring, for occupancy display (docs/03 M5-T2) and gate §6.1.
    public struct Stats: Sendable, Equatable {
        /// Seconds between the oldest and newest buffered frame.
        public let spanSeconds: Double
        public let sampleCount: Int
        public let keyframeCount: Int
        /// Total compressed payload bytes currently held (excludes CMSampleBuffer overhead).
        public let compressedBytes: Int
    }

    private let ring: RingBuffer<CMSampleBuffer>
    private let frameRateCap: Int
    /// Fires once on the first unrecoverable encoder error (session creation or encode failure),
    /// from a capture/VT thread. Mirrors `MovieRecorder.onCannotBeginWriting` — a dead encoder must
    /// surface, never wedge silently (ADR-007).
    private let onFailure: (@Sendable (String) -> Void)?

    private let lock = NSLock()
    private var session: VTCompressionSession?
    private var isPreparingSession = false
    private var failed = false
    private var invalidated = false

    /// Session bring-up allocates the hardware encoder and takes real time; it runs here, never
    /// on the SCK callback queue that triggers it (docs/01).
    private let setupQueue = DispatchQueue(
        label: "dev.fcostantini.screenrec.replay.setup", qos: .userInitiated)

    /// `seconds` is the replay window; the ring keeps `seconds + 2 s` slack so a keyframe at or
    /// before the window's start is still present when a clip is taken (docs/01).
    public init(seconds: Double, frameRateCap: Int, onFailure: (@Sendable (String) -> Void)? = nil) {
        ring = RingBuffer(capacity: ReplayWindow.capacity(seconds))
        self.frameRateCap = frameRateCap
        self.onFailure = onFailure
    }

    deinit {
        invalidate()
    }

    public func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        guard type == .screen, let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)

        lock.lock()
        if failed || invalidated {
            lock.unlock()
            return
        }
        guard let session else {
            // Frames arriving before the session is ready are dropped — the ring just starts a
            // beat later, and the first encoded frame is a keyframe regardless.
            if !isPreparingSession {
                isPreparingSession = true
                lock.unlock()
                // The format, not the buffer: bring-up reads nothing else, and SCK's IOSurface pool
                // is `queueDepth` deep (docs/01), so carrying a frame onto another queue would hold
                // one of five surfaces for as long as the VT session takes to build.
                if let format = CMSampleBufferGetFormatDescription(buffer) {
                    setupQueue.async { [weak self] in self?.prepareSession(for: format) }
                } else {
                    fail("The first frame carried no format description.")
                }
            } else {
                lock.unlock()
            }
            return
        }
        lock.unlock()

        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: imageBuffer, presentationTimeStamp: pts, duration: .invalid,
            frameProperties: nil, infoFlagsOut: nil
        ) { [weak self] status, flags, sample in
            self?.handleEncoderOutput(status: status, flags: flags, sample: sample)
        }
        // `kVTInvalidSessionErr` is the expected race with `invalidate()` mid-flight, not a failure.
        if status != noErr, status != kVTInvalidSessionErr {
            fail("Couldn't submit a frame to the replay encoder (VT error \(status)).")
        }
    }

    private func prepareSession(for format: CMFormatDescription) {
        do {
            let session = try Self.makeSession(for: format, frameRateCap: frameRateCap)
            lock.lock()
            // `invalidate()` may have run while the session was building.
            guard !invalidated else {
                lock.unlock()
                VTCompressionSessionInvalidate(session)
                return
            }
            self.session = session
            lock.unlock()
        } catch {
            fail((error as? EncoderError)?.message ?? error.localizedDescription)
        }
    }

    /// Change the replay window in place; buffered frames survive.
    public func updateWindow(seconds: Double) {
        ring.setCapacity(ReplayWindow.capacity(seconds))
    }

    public func stats() -> Stats {
        let entries = ring.snapshot()
        var keyframes = 0
        var bytes = 0
        for entry in entries {
            if entry.isKeyframe { keyframes += 1 }
            bytes += CMSampleBufferGetTotalSampleSize(entry.element)
        }
        return Stats(
            spanSeconds: RingBuffer<CMSampleBuffer>.span(of: entries),
            sampleCount: entries.count,
            keyframeCount: keyframes,
            compressedBytes: bytes
        )
    }

    /// Tears down the VT session. Encodes already in flight resolve as `kVTInvalidSessionErr`
    /// and are ignored; further frames are dropped. Safe to call more than once.
    public func invalidate() {
        lock.lock()
        invalidated = true
        let session = self.session
        self.session = nil
        lock.unlock()
        if let session { VTCompressionSessionInvalidate(session) }
    }

    /// The compressed samples for a clip of the last `seconds` before `anchor` (the mux clock —
    /// audio-derived, so a static screen's stale video ring doesn't shrink the window), starting
    /// on a keyframe (RingBuffer's contract). Falls back to everything from the oldest retained
    /// keyframe when the ring is younger than the window (armed < N seconds ago) — a short clip
    /// beats a refusal; the policy T1 assigned to the mux side. Empty ⇒ nothing buffered.
    func clip(seconds: Double, endingAt anchor: CMTime) -> [RingEntry<CMSampleBuffer>] {
        let window = ring.clip(endingAt: anchor, seconds: CMTime(seconds: seconds, preferredTimescale: 600))
        if !window.isEmpty { return window }
        let all = ring.snapshot()
        guard let firstKeyframe = all.firstIndex(where: \.isKeyframe) else { return [] }
        return Array(all[firstKeyframe...])
    }

    /// Newest encoded pts, nil while nothing is buffered.
    func newestPTS() -> CMTime? {
        ring.newestPTS()
    }

    /// Test seam; M5-T4's muxer gets its data through `clip(seconds:)`.
    func ringEntriesForTesting() -> [RingEntry<CMSampleBuffer>] {
        ring.snapshot()
    }

    /// Test seam: session bring-up is asynchronous, so tests wait for readiness before feeding.
    var isReadyForTesting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return session != nil
    }

    /// Blocks until every submitted frame has reached the output handler (≤ a frame of latency
    /// for a RealTime session). The muxer calls this before snapshotting so the frames nearest
    /// the trigger — the ones the user pressed save for — are in the ring.
    func completePendingFrames() {
        lock.lock()
        let session = self.session
        lock.unlock()
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    private func handleEncoderOutput(status: OSStatus, flags: VTEncodeInfoFlags, sample: CMSampleBuffer?) {
        guard status == noErr else {
            if status != kVTInvalidSessionErr {
                fail("The replay encoder failed on a frame (VT error \(status)).")
            }
            return
        }
        // RealTime sessions may shed load; a dropped replay frame is invisible to the user.
        guard !flags.contains(.frameDropped), let sample else { return }
        ring.append(
            sample,
            pts: CMSampleBufferGetPresentationTimeStamp(sample),
            isKeyframe: Self.isKeyframe(sample)
        )
    }

    private func fail(_ message: String) {
        lock.lock()
        let shouldNotify = !failed
        failed = true
        lock.unlock()
        if shouldNotify { onFailure?(message) }
    }

    /// `NotSync` absent ⇒ keyframe (02 §9) — encoders only attach it to delta frames.
    static func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[String: Any]],
              let first = attachments.first else {
            return true
        }
        return (first[kCMSampleAttachmentKey_NotSync as String] as? Bool) != true
    }

    private struct EncoderError: Error {
        let message: String
    }

    /// One HEVC session sized from the first frame's format description (same move as
    /// `MovieRecorder`). Properties per 02 §9; bitrate matches recording's Balanced math so the
    /// two encoders can't drift apart.
    private static func makeSession(
        for format: CMFormatDescription, frameRateCap: Int
    ) throws -> VTCompressionSession {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)

        var session: VTCompressionSession?
        let createStatus = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: dimensions.width, height: dimensions.height,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        guard createStatus == noErr, let session else {
            throw EncoderError(message: "Couldn't create the replay encoder (VT error \(createStatus)).")
        }

        let bitrate = BitrateModel.averageBitrate(
            width: Int(dimensions.width), height: Int(dimensions.height),
            frameRate: frameRateCap, preset: .balanced)
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            // No B-frames: PTS==DTS, so the ring stays monotone and M5-T4 muxes passthrough (ADR-005).
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            // Keyframe ≤ 1 s bounds a clip's start error to ≤ 1 s (docs/04 §6.2).
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 1,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_HEVC_Main_AutoLevel,
            kVTCompressionPropertyKey_AverageBitRate: bitrate,
        ]
        let propertyStatus = VTSessionSetProperties(session, propertyDictionary: properties as CFDictionary)
        guard propertyStatus == noErr else {
            VTCompressionSessionInvalidate(session)
            throw EncoderError(message: "Couldn't configure the replay encoder (VT error \(propertyStatus)).")
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
        return session
    }
}
