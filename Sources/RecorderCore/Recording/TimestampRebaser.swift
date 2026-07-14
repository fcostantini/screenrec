import CoreMedia

/// Rebases raw capture timestamps onto the recording timeline (docs/02 §5):
///
/// - the **epoch** is the first complete video frame's PTS, so the file starts at zero;
/// - audio arriving before the epoch is dropped, so audio never leads video;
/// - **pause** spans are removed via a cumulative offset — resume re-anchors on the next
///   complete video frame;
/// - output PTS is kept **strictly monotonic per track** (SCK occasionally reorders or
///   duplicates buffers, which would otherwise corrupt the writer).
///
/// Pure value type — no AVFoundation, no clock — so it is unit-testable in isolation and
/// composes with `MovieRecorder`, which owns one and mutates it under its own lock (M2-T4).
/// Pause/resume is exercised in M3, but the math lives here now.
///
/// Callers deliver only complete video frames as `.screen` (the `SampleRouter` already drops
/// incomplete ones), so the first `.screen` buffer seen is the epoch.
public struct TimestampRebaser {
    /// What to do with a buffer: drop it, or append it at the returned (rebased) PTS.
    public enum Decision: Equatable {
        case drop
        case emit(presentationTimeStamp: CMTime)
    }

    private var epoch: CMTime?
    private var pausedOffset: CMTime = .zero
    private var isPaused = false
    private var awaitingResumeFrame = false
    private var pauseStartPTS: CMTime = .zero
    private var lastEmitted: [SourceType: CMTime] = [:]

    public init() {}

    /// Decide a buffer's fate and, when kept, the PTS to append it at.
    public mutating func rebase(rawPTS: CMTime, source: SourceType) -> Decision {
        guard rawPTS.isNumeric else { return .drop }

        if isPaused {
            // Resume completes on the next complete video frame: fold the paused span into
            // the cumulative offset, then let this frame through as the first sample after.
            guard awaitingResumeFrame, source == .screen, epoch != nil else { return .drop }
            pausedOffset = CMTimeAdd(pausedOffset, CMTimeSubtract(rawPTS, pauseStartPTS))
            isPaused = false
            awaitingResumeFrame = false
        }

        let epochPTS: CMTime
        if let epoch {
            epochPTS = epoch
        } else {
            // First complete video frame anchors the timeline; earlier audio is dropped.
            guard source == .screen else { return .drop }
            epoch = rawPTS
            epochPTS = rawPTS
        }

        let rebased = CMTimeSubtract(CMTimeSubtract(rawPTS, epochPTS), pausedOffset)
        // Before the timeline origin (audio stamped ahead of the epoch) — drop.
        guard CMTimeCompare(rebased, .zero) >= 0 else { return .drop }
        // Strictly monotonic per track — reject a reorder or duplicate.
        if let last = lastEmitted[source], CMTimeCompare(rebased, last) <= 0 { return .drop }

        lastEmitted[source] = rebased
        return .emit(presentationTimeStamp: rebased)
    }

    /// Note the pause instant (raw capture PTS). No-op unless recording is underway; a second
    /// pause while already paused is ignored.
    public mutating func pause(atRawPTS pts: CMTime) {
        guard epoch != nil, !isPaused, pts.isNumeric else { return }
        isPaused = true
        awaitingResumeFrame = false
        pauseStartPTS = pts
    }

    /// Arm resume: the next complete video frame re-anchors the timeline and reopens the gate.
    public mutating func resume() {
        guard isPaused else { return }
        awaitingResumeFrame = true
    }
}
