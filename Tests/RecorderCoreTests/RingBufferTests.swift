import CoreMedia
import Testing
@testable import RecorderCore

/// The ring reasons only over `pts` and `isKeyframe`, so `RingBuffer<Int>` exercises every path —
/// no `CMSampleBuffer` needed (M5-T1). `t` builds whole-second timestamps.
@Suite struct RingBufferTests {

    private static func t(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    @Test func evictsFromTheHeadKeepingCapacityPlusSlack() {
        let ring = RingBuffer<Int>(capacity: Self.t(4), slack: Self.t(2))   // keep ≤ 6 s
        for i in 0...10 { ring.append(i, pts: Self.t(Double(i)), isKeyframe: true) }
        let snap = ring.snapshot()
        // newest = 10; span ≤ 6 ⇒ oldest = 4. Entries with pts 4…10 survive.
        #expect(snap.first?.pts == Self.t(4))
        #expect(snap.last?.pts == Self.t(10))
        #expect(snap.count == 7)
    }

    @Test func keepsEverythingWhileUnderCapacity() {
        let ring = RingBuffer<Int>(capacity: Self.t(60))
        for i in 0...5 { ring.append(i, pts: Self.t(Double(i)), isKeyframe: false) }
        #expect(ring.snapshot().count == 6)
    }

    @Test func clipStartsAtTheTightestKeyframeBeforeTheCut() {
        let ring = RingBuffer<Int>(capacity: Self.t(60))
        // Keyframes on even seconds, plain frames on odd; pts 0…8, no eviction.
        for i in 0...8 { ring.append(i, pts: Self.t(Double(i)), isKeyframe: i % 2 == 0) }
        // newest = 8, seconds = 4 ⇒ cut = 4. Newest keyframe ≤ 4 is pts 4, not the older 0/2.
        let clip = ring.clip(seconds: Self.t(4))
        #expect(clip.first?.pts == Self.t(4))
        #expect(clip.last?.pts == Self.t(8))
        #expect(clip.first?.isKeyframe == true)
    }

    @Test func clipIsEmptyUntilAKeyframeReachesBackFarEnough() {
        let ring = RingBuffer<Int>(capacity: Self.t(60))
        ring.append(0, pts: Self.t(0), isKeyframe: true)
        ring.append(1, pts: Self.t(1), isKeyframe: false)
        // newest = 1, seconds = 30 ⇒ cut = −29; the only keyframe (pts 0) is newer than that.
        #expect(ring.clip(seconds: Self.t(30)).isEmpty)
    }

    @Test func clipIsEmptyWithNoKeyframes() {
        let ring = RingBuffer<Int>(capacity: Self.t(60))
        for i in 0...5 { ring.append(i, pts: Self.t(Double(i)), isKeyframe: false) }
        #expect(ring.clip(seconds: Self.t(2)).isEmpty)
    }

    @Test func clipStartIndexSelectsTheTightestKeyframeDirectly() {
        // The pure selection, off any ring or lock — the muxer (M5-T4) reads this index too.
        let entries = (0...8).map {
            RingEntry(element: $0, pts: Self.t(Double($0)), isKeyframe: $0 % 2 == 0)
        }
        // anchor 8, seconds 4 ⇒ cut 4; newest keyframe ≤ 4 is index 4.
        #expect(RingBuffer<Int>.clipStartIndex(in: entries, endingAt: Self.t(8), seconds: Self.t(4)) == 4)
        // No keyframe reaches back 30 s ⇒ nil; empty input ⇒ nil.
        #expect(RingBuffer<Int>.clipStartIndex(in: entries, endingAt: Self.t(8), seconds: Self.t(30)) == nil)
        #expect(RingBuffer<Int>.clipStartIndex(in: [], endingAt: Self.t(8), seconds: Self.t(1)) == nil)
        // An external anchor newer than the newest entry (static screen: the mux clock is the
        // audio ring) selects the newest keyframe that still precedes the shifted cut.
        #expect(RingBuffer<Int>.clipStartIndex(in: entries, endingAt: Self.t(60), seconds: Self.t(4)) == 8)
    }

    @Test func snapshotAndClipDuringConcurrentAppendStaySafe() async {
        // docs/04 TSan target: appends race snapshots/clips; the lock must make it clean.
        let ring = RingBuffer<Int>(capacity: Self.t(1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<2000 {
                    ring.append(i, pts: Self.t(Double(i) / 100), isKeyframe: i % 30 == 0)
                }
            }
            group.addTask { for _ in 0..<2000 { _ = ring.snapshot() } }
            group.addTask { for _ in 0..<2000 { _ = ring.clip(seconds: Self.t(0.5)) } }
        }
        // No content assertion — the point is a clean run under the thread sanitizer, no crash.
        #expect(ring.snapshot().isEmpty == false)
    }
}
