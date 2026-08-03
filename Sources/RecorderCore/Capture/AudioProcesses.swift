import CoreAudio
import Foundation

/// The apps a process tap can silence (M27-T3): those the audio system already knows.
///
/// ⚠️ **Not the same set as the on-screen apps `Everything Except` offers.** An app appears here
/// once it has played something and disappears again when it stops, so a menu built from
/// `SCShareableContent` would offer exclusions a tap cannot perform — silently, since excluding an
/// unknown process is a no-op (docs/07).
///
/// 🔴 **An app's audio often belongs to a helper, not to the app.** Discord's call audio comes from
/// `com.hnc.Discord.helper.Renderer`, a nested `.app` inside `Discord.app/Contents/Frameworks`
/// (measured). So a helper is reported under its own bundle ID, and silencing only the parent's
/// would leave the call audible — the family is matched by prefix, and the menu shows the parent.
public enum AudioProcesses {
    /// Bundle IDs **currently producing output**, deduplicated and **collapsed onto their parent
    /// app** — a menu offering "Discord Helper (Renderer)" would be naming an implementation detail.
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
                .filter { !$0.isEmpty }
                .map(parentBundleID(of:)))
    }

    /// Whether anything **we are not silencing** is producing output — the cross-check that
    /// separates "the tap is broken" from "the room is quiet" (M27-T4).
    ///
    /// 🔴 `excluding` is load-bearing, not a refinement. With it omitted, muting the only app that
    /// happens to be playing makes the tap correctly silent while the probe still says "something
    /// is playing", and the silence notice fires on a recording that is working perfectly —
    /// measured on a 5-minute take with Discord muted (docs/07). Daemons still count: the question
    /// is whether sound exists that we expect to capture, not whose it is.
    static func isAnythingPlaying(excluding silenced: [String] = []) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0
        else { return false }
        var objects = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr
        else { return false }
        let excluded = Set(silenced)
        return objects.contains { object in
            guard isRunningOutput(object) else { return false }
            guard let id = bundleID(of: object) else { return true }
            return !excluded.contains(parentBundleID(of: id))
        }
    }

    /// The app a bundle ID belongs to: `com.hnc.Discord.helper.Renderer` → `com.hnc.Discord`.
    /// Pure string work, so `RecorderCore` stays free of AppKit (docs/01) — and it holds for the
    /// Electron/Chromium shape every app here uses, where a helper's id extends its parent's.
    public static func parentBundleID(of bundleID: String) -> String {
        // A whole component, not a substring: `com.example.helperbee` is an app called helperbee,
        // and truncating it would silence something the user never named.
        let parts = bundleID.split(separator: ".", omittingEmptySubsequences: false)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "helper" }), index > 0 else {
            return bundleID
        }
        return parts[..<index].joined(separator: ".")
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
            // Match the family, not the name: silencing an app has to take its helpers with it,
            // since that is where the audio usually is.
            guard let bundleID = bundleID(of: object) else { continue }
            let parent = parentBundleID(of: bundleID)
            guard wanted.contains(parent) else { continue }
            found[parent, default: []].append(object)
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
