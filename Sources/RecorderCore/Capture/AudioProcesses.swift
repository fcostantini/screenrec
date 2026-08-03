import CoreAudio
import Foundation

/// The apps a process tap can silence (M27-T3): those the audio system already knows.
///
/// ⚠️ **Not the same set as the on-screen apps `Everything Except` offers.** An app appears here
/// once it has played something and disappears again when it stops, so a menu built from
/// `SCShareableContent` would offer exclusions a tap cannot perform — silently, since excluding an
/// unknown process is a no-op (docs/07).
public enum AudioProcesses {
    /// Bundle IDs **currently producing output**, deduplicated. Helper processes share their app's
    /// bundle ID, so a browser with three of them appears once.
    ///
    /// ⚠️ The process list alone is not this: it carries every process registered with the audio
    /// system — `caphost`, `audiomxd`, accessibility daemons — whether or not a sound is coming out.
    /// `kAudioProcessPropertyIsRunningOutput` is what separates "playing" from "known".
    public static func silenceableBundleIDs() -> Set<String> {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var objects = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr
        else { return [] }
        return Set(
            objects
                .filter { isRunningOutput($0) }
                .compactMap { bundleID(of: $0) }
                .filter { !$0.isEmpty })
    }

    /// Every audio object belonging to `bundleID` — a browser or a music app usually has several,
    /// and silencing only the first would leave the rest audible.
    static func objects(forBundleIDs bundleIDs: [String]) -> [String: [AudioObjectID]] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0
        else { return [:] }
        var objects = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr
        else { return [:] }

        let wanted = Set(bundleIDs)
        var found: [String: [AudioObjectID]] = [:]
        for object in objects {
            guard let bundleID = bundleID(of: object), wanted.contains(bundleID) else { continue }
            found[bundleID, default: []].append(object)
        }
        return found
    }

    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    private static func bundleID(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // `Unmanaged`, not `CFString?`: a raw pointer to a variable holding an object reference is
        // what the compiler warns about, and these getters hand back a +1 string.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
            let value
        else { return nil }
        return value.takeRetainedValue() as String
    }
}
