import CoreAudio
import Foundation

/// Verification surface for M30-T1: did the system-audio tap outlive the session that made it?
///
/// It has to run in the process that created the tap: the aggregate device is created
/// `kAudioAggregateDeviceIsPrivateKey`, so no other process can see it. Two cheaper-looking probes do
/// not work — a destroyed `AudioObjectID`'s property read still returns `noErr`, and
/// `kAudioHardwarePropertyTapList` still lists a destroyed tap (docs/07).
enum TapAudit {

    /// Must match `SystemAudioTap.aggregateDeviceName`, which lives in another module. A test in
    /// `RecorderCoreTests` pins that constant, so a rename fails a test rather than this check.
    private static let deviceName = "screenrec system audio"

    /// The HAL client caches the device list, so a query straight after a create or destroy can miss
    /// the change (docs/07).
    private static let settle: TimeInterval = 0.5

    /// Prints whether a tap survived. Called at the end of a `record` run under `--audit-tap`.
    static func report() {
        Thread.sleep(forTimeInterval: settle)
        let survivors = deviceNames().filter { $0.contains(deviceName) }
        if survivors.isEmpty {
            print("  ✓ audit-tap: no system-audio tap survived the session")
        } else {
            print("  ✗ audit-tap: \(survivors.count) tap device(s) still alive → \(survivors)")
        }
    }

    private static func deviceNames() -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { name(of: $0) }
    }

    private static func name(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // `Unmanaged`, not `CFString?`: these getters hand back a +1 string (the SystemAudioTap rule).
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
            let value
        else { return nil }
        return value.takeRetainedValue() as String
    }
}
