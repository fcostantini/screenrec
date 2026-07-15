import Foundation

/// Stops a recording before it fills the volume (docs/02 §7). Once free space on the output
/// volume drops below `floorBytes`, `onLow` fires once and the owner stops cleanly with
/// `.diskAlmostFull` — fail-stop per ADR-007: a shorter playable file beats a truncated one,
/// and the writer needs headroom to finalize at all.
///
/// One-shot: the recording is ending, so there is nothing to re-arm for.
///
/// The space probe is injected, so tests exercise every branch without touching a real disk.
/// `check()` is caller-driven (the owner polls it), keeping this free of timers.
final class DiskSpaceMonitor: @unchecked Sendable {
    /// docs/02 §7. Headroom, not a hard limit: the writer still needs to flush and finalize
    /// after we decide to stop, so the floor must exceed what finalizing can cost.
    static let defaultFloorBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// Suggested `check()` cadence. Disk fills slowly and reading volume capacity is cheap, so
    /// this trades nothing for a prompt stop.
    static let checkInterval: TimeInterval = 2

    private let floorBytes: Int64
    private let availableBytes: @Sendable () -> Int64?
    private let onLow: @Sendable () -> Void

    private let lock = NSLock()
    private var hasFired = false

    init(
        floorBytes: Int64 = DiskSpaceMonitor.defaultFloorBytes,
        availableBytes: @escaping @Sendable () -> Int64?,
        onLow: @escaping @Sendable () -> Void
    ) {
        self.floorBytes = floorBytes
        self.availableBytes = availableBytes
        self.onLow = onLow
    }

    /// Watches the volume holding `url`. ⚠️ Pass an **existing** path — the output *directory*,
    /// not the output file: `resourceValues` throws for a path that doesn't exist yet, which
    /// would return nil forever and silently disable the guard for the whole recording.
    convenience init(
        floorBytes: Int64 = DiskSpaceMonitor.defaultFloorBytes,
        watching url: URL,
        onLow: @escaping @Sendable () -> Void
    ) {
        self.init(
            floorBytes: floorBytes,
            availableBytes: { DiskSpaceMonitor.availableBytes(forVolumeContaining: url) },
            onLow: onLow)
    }

    /// Free space on the volume holding `url`, or nil if neither capacity key can be read.
    static func availableBytes(forVolumeContaining url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        return availableBytes(
            importantUsage: values?.volumeAvailableCapacityForImportantUsage,
            rawCapacity: values?.volumeAvailableCapacity)
    }

    /// Reconciles the two capacity keys — the pure half of the probe, so this volume-dependent
    /// behavior is testable without mounting a volume.
    ///
    /// ⚠️ **Takes the larger of the two on purpose.** `volumeAvailableCapacityForImportantUsage`
    /// is the key Apple recommends, and on the boot volume it rightly reads *higher* than the
    /// raw count because it includes purgeable space the OS would evict for us (measured
    /// 764 GB vs 726 GB). But it is only meaningful there: **every non-boot volume reports 0 —
    /// not nil** (measured 2026-07-15 on an HFS+ disk image: 0 against 102 MB of real free
    /// space). Trusting it alone reads every external drive, USB stick, SD card and disk image
    /// as full and kills those recordings on the first poll. The raw count works everywhere, so
    /// the max keeps purgeable-awareness on the boot volume without the false positive
    /// elsewhere — and a genuinely full volume reports ~0 from *both*, so the guard still fires.
    static func availableBytes(importantUsage: Int64?, rawCapacity: Int?) -> Int64? {
        let raw = rawCapacity.map(Int64.init)
        guard importantUsage != nil || raw != nil else { return nil }
        return max(importantUsage ?? 0, raw ?? 0)
    }

    /// Fire `onLow` once if free space is under the floor. Stays silent when the probe can't
    /// read the volume at all: an unreadable capacity is not evidence of a full disk, and
    /// killing a healthy recording over it would be worse than the thing we're guarding against.
    func check() {
        let available = availableBytes()  // a filesystem call — never hold the lock across it
        lock.lock()
        let low: Bool
        if !hasFired, let available, available < floorBytes {
            hasFired = true
            low = true
        } else {
            low = false
        }
        lock.unlock()
        if low { onLow() }  // outside the lock — it is non-reentrant
    }
}
