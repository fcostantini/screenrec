import Foundation

/// Stops a recording before it fills the volume (docs/02 §7). Once free space on the output
/// volume drops below `floorBytes`, `onLow` fires once and the owner stops cleanly with
/// `.diskAlmostFull` (fail-stop, ADR-007). One-shot — the recording is ending.
///
/// The space probe is injected so tests need no real disk; `check()` is caller-driven, keeping
/// this free of timers.
public final class DiskSpaceMonitor: @unchecked Sendable {
    /// docs/02 §7. Headroom, not a hard limit: the writer still needs to flush and finalize
    /// after the stop decision, so the floor must exceed what finalizing can cost.
    public static let defaultFloorBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// Suggested `check()` cadence. Disk fills slowly and reading volume capacity is cheap.
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
    /// not the output file: `resourceValues` throws for a path that doesn't exist yet, returning
    /// nil forever and silently disabling the guard.
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
    public static func availableBytes(forVolumeContaining url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        return availableBytes(
            importantUsage: values?.volumeAvailableCapacityForImportantUsage,
            rawCapacity: values?.volumeAvailableCapacity)
    }

    /// Reconciles the two capacity keys. Pure, so it's testable without mounting a volume.
    ///
    /// ⚠️ **Takes the larger of the two on purpose.** `volumeAvailableCapacityForImportantUsage`
    /// counts purgeable space on the boot volume, but returns **0 — not nil — on every non-boot
    /// volume**, which alone would read external drives and disk images as full. The raw count
    /// works everywhere; a genuinely full volume reports ~0 from both, so the guard still fires.
    static func availableBytes(importantUsage: Int64?, rawCapacity: Int?) -> Int64? {
        let raw = rawCapacity.map(Int64.init)
        guard importantUsage != nil || raw != nil else { return nil }
        return max(importantUsage ?? 0, raw ?? 0)
    }

    /// Fire `onLow` once if free space is under the floor. Silent when the probe can't read the
    /// volume: an unreadable capacity is not evidence of a full disk.
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
