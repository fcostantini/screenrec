import CoreMedia

/// One stored sample: the payload plus the two things the ring reasons about — its presentation
/// timestamp (duration eviction) and whether it's a keyframe (clip start).
struct RingEntry<Element> {
    let element: Element
    let pts: CMTime
    let isKeyframe: Bool
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
    private let limit: CMTime
    private let lock = NSLock()
    private var entries: [RingEntry<Element>] = []

    /// `capacity` is the target window (e.g. 60 s); `slack` (default 2 s, docs/01) keeps a little
    /// more so a keyframe at or before the N-second mark is still present when a clip is taken.
    init(capacity: CMTime, slack: CMTime = CMTime(seconds: 2, preferredTimescale: 600)) {
        limit = CMTimeAdd(capacity, slack)
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
        // `removeFirst()` is O(n), but eviction is ~1/append and n is a few thousand → negligible;
        // a hand-rolled circular buffer isn't worth the complexity (ADR-010, no deps).
        while let oldest = entries.first, let newest = entries.last,
              CMTimeCompare(CMTimeSubtract(newest.pts, oldest.pts), limit) > 0 {
            entries.removeFirst()
        }
    }

    /// A consistent copy of every entry (oldest → newest), taken under the lock so it can't tear
    /// against a concurrent `append`. Payloads are refcounted, so copying the array is cheap.
    func snapshot() -> [RingEntry<Element>] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    /// The entries for a clip of the last `seconds`: from the newest keyframe at or before
    /// `newest.pts − seconds` through the newest entry. Empty while the ring holds no qualifying
    /// keyframe yet (still filling). Keyframes ~1 s apart ⇒ the clip runs `seconds + ≤ 1 s`
    /// (docs/04 §6.2). Any fall-back-to-shorter policy is the muxer's (M5-T4), not the ring's.
    func clip(seconds: CMTime) -> [RingEntry<Element>] {
        lock.lock(); defer { lock.unlock() }
        guard let start = Self.clipStartIndex(in: entries, seconds: seconds) else { return [] }
        return Array(entries[start...])
    }

    /// Pure keyframe selection, so it's testable without a live ring or clock: the index of the
    /// newest keyframe whose pts ≤ `newest.pts − seconds` — the tightest start that still yields at
    /// least `seconds` — or nil if none qualifies.
    static func clipStartIndex(in entries: [RingEntry<Element>], seconds: CMTime) -> Int? {
        guard let newest = entries.last else { return nil }
        let cut = CMTimeSubtract(newest.pts, seconds)
        return entries.lastIndex { $0.isKeyframe && CMTimeCompare($0.pts, cut) <= 0 }
    }
}
