import CoreMedia
import Foundation

/// Buffers one audio source's recent PCM for instant replay (docs/01, 02 §9) — a
/// `SampleRouter` consumer alongside `ReplayEncoder`, instantiated once per audio source.
/// Payloads are deep copies: retaining SCK's own buffers for a minute would gamble on its
/// internal pools, and at PCM rates the copy costs ~0.5 MB/s. AAC encoding waits for mux time.
///
/// Concurrency: `consume` runs on an SCK audio queue, `stats` on the caller's; state is
/// `NSLock`-guarded (docs/01: locks, not actors, on the sample path).
public final class ReplayAudioRing: SampleConsumer, @unchecked Sendable {
    /// The latched PCM format, for occupancy display and duration × rate byte math.
    public struct Format: Sendable, Equatable {
        public let sampleRate: Double
        public let channels: Int
        /// Per sample, per channel — uniform across interleaved and planar layouts, unlike the
        /// ASBD's `mBytesPerFrame` (which is per-plane when non-interleaved; SCK's system audio
        /// arrives planar Float32, measured live 2026-07-16).
        public let bytesPerSample: Int

        public var bytesPerSecond: Int { Int(sampleRate) * channels * bytesPerSample }
    }

    /// A point-in-time read of the ring (docs/03 M5-T3 occupancy printout).
    public struct Stats: Sendable, Equatable {
        /// Seconds between the oldest and newest buffered sample's start.
        public let spanSeconds: Double
        public let sampleCount: Int
        /// PCM payload bytes currently held.
        public let bytes: Int
        /// Nil until the first buffer latches the source's format.
        public let format: Format?
        /// Times the source's format identity changed mid-arm (each one cleared the ring).
        public let formatChanges: Int
        /// Buffers lost to copy-allocation failure — distinguishes "nothing delivered" from
        /// "delivered but lost", which otherwise look identical from outside.
        public let copyFailures: Int
    }

    private let source: SourceType
    private let ring: RingBuffer<CMSampleBuffer>
    private let lock = NSLock()
    private var latchedASBD: AudioStreamBasicDescription?
    private var formatChanges = 0
    private var copyFailures = 0

    /// `seconds` is the replay window (+ 2 s slack, docs/01). `source` picks which audio this
    /// ring consumes; everything else routed to it is ignored.
    public init(source: SourceType, seconds: Double) {
        precondition(source != .screen, "an audio ring cannot consume screen frames")
        self.source = source
        ring = RingBuffer(capacity: ReplayWindow.capacity(seconds))
    }

    public func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        guard type == source,
              let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return }

        lock.lock()
        if let latched = latchedASBD, !asbd.hasSameIdentity(as: latched) {
            // The format changed (device/codec switch, 02 §4): the buffered audio is dead air
            // for "the last N seconds" and mixing layouts would corrupt the mux, so clear and
            // re-latch — replay keeps working at the new format, and unlike MovieRecorder
            // there's no welded writer input forcing a fail-stop.
            latchedASBD = asbd
            formatChanges += 1
            ring.removeAll()
        } else if latchedASBD == nil {
            latchedASBD = asbd
        }
        lock.unlock()

        guard let copy = Self.copyingPCM(of: buffer) else {
            lock.lock()
            copyFailures += 1
            lock.unlock()
            return
        }
        // Every PCM sample is a valid clip start, so the ring's keyframe search degenerates
        // to the tightest cut — exactly right for audio.
        ring.append(copy, pts: CMSampleBufferGetPresentationTimeStamp(buffer), isKeyframe: true)
    }

    /// Change the replay window in place; buffered audio survives.
    public func updateWindow(seconds: Double) {
        ring.setCapacity(ReplayWindow.capacity(seconds))
    }

    public func stats() -> Stats {
        lock.lock()
        let asbd = latchedASBD
        let changes = formatChanges
        let failures = copyFailures
        lock.unlock()

        let entries = ring.snapshot()
        var bytes = 0
        for entry in entries {
            // The block's data length, not CMSampleBufferGetTotalSampleSize — sample-size
            // bookkeeping reports 0 for planar audio (measured live), the payload never lies.
            if let data = CMSampleBufferGetDataBuffer(entry.element) {
                bytes += CMBlockBufferGetDataLength(data)
            }
        }
        return Stats(
            spanSeconds: RingBuffer<CMSampleBuffer>.span(of: entries),
            sampleCount: entries.count,
            bytes: bytes,
            format: asbd.map(Self.format(from:)),
            formatChanges: changes,
            copyFailures: failures)
    }

    /// The buffered PCM from `pts` onward (start-to-start: a buffer straddling `pts` is
    /// excluded, bounding the clip's leading audio gap to one buffer, ~20 ms). The muxer calls
    /// this with the clip's rebase origin.
    func entries(startingAt pts: CMTime) -> [RingEntry<CMSampleBuffer>] {
        ring.snapshot().filter { CMTimeCompare($0.pts, pts) >= 0 }
    }

    /// Newest buffered pts, nil while empty — one input to the muxer's window anchor.
    func newestPTS() -> CMTime? {
        ring.newestPTS()
    }

    /// Test seam; M5-T4's muxer gets its data through `entries(startingAt:)`.
    func ringEntriesForTesting() -> [RingEntry<CMSampleBuffer>] {
        ring.snapshot()
    }

    private static func format(from asbd: AudioStreamBasicDescription) -> Format {
        let channels = max(Int(asbd.mChannelsPerFrame), 1)
        let isPlanar = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        return Format(
            sampleRate: asbd.mSampleRate,
            channels: channels,
            bytesPerSample: isPlanar ? Int(asbd.mBytesPerFrame) : Int(asbd.mBytesPerFrame) / channels)
    }

    /// A new `CMSampleBuffer` whose block buffer is freshly allocated and filled from
    /// `buffer`'s — sharing only the (immutable) format description. Nil on allocation
    /// failure; dropping one buffer beats ringing memory SCK still owns.
    private static func copyingPCM(of buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let sourceData = CMSampleBufferGetDataBuffer(buffer),
              let format = CMSampleBufferGetFormatDescription(buffer) else { return nil }
        let length = CMBlockBufferGetDataLength(sourceData)

        var copied: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &copied) == noErr,
            let destination = copied
        else { return nil }
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(
            destination, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil,
            dataPointerOut: &pointer) == noErr,
            let raw = pointer,
            CMBlockBufferCopyDataBytes(
                sourceData, atOffset: 0, dataLength: length, destination: raw) == noErr
        else { return nil }

        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: destination, formatDescription: format,
            sampleCount: CMSampleBufferGetNumSamples(buffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(buffer),
            packetDescriptions: nil, sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }
}
