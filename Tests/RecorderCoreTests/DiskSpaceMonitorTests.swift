import Foundation
import Testing
@testable import RecorderCore

/// The space probe is injected, so every branch runs without touching a real disk.
@Suite struct DiskSpaceMonitorTests {

    private static let floor: Int64 = 2 * 1024 * 1024 * 1024  // 2 GB

    @Test func firesOnceWhenSpaceDropsBelowTheFloor() async {
        // Exactly one event: we're stopping the recording, so repeated polls must not re-fire.
        await confirmation("low disk reported exactly once") { low in
            let monitor = DiskSpaceMonitor(
                floorBytes: Self.floor, availableBytes: { Self.floor - 1 }, onLow: { low() })
            monitor.check()
            monitor.check()
            monitor.check()
        }
    }

    @Test func doesNotFireWithRoomToSpare() async {
        await confirmation("no report above the floor", expectedCount: 0) { low in
            let monitor = DiskSpaceMonitor(
                floorBytes: Self.floor, availableBytes: { Self.floor * 10 }, onLow: { low() })
            for _ in 0..<5 { monitor.check() }
        }
    }

    @Test func doesNotFireExactlyAtTheFloor() async {
        // The floor is the reserve we must keep, so sitting exactly on it is not yet a failure.
        await confirmation("no report at exactly the floor", expectedCount: 0) { low in
            let monitor = DiskSpaceMonitor(
                floorBytes: Self.floor, availableBytes: { Self.floor }, onLow: { low() })
            monitor.check()
        }
    }

    @Test func doesNotFireWhenCapacityCannotBeRead() async {
        // An unreadable volume is not evidence of a full one — killing a healthy recording over
        // it would be worse than the thing being guarded against.
        await confirmation("no report when the probe returns nil", expectedCount: 0) { low in
            let monitor = DiskSpaceMonitor(
                floorBytes: Self.floor, availableBytes: { nil }, onLow: { low() })
            monitor.check()
        }
    }

    @Test func readsRealCapacityForAnExistingVolume() throws {
        // Guards the URLResourceValues keys themselves: a typo or a key Apple retires would make
        // the probe return nil forever, and the guard would never fire on a real full disk.
        // NOTE: this only ever probes the BOOT volume, which is exactly why it cannot catch the
        // external-volume bug below — that is what `reconciles…` exists for.
        let available = try #require(
            DiskSpaceMonitor.availableBytes(forVolumeContaining: FileManager.default.temporaryDirectory))
        #expect(available > 0)
    }

    // MARK: - Reconciling the two capacity keys

    @Test func reconcilesExternalVolumeReportingZeroImportantUsage() {
        // The bug this exists for (measured 2026-07-15 on an HFS+ disk image): every non-boot
        // volume reports importantUsage == 0 — NOT nil — while the raw count is correct. Trusting
        // importantUsage alone reads a healthy external drive as full and kills the recording on
        // the first poll. 0 is a successfully-read value, so no nil-guard can save us here.
        #expect(DiskSpaceMonitor.availableBytes(importantUsage: 0, rawCapacity: 102_363_136)
            == 102_363_136)
    }

    @Test func prefersImportantUsageOnTheBootVolume() {
        // Real figures from ~/Movies: importantUsage reads HIGHER than raw because it counts
        // purgeable space the OS would evict for us. Keep that — it's the whole point of the key.
        #expect(DiskSpaceMonitor.availableBytes(importantUsage: 764_860_797_513, rawCapacity: 726_307_803_136)
            == 764_860_797_513)
    }

    @Test func reportsGenuinelyFullVolumeAsFull() {
        // The reconciliation must not paper over a real full disk: both keys read ~0 there, so
        // taking the larger still returns ~0 and the guard fires.
        #expect(DiskSpaceMonitor.availableBytes(importantUsage: 0, rawCapacity: 0) == 0)
    }

    @Test func returnsNilOnlyWhenNeitherKeyIsReadable() {
        #expect(DiskSpaceMonitor.availableBytes(importantUsage: nil, rawCapacity: nil) == nil)
        #expect(DiskSpaceMonitor.availableBytes(importantUsage: nil, rawCapacity: 500) == 500)
        #expect(DiskSpaceMonitor.availableBytes(importantUsage: 500, rawCapacity: nil) == 500)
    }
}
