import CoreMedia

/// One stored sample: the payload plus the two things the ring reasons about — its presentation
/// timestamp (duration eviction) and whether it's a keyframe (clip start).
struct RingEntry<Element> {
    let element: Element
    let pts: CMTime
    let isKeyframe: Bool
}

/// The one statement of the replay-window contract: every ring capacity and resize goes through
/// here, so validation and the pts timescale can't drift between the video and audio rings.
enum ReplayWindow {
    /// Retained beyond the requested window so a keyframe at or before the N-second mark survives
    /// until a clip is taken. `ReplayFootprint` bills for it too — the rings really do hold it.
    static let slackSeconds: Double = 2
    static let slack = CMTime(seconds: slackSeconds, preferredTimescale: 600)

    static func capacity(_ seconds: Double) -> CMTime {
        // A non-finite or non-positive window silently breaks ring retention (eviction limit
        // ≤ 0 evicts everything); callers validate their inputs (M4-T4 pattern), so this is a
        // programmer error.
        precondition(
            seconds.isFinite && seconds > 0,
            "replay window must be a positive, finite number of seconds")
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }
}

/// A duration-bounded, lock-guarded rolling window of timestamped samples — the store behind
/// instant replay (docs/01, 02 §9). Generic so the video ring (compressed `CMSampleBuffer`s, M5-T2)
/// and the audio rings (PCM, M5-T3) share one implementation; the ring only ever looks at `pts`
/// and `isKeyframe`, never the payload.
///
/// Concurrency: `append` runs on a capture callback queue, `snapshot`/`clip` on the mux queue, so
/// state is guarded by `NSLock` rather than actor isolation (docs/01) — no async hop on the sample
/// path. Internal until M5-T2's `replay-arm` gives it a cross-module consumer.
final class RingBuffer<Element>: @unchecked Sendable {
    /// `capacity + slack`, precomputed — the widest span the ring retains. Recomputing it per
    /// append would put constant arithmetic on the sample hot path.
    private var limit: CMTime
    private let slack: CMTime
    private let lock = NSLock()
    private var entries: [RingEntry<Element>] = []

    /// `capacity` is the target window (e.g. 60 s); `slack` (default 2 s, docs/01) keeps a little
    /// more so a keyframe at or before the N-second mark is still present when a clip is taken.
    init(capacity: CMTime, slack: CMTime = ReplayWindow.slack) {
        self.slack = slack
        limit = CMTimeAdd(capacity, slack)
    }

    /// Change the retention window in place; contents survive. Shrinking evicts eagerly rather
    /// than on the next append — a static screen's ring may not append for minutes (02 §9), and
    /// the freed memory shouldn't wait for it.
    func setCapacity(_ capacity: CMTime) {
        lock.lock(); defer { lock.unlock() }
        limit = CMTimeAdd(capacity, slack)
        evictLocked()
    }

    /// Append the newest sample and evict from the head while the span exceeds `capacity + slack`.
    /// Lock-brief and allocation-light, so it's safe to call straight from a capture callback.
    ///
    /// Precondition: `pts` is non-decreasing across appends — the span is measured as
    /// `newest − oldest`, so a backward step would stall eviction. The replay pipeline guarantees
    /// it: no B-frames ⇒ PTS==DTS (ADR-005), delivered in capture order on a serial queue.
    func append(_ element: Element, pts: CMTime, isKeyframe: Bool) {
        lock.lock(); defer { lock.unlock() }
        entries.append(RingEntry(element: element, pts: pts, isKeyframe: isKeyframe))
        evictLocked()
    }

    /// Caller holds `lock`. Single-pass: a shrink can evict thousands of entries at once, and
    /// per-entry `removeFirst()` would go quadratic while an SCK-queue append waits on the lock.
    private func evictLocked() {
        guard let newest = entries.last else { return }
        var drop = 0
        while drop < entries.count - 1,
              CMTimeCompare(CMTimeSubtract(newest.pts, entries[drop].pts), limit) > 0 {
            drop += 1
        }
        if drop > 0 { entries.removeFirst(drop) }
    }

    /// A consistent copy of every entry (oldest → newest), taken under the lock so it can't tear
    /// against a concurrent `append`. Payloads are refcounted, so copying the array is cheap.
    func snapshot() -> [RingEntry<Element>] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    /// Drop everything (e.g. an audio format change makes the buffered content dead air).
    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }

    /// Oldest-to-newest span of a snapshot, NaN-guarded (docs/02 §10: CMTime → seconds can be
    /// NaN, and `Int(NaN)` traps downstream). Static and pure so every consumer's `stats()`
    /// shares one span policy.
    static func span(of entries: [RingEntry<Element>]) -> Double {
        guard let first = entries.first, let last = entries.last else { return 0 }
        let seconds = CMTimeSubtract(last.pts, first.pts).seconds
        return seconds.isFinite ? seconds : 0
    }

    /// The entries for a clip of the last `seconds`: from the newest keyframe at or before
    /// `newest.pts − seconds` through the newest entry. Empty while the ring holds no qualifying
    /// keyframe yet (still filling). Keyframes ~1 s apart ⇒ the clip runs `seconds + ≤ 1 s`
    /// (docs/04 §6.2). Any fall-back-to-shorter policy is the muxer's (M5-T4), not the ring's.
    func clip(seconds: CMTime) -> [RingEntry<Element>] {
        lock.lock(); defer { lock.unlock() }
        guard let newest = entries.last else { return [] }
        return clipLocked(endingAt: newest.pts, seconds: seconds)
    }

    /// Like `clip(seconds:)`, but the window ends at an external `anchor` — the mux clock, which
    /// may be newer than this ring's newest entry (frame-on-change: a static screen's video ring
    /// lags a live audio clock).
    func clip(endingAt anchor: CMTime, seconds: CMTime) -> [RingEntry<Element>] {
        lock.lock(); defer { lock.unlock() }
        return clipLocked(endingAt: anchor, seconds: seconds)
    }

    /// Newest stored pts, without copying the ring. Nil while empty.
    func newestPTS() -> CMTime? {
        lock.lock(); defer { lock.unlock() }
        return entries.last?.pts
    }

    /// How much the ring is holding, without copying it or walking it: `stats()` is O(n) over every
    /// entry (~7,200 at 2 min / 60 fps) and the menu that reads this must not wait (M6-T10).
    /// NaN-guarded for the same reason `span(of:)` is — docs/02 §10.
    func heldSeconds() -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let first = entries.first, let last = entries.last else { return 0 }
        let seconds = CMTimeSubtract(last.pts, first.pts).seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }

    private func clipLocked(endingAt anchor: CMTime, seconds: CMTime) -> [RingEntry<Element>] {
        guard let start = Self.clipStartIndex(in: entries, endingAt: anchor, seconds: seconds) else {
            return []
        }
        return Array(entries[start...])
    }

    /// Pure keyframe selection, so it's testable without a live ring or clock: the index of the
    /// newest keyframe whose pts ≤ `anchor − seconds` — the tightest start that still yields at
    /// least `seconds` before the anchor — or nil if none qualifies.
    static func clipStartIndex(
        in entries: [RingEntry<Element>], endingAt anchor: CMTime, seconds: CMTime
    ) -> Int? {
        let cut = CMTimeSubtract(anchor, seconds)
        return entries.lastIndex { $0.isKeyframe && CMTimeCompare($0.pts, cut) <= 0 }
    }
}
